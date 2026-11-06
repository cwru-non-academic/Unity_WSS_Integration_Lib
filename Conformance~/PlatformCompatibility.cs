using System.IO.Ports;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Text.Json;
using Wss.Transports;

// This executable compiles the unmodified production selector. Only its unused
// Unity log sink has a shim; no Unity lifecycle or engine execution is claimed.
internal static class PlatformCompatibility
{
    public static int Main(string[] args)
    {
        AssemblyLoadContext.Default.Resolving += (_, name) =>
        {
            // Ports must be selected by the .NET host's package metadata, as in
            // C#. Never substitute a test-owned Ports resolver for that behavior.
            if (name.Name == "System.IO.Ports") return null;
            string path = name.Name == "WSS.Transport.BLE.MacOS"
                ? Path.Combine(AppContext.BaseDirectory, "backends", "macos", name.Name + ".dll")
                : Path.Combine(AppContext.BaseDirectory, name.Name + ".dll");
            return File.Exists(path) ? AssemblyLoadContext.Default.LoadFromAssemblyPath(path) : null;
        };
        try
        {
            if (args.Length != 2) throw new ArgumentException("Expected projection directory and result path.");
            Run(args[0], args[1]);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void Run(string projection, string resultPath)
    {
        bool macDeclared = DeclaresMacOSBackend();
        AssertMacPayload(projection, macDeclared);
        AssertMacPayload(AppContext.BaseDirectory, macDeclared);
        string runtime = OperatingSystem.IsWindows() ? "win" : "unix";
        string relative = Path.Combine("runtimes", runtime, "lib", "net8.0", "System.IO.Ports.dll");
        using (var serial = WssTransportSupport.Create(WssTransportType.Serial, false,
            OperatingSystem.IsWindows() ? "COM1" : "/dev/ttyWssUnitySmoke")) { }
        Require(Path.GetFullPath(typeof(SerialPort).Assembly.Location) ==
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, relative)), "Wrong Serial runtime location.");
        Require(typeof(SerialPort).Assembly.GetName().Version.Major == 8, "Wrong Serial runtime version.");
        SameBytes(typeof(SerialPort).Assembly.Location, Path.Combine(projection, relative));
        Console.WriteLine("PASS: production Serial selection uses the exact packaged OS runtime; no port opened.");

        if (OperatingSystem.IsLinux())
        {
            nint native = NativeLibrary.Load(Path.Combine(AppContext.BaseDirectory,
                "runtimes", "linux-x64", "native", "libSystem.IO.Ports.Native.so"));
            NativeLibrary.Free(native);
        }

        string ble;
        if (OperatingSystem.IsWindows())
        {
            using var transport = WssTransportSupport.Create(WssTransportType.BLE, false, "name:ci-load-only");
            foreach (string name in new[] { "WSS.Transport.BLE.Windows", "WSS.Transport.BLE.Windows.Native" })
            {
                Assembly assembly = Assembly.Load(name);
                Require(AssemblyLoadContext.GetLoadContext(assembly) == AssemblyLoadContext.Default,
                    "BLE backend escaped the default load context.");
                string file = Path.Combine(AppContext.BaseDirectory, name + ".dll");
                Require(Path.GetFullPath(assembly.Location) == Path.GetFullPath(file), "Wrong BLE backend location.");
                SameBytes(file, Path.Combine(projection, name + ".dll"));
            }
            nint native = NativeLibrary.Load(Path.Combine(AppContext.BaseDirectory, "WssBleWindows.dll"));
            try
            {
                Require(!NativeLibrary.TryGetExport(native, "wss_test_mode", out _), "Production DLL is a test shim.");
                foreach (string export in new[] { "wss_ble_get_abi_info", "wss_ble_nus_connect", "wss_ble_nus_write", "wss_ble_nus_disconnect" })
                    Require(NativeLibrary.GetExport(native, export) != nint.Zero, "Missing native export: " + export);
            }
            finally { NativeLibrary.Free(native); }
            ble = "Windows production selector/backend/native exports loaded; no scan or connection";
        }
        else if (OperatingSystem.IsMacOS() && macDeclared)
        {
            for (int cycle = 0; cycle < 2; cycle++)
            {
                using var transport = WssTransportSupport.Create(WssTransportType.BLE, false, "name:ci-load-only");
                Require(!transport.IsConnected, "macOS construction unexpectedly connected.");
                object facade = typeof(WssBleTransport).GetField("_inner", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(transport)!;
                object backend = typeof(BleNusTransport).GetField("_backend", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(facade)!;
                Require(backend.GetType().FullName == "Wss.Transports.Backends.MacOS.MacBleNusBackend", "Unity selected the wrong macOS backend.");
            }
            ble = "macOS Mono production selector, repeated registration/construction/disposal and native ABI; no scan or connection";
        }
        else
        {
            try
            {
                using var unexpected = WssTransportSupport.Create(WssTransportType.BLE, false, "name:ci-load-only");
                throw new InvalidOperationException("Unsupported Unity platform unexpectedly selected a BLE backend.");
            }
            catch (PlatformNotSupportedException ex)
            {
                Require(ex.Message.Contains("Linux and other Unity targets are not supported") ||
                    (OperatingSystem.IsMacOS() && !macDeclared && ex.Message.Contains("macOS BLE requires")), "Unexpected unsupported BLE failure.");
            }
            Require(!AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name.StartsWith("WSS.Transport.BLE.Windows")),
                "Unsupported platform loaded the Windows BLE backend.");
            ble = "unsupported by this platform/payload; explicit rejection verified; no backend capability inferred";
        }
        foreach (Assembly shared in new[] { typeof(ITransport).Assembly, typeof(SerialPortTransport).Assembly, typeof(BleNusTransport).Assembly })
        {
            Require(AssemblyLoadContext.GetLoadContext(shared) == AssemblyLoadContext.Default, "Wrong shared load context.");
            Require(AppDomain.CurrentDomain.GetAssemblies().Count(a => a.GetName().Name == shared.GetName().Name) == 1,
                "Duplicate transport contract assembly.");
        }
        if (OperatingSystem.IsMacOS() && macDeclared)
        {
            string directory = Path.Combine(AppContext.BaseDirectory, "backends", "macos");
            Assembly backend = AppDomain.CurrentDomain.GetAssemblies().Single(a => a.GetName().Name == "WSS.Transport.BLE.MacOS");
            Require(Path.GetFullPath(backend.Location) == Path.Combine(directory, "WSS.Transport.BLE.MacOS.dll"), "Wrong macOS backend location.");
            Require(AssemblyLoadContext.GetLoadContext(backend) == AssemblyLoadContext.Default, "Wrong macOS load context.");
            SameBytes(backend.Location, Path.Combine(projection, "backends", "macos", "WSS.Transport.BLE.MacOS.dll"));
            string library = Path.Combine(directory, "libwss_macos_ble.dylib");
            SameBytes(library, Path.Combine(projection, "backends", "macos", "libwss_macos_ble.dylib"));
            var imports = backend.GetTypes().SelectMany(t => t.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
                .Select(m => m.GetCustomAttribute<DllImportAttribute>()).Where(a => a != null && a.Value.Contains("wss_macos_ble")).ToArray();
            Require(imports.Length > 0, "No macOS native ABI imports discovered.");
            nint native = NativeLibrary.Load(library);
            try
            {
                foreach (var import in imports) Require(NativeLibrary.GetExport(native, import.EntryPoint) != nint.Zero, "Missing macOS ABI export.");
            }
            finally { NativeLibrary.Free(native); }
            backend.GetType("Wss.Transports.Backends.MacOS.MacBleBackend", true)!.GetMethod("VerifyNativeAbi")!.Invoke(null, null);
            Console.WriteLine("PASS: macOS Mono selector and exact backend/native ABI loaded in .NET; Unity engine and Bluetooth I/O were not executed.");
        }
        Require(!AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name is "WinRT.Runtime" or "Microsoft.Windows.SDK.NET"),
            "Unexpected WinRT managed dependency.");
        Console.WriteLine("PASS: BLE " + ble);
        File.WriteAllText(resultPath, JsonSerializer.Serialize(new
        {
            schema = "wss-dotnet-platform-probe/v1", execution = "dotnet", unity_executed = false,
            os = RuntimeInformation.OSDescription, architecture = RuntimeInformation.ProcessArchitecture.ToString(),
            serial = "exact packaged OS runtime selected; construction only", ble, macos_backend_declared = macDeclared,
            macos_native_abi_verified = OperatingSystem.IsMacOS() && macDeclared, hardware_access = false
        }, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static void SameBytes(string actual, string expected) => Require(
        SHA256.HashData(File.ReadAllBytes(actual)).SequenceEqual(SHA256.HashData(File.ReadAllBytes(expected))),
        "Loaded bytes differ from verified projection: " + actual);

    private static bool DeclaresMacOSBackend()
    {
        Type loader = typeof(BleNusTransport).Assembly.GetType("Wss.Transports.Backends.BleBackendLoader", true)!;
        MethodInfo identity = loader.GetMethod("GetBackendIdentity", BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new InvalidOperationException("Unknown BLE capability contract; cannot infer unsupported macOS.");
        try
        {
            var mapping = ((string AssemblyName, string FactoryName))identity.Invoke(null, new object[] { "macos" })!;
            Require(mapping.AssemblyName == "WSS.Transport.BLE.MacOS" && mapping.FactoryName == "Wss.Transports.Backends.MacOS.MacBleNusBackendFactory", "Unexpected macOS capability mapping.");
            return true;
        }
        catch (TargetInvocationException e) when (e.InnerException is ArgumentOutOfRangeException argument && argument.ParamName == "platform") { return false; }
    }

    private static void AssertMacPayload(string root, bool declared)
    {
        string directory = Path.Combine(root, "backends", "macos");
        string[] actual = Directory.Exists(directory) ? Directory.GetFiles(directory, "*", SearchOption.AllDirectories)
            .Where(p => !p.EndsWith(".meta", StringComparison.Ordinal)).Select(Path.GetFileName).OrderBy(p => p, StringComparer.Ordinal).ToArray()! : Array.Empty<string>();
        string[] expected = declared ? new[] { "WSS.Transport.BLE.MacOS.dll", "libwss_macos_ble.dylib" } : Array.Empty<string>();
        Require(actual.SequenceEqual(expected), "Declared macOS capability requires exactly its managed/native pair; legacy facades must not contain orphan Mac binaries.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}

namespace UnityEngine
{
    internal static class Debug
    {
        public static void Log(object message) => throw new InvalidOperationException("Unity logging must not execute in the .NET load-only probe.");
        public static void LogWarning(object message) => Log(message);
        public static void LogError(object message) => Log(message);
    }
}

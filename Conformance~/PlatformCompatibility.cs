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
            string path = Path.Combine(AppContext.BaseDirectory, name.Name + ".dll");
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
        else
        {
            try
            {
                using var unexpected = WssTransportSupport.Create(WssTransportType.BLE, false, "name:ci-load-only");
                throw new InvalidOperationException("Non-Windows Unity BLE unexpectedly selected a backend.");
            }
            catch (PlatformNotSupportedException ex)
            {
                Require(ex.Message.Contains("Windows Editor or Windows standalone"), "Unexpected unsupported BLE failure.");
            }
            Require(!AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name.StartsWith("WSS.Transport.BLE.Windows")),
                "Unsupported platform loaded the Windows BLE backend.");
            ble = "unsupported by the production Unity selector; rejection verified (Linux Core BLE is not Unity BLE support)";
        }
        foreach (Assembly shared in new[] { typeof(ITransport).Assembly, typeof(SerialPortTransport).Assembly, typeof(BleNusTransport).Assembly })
        {
            Require(AssemblyLoadContext.GetLoadContext(shared) == AssemblyLoadContext.Default, "Wrong shared load context.");
            Require(AppDomain.CurrentDomain.GetAssemblies().Count(a => a.GetName().Name == shared.GetName().Name) == 1,
                "Duplicate transport contract assembly.");
        }
        Require(!AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name is "WinRT.Runtime" or "Microsoft.Windows.SDK.NET"),
            "Unexpected WinRT managed dependency.");
        Console.WriteLine("PASS: BLE " + ble);
        File.WriteAllText(resultPath, JsonSerializer.Serialize(new
        {
            schema = "wss-dotnet-platform-probe/v1", execution = "dotnet", unity_executed = false,
            os = RuntimeInformation.OSDescription, architecture = RuntimeInformation.ProcessArchitecture.ToString(),
            serial = "exact packaged OS runtime selected; construction only", ble, hardware_access = false
        }, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static void SameBytes(string actual, string expected) => Require(
        SHA256.HashData(File.ReadAllBytes(actual)).SequenceEqual(SHA256.HashData(File.ReadAllBytes(expected))),
        "Loaded bytes differ from verified projection: " + actual);

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

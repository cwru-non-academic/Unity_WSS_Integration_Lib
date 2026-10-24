using System;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;
using Wss.CoreModule;
using Wss.Transports;
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN
using Wss.Transports.Backends.Windows;
#endif

/// <summary>Selects the byte transport used by a Unity WSS component.</summary>
public enum WssTransportType
{
    /// <summary>Uses a serial COM port.</summary>
    Serial = 0,
    /// <summary>Uses a Windows BLE Nordic UART Service device.</summary>
    BLE = 1,
    /// <summary>Uses the existing simulated transport.</summary>
    Test = 2,
    /// <summary>Uses the shared in-memory Core conformance emulator.</summary>
    Conformance = 3
}

internal static class WssTransportSupport
{
    private static readonly object RegistrationGate = new object();
    private static bool _registered;

    // Field-only: safe in Unity's serialization callbacks, including worker threads.
    internal static void Migrate(ref int version, bool legacyTest, bool legacyForce,
        ref WssTransportType type, ref bool auto)
    {
        if (version != 0) return;
        type = legacyTest ? WssTransportType.Test : WssTransportType.Serial;
        auto = !legacyForce;
        version = 1;
    }

    internal static bool SelectionMatches(WssTransportType type, bool auto, string device,
        WssTransportType cachedType, bool cachedAuto, string cachedDevice) =>
        type == cachedType && (type == WssTransportType.Test ||
        (auto == cachedAuto && (auto || device == cachedDevice)));

    internal static ITransport Create(WssTransportType type, bool auto, string device)
    {
        switch (type)
        {
            case WssTransportType.Conformance:
                return new Wss.Testing.EmulatedWssTransport();
            case WssTransportType.Test:
                return new TestModeTransport(new TestModeTransportOptions());
            case WssTransportType.Serial:
                return new SerialPortTransport(SerialOptions(auto, device));
            case WssTransportType.BLE:
                var options = BleOptions(auto, device); // Validate before registration/native access.
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN
                lock (RegistrationGate)
                {
                    if (!_registered)
                    {
                        WindowsBleBackend.Register();
                        _registered = true;
                    }
                }
                return new WssBleTransport(new BleNusTransport(options));
#else
                throw new PlatformNotSupportedException("Unity WSS BLE requires Windows Editor or Windows standalone.");
#endif
            default:
                throw new ArgumentOutOfRangeException(nameof(type), type, "Unknown WSS transport type.");
        }
    }

    internal static SerialPortTransportOptions SerialOptions(bool auto, string device)
    {
        RequireManualSelector(auto, device, "Serial COM port");
        return new SerialPortTransportOptions
        {
            PortName = auto ? string.Empty : device,
            AutoSelectPort = auto
        };
    }

    internal static BleNusTransportOptions BleOptions(bool auto, string device)
    {
        if (auto) return new BleNusTransportOptions { AutoSelectDevice = true };
        RequireManualSelector(false, device, "BLE device name or id");
        bool id = device.StartsWith("id:", StringComparison.OrdinalIgnoreCase);
        bool name = device.StartsWith("name:", StringComparison.OrdinalIgnoreCase);
        string selector = id ? device.Substring(3) : name ? device.Substring(5) : device;
        RequireManualSelector(false, selector, "BLE device name or id after its prefix");
        return new BleNusTransportOptions
        {
            AutoSelectDevice = false,
            DeviceId = id ? selector : null,
            DeviceName = id ? null : selector
        };
    }

    private static void RequireManualSelector(bool auto, string device, string description)
    {
        if (!auto && string.IsNullOrWhiteSpace(device))
            throw new ArgumentException("A nonblank " + description + " is required when Auto is disabled.", nameof(device));
        if (!auto && device.IndexOf('\0') >= 0)
            throw new ArgumentException("The device selector must not contain a NUL character.", nameof(device));
    }

    // Called on Unity's main thread, before any BLE worker starts. Core logs may originate
    // from its own workers too, so marshal its shared sink rather than logging in continuations.
    internal static SynchronizationContext CaptureLogContext()
    {
        var context = SynchronizationContext.Current;
        if (context == null)
            throw new InvalidOperationException("BLE activation requires Unity's main-thread synchronization context.");
        Log.SetSink((level, message) => context.Post(_ =>
        {
            if (level == Log.LogLevel.Error) Debug.LogError(message);
            else if (level == Log.LogLevel.Warn) Debug.LogWarning(message);
            else Debug.Log(message);
        }, null));
        return context;
    }
}

// One adapter per activation. The core remains the only caller that starts connection.
// Shutdown permanently fences this activation; reset constructs a new adapter after cleanup.
internal sealed class WssBleTransport : ITransport
{
    private readonly ITransport _inner;
    private readonly object _gate = new object();
    private readonly CancellationTokenSource _activation = new CancellationTokenSource();
    private Task _connection;
    private bool _stopping;
    private bool _disposed;

    internal WssBleTransport(ITransport inner) { _inner = inner; }
    internal Task ConnectionTask { get { lock (_gate) return _connection; } }
    public bool IsConnected => _inner.IsConnected;
    public event Action<byte[]> BytesReceived
    {
        add => _inner.BytesReceived += value;
        remove => _inner.BytesReceived -= value;
    }

    public Task ConnectAsync(CancellationToken ct = default)
    {
        lock (_gate)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(WssBleTransport));
            if (_stopping) return Task.FromCanceled(new CancellationToken(true));
            return _connection ?? (_connection = Task.Run(async () =>
            {
                using (var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, _activation.Token))
                    await _inner.ConnectAsync(linked.Token).ConfigureAwait(false);
            }));
        }
    }

    internal void CancelConnection()
    {
        lock (_gate)
        {
            if (_stopping || _disposed) return;
            _stopping = true;
        }
        _activation.Cancel();
    }

    public async Task DisconnectAsync(CancellationToken ct = default)
    {
        CancelConnection();
        var connection = ConnectionTask;
        if (connection != null)
        {
            try { await connection.ConfigureAwait(false); }
            catch { /* The main-thread wrapper observes/report connection failures. */ }
        }
        await _inner.DisconnectAsync(ct).ConfigureAwait(false);
    }

    public Task SendAsync(byte[] data, CancellationToken ct = default) => _inner.SendAsync(data, ct);

    public void Dispose()
    {
        CancelConnection();
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
        }
        try { _inner.Dispose(); }
        finally { _activation.Dispose(); }
    }
}

// Holds cleanup independently of the detached component stack. A replacement may only be
// constructed after Pending completes; worker completion never calls InitializeStack.
internal sealed class WssBleCleanup
{
    internal Task Pending { get; private set; } = Task.CompletedTask;

    internal void Release(IStimulationCore owner, WssBleTransport transport,
        SynchronizationContext context, string description)
    {
        transport.CancelConnection();
        Pending = Task.Run(async () =>
        {
            var connection = transport.ConnectionTask;
            if (connection != null)
            {
                try { await connection.ConfigureAwait(false); }
                catch (OperationCanceledException) { /* Expected when this activation is released. */ }
                catch (Exception ex) { Report(context, description + " connection failed before cleanup: " + ex); }
            }
            try
            {
                if (owner != null) owner.Dispose();
                else transport.Dispose(); // Construction never transferred ownership.
            }
            catch (Exception ex)
            {
                Report(context, description + " cleanup failed: " + ex);
                if (owner != null)
                {
                    try { transport.Dispose(); } // Shutdown threw before transport disposal.
                    catch (Exception cleanupEx) { Report(context, description + " transport disposal failed: " + cleanupEx); }
                }
            }
        });
    }

    private static void Report(SynchronizationContext context, string message) =>
        context.Post(_ => Debug.LogError(message), null);
}

#nullable disable
using System;
using System.IO;
using Wss.CoreModule;
using Wss.ModelModule;
using Wss.Testing;

// Ordinary .NET host for the real Stimulation.Commands/Stack partial source.
// This is deliberately not a MonoBehaviour or a UnityEngine compatibility stub.
public partial class Stimulation : IDisposable
{
    private readonly string _directory;
    private IStimulationCore _owner;
    private IModelParamsCore _wss;
    private EmulatedWssTransport _transport;
    private IBasicStimulation basicWSS;
    private bool basicSupported;
    private bool _initialized;
    private bool _disposed;
    private IModelParamsCore WSS => _wss ?? throw new InvalidOperationException("The WSS stack is not initialized.");

    /// <summary>Creates an emulator-only host for the shared production wrapper source.</summary>
    /// <param name="directory">Existing directory containing canonical configuration files.</param>
    public Stimulation(string directory)
    {
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
            throw new ArgumentException("An existing fixture directory is required.", nameof(directory));
        _directory = Path.GetFullPath(directory);
    }

    /// <summary>Initializes the same Core, parameter and model layers used by the Unity host.</summary>
    public void Initialize()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(Stimulation));
        if (_initialized) return;
        _transport = new EmulatedWssTransport();
        try
        {
            _wss = WssStimulationStack.Build(_transport, _directory, 1, ref _owner);
            _wss.TryGetBasic(out basicWSS);
            basicSupported = basicWSS != null;
            _wss.Initialize();
            _initialized = true;
        }
        catch { Dispose(); throw; }
    }

    /// <summary>Advances the emulator on the calling thread.</summary>
    public void Tick() { if (_initialized) WSS.Tick(); }

    /// <summary>Gets observations from the real Core emulator.</summary>
    /// <param name="conformance">The active emulator observation interface, or null.</param>
    /// <returns>True after an emulator has been created.</returns>
    public bool TryGetConformance(out IWssConformance conformance)
    {
        conformance = (_transport as IConformanceProvider)?.Conformance;
        return conformance != null;
    }

    /// <summary>Releases the in-memory stack; no physical transport is available in this host.</summary>
    public void DisposeConformance() => Dispose();

    /// <summary>Advances the in-memory stack through the manual-host-shaped API.</summary>
    public void TickConformance() => Tick();

    /// <summary>Initializes the in-memory stack through the application entry point.</summary>
    public void resetRadio() => Initialize();

    /// <summary>Disposes the stack after its tick loop has stopped.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _initialized = false;
        try { if (_owner != null) _owner.Dispose(); else _transport?.Dispose(); }
        catch { _transport?.Dispose(); throw; }
        finally { _wss = null; _owner = null; _transport = null; basicWSS = null; basicSupported = false; }
    }
}

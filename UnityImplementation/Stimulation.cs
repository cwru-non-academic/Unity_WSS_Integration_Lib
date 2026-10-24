using UnityEngine;
using UnityEngine.Serialization;
using System.Collections.Generic;
using System;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using Wss.CoreModule;
using Wss.CalibrationModule;
using Wss.ModelModule;
using Wss.Transports;

/// <summary>
/// High-level Unity wrapper for the full stimulation model layer.
/// Extends <c>StimParamsLayer</c> with proportional and derivative control modes,
/// calibration constants, and model-based drive computation.
/// This is the top-level interface that user code should normally interact with.
/// </summary>
public partial class Stimulation : MonoBehaviour, ISerializationCallbackReceiver
{
    #region ==== Serialized Fields ====

    [SerializeField, Tooltip("Select Serial, Windows BLE/NUS, or simulated Test transport.")]
    private WssTransportType transportType = WssTransportType.Serial;
    [SerializeField, Tooltip("Automatically select a device. Ignored in Test mode.")]
    private bool auto = true;
    [SerializeField, FormerlySerializedAs("comPort"), Tooltip("Manual COM port or BLE advertised name. BLE accepts name: or id: (address/Windows ID). Ignored in Auto and Test modes.")]
    private string deviceName = "COM7";
    [SerializeField, HideInInspector, FormerlySerializedAs("testMode")] private bool legacyTestMode;
    [SerializeField, HideInInspector, FormerlySerializedAs("forcePort")] private bool legacyForcePort;
    [SerializeField, HideInInspector] private int transportSerializationVersion;

    /// <summary>Gets or sets manual selection for existing port-selection callers.</summary>
    public bool forcePort { get { MigrateTransport(); return !auto; } set { MigrateTransport(); auto = !value; } }
    /// <summary>Gets or sets the shared device selector for existing port-selection callers.</summary>
    public string comPort { get { MigrateTransport(); return deviceName; } set { MigrateTransport(); deviceName = value; } }

    private void MigrateTransport() => WssTransportSupport.Migrate(ref transportSerializationVersion,
        legacyTestMode, legacyForcePort, ref transportType, ref auto);
    /// <summary>Preserves legacy transport fields without performing device I/O.</summary>
    public void OnAfterDeserialize() => MigrateTransport();
    /// <summary>Marks field-only defaults before Unity serializes this component.</summary>
    public void OnBeforeSerialize() => MigrateTransport();
    private void OnValidate() => MigrateTransport();

    /// <summary>
    /// Maximum number of setup retries before failing initialization.
    /// </summary>
    [SerializeField] private int maxSetupTries = 5;

    #endregion

    private IModelParamsCore _wss;
    private string _conformanceConfigPath;
    private string ConfigPath => _conformanceConfigPath ?? Application.streamingAssetsPath;

    /// <summary>Configures an inactive, uninitialized component for the in-memory conformance emulator.</summary>
    /// <param name="directory">Existing directory containing the shared scenario configuration files.</param>
    /// <remarks>Call on Unity's main thread before resetRadio. This does not connect to hardware.</remarks>
    /// <exception cref="InvalidOperationException">The component is active or already owns a stack.</exception>
    /// <exception cref="ArgumentException">The configuration directory does not exist.</exception>
    public void ConfigureConformance(string directory)
    {
        if (isActiveAndEnabled || _stackOwner != null || _destroyed)
            throw new InvalidOperationException("Configure conformance before activating or initializing the component.");
        if (string.IsNullOrWhiteSpace(directory) || !System.IO.Directory.Exists(directory))
            throw new ArgumentException("An existing conformance configuration directory is required.", nameof(directory));
        transportSerializationVersion = 1;
        transportType = WssTransportType.Conformance;
        _conformanceConfigPath = System.IO.Path.GetFullPath(directory);
        maxSetupTries = 1;
    }

    /// <summary>Gets observations from the active shared emulator.</summary>
    /// <param name="conformance">The emulator's observation and evaluation interface, or null.</param>
    /// <returns>True when the active transport supplies conformance observations.</returns>
    public bool TryGetConformance(out Wss.Testing.IWssConformance conformance)
    {
        conformance = (_transport as Wss.Testing.IConformanceProvider)?.Conformance;
        return conformance != null;
    }

    /// <summary>Advances an explicitly configured emulator on Unity's main thread without Play mode.</summary>
    /// <exception cref="InvalidOperationException">The initialized transport is not the emulator.</exception>
    public void TickConformance()
    {
        if (!_initialized || !(_transport is Wss.Testing.EmulatedWssTransport))
            throw new InvalidOperationException("Only an initialized conformance emulator may be ticked explicitly.");
        WSS.Tick();
    }

    /// <summary>Disposes the emulator stack on Unity's main thread.</summary>
    /// <exception cref="InvalidOperationException">The active stack uses another transport.</exception>
    public void DisposeConformance()
    {
        if (_transport != null && !(_transport is Wss.Testing.EmulatedWssTransport))
            throw new InvalidOperationException("The active stack is not a conformance emulator.");
        DisposeStack();
    }
    private IModelParamsCore WSS => _wss ?? throw new InvalidOperationException("The WSS stack is not initialized. Enable the component or call resetRadio() to retry.");
    private IStimulationCore _stackOwner;
    private ITransport _transport;
    private bool _initialized;
    private bool _destroyed;
    private WssTransportType _stackTransportType;
    private bool _stackAuto;
    private string _stackPort;
    private string _stackConfigPath;
    private int _stackMaxSetupTries;
    private readonly WssBleCleanup _bleCleanup = new WssBleCleanup();
    private SynchronizationContext _bleLogContext;
    private bool _initializeAfterCleanup;
    private IBasicStimulation basicWSS;
    /// <summary>True after <see cref="StartStimulation"/> succeeds.</summary>
    public bool started = false;
    /// <summary>True if the underlying core exposes basic-stimulation APIs.</summary>
    private bool basicSupported = false;

    #region ==== Unity Lifecycle ====

    /// <summary>
    /// Defers stack construction to activation so port selection can be applied first.
    /// </summary>
    public void Awake()
    {
    }

    /// <summary>Initializes the WSS device connection when the component becomes active.</summary>
    void OnEnable() => InitializeStack();

    /// <summary>
    /// Advances communication tick and listens for debug input.
    /// Press <c>A</c> to reload configuration file manually.
    /// </summary>
    void Update()
    {
        if (_initializeAfterCleanup && _bleCleanup.Pending.IsCompleted)
        {
            _initializeAfterCleanup = false;
            if (!_destroyed && isActiveAndEnabled) InitializeStack();
        }
        if (!_initialized) return;
        var connection = (_transport as WssBleTransport)?.ConnectionTask;
        if (connection != null && (connection.IsFaulted || connection.IsCanceled))
        {
            Debug.LogError($"WSS {_stackTransportType} ({_stackPort}) connection failed: " +
                (connection.IsCanceled ? "cancelled" : connection.Exception?.GetBaseException().ToString()), this);
            DisposeStack();
            return;
        }
        try
        {
            WSS.Tick();
            if (Input.GetKeyDown(KeyCode.A))
                WSS.LoadConfigFile();
        }
        catch (Exception ex)
        {
            Debug.LogError($"WSS update failed: {ex}", this);
            DisposeStack();
        }
    }

    /// <summary>Ensures clean shutdown when the component is disabled.</summary>
    void OnDisable() => ShutdownStack();

    void OnDestroy()
    {
        _destroyed = true;
        DisposeStack();
    }

    void OnApplicationQuit()
    {
        _destroyed = true;
        DisposeStack();
    }

    private bool StackSettingsMatch() =>
        _wss != null &&
        _stackMaxSetupTries == maxSetupTries && _stackConfigPath == ConfigPath &&
        WssTransportSupport.SelectionMatches(transportType, auto, deviceName, _stackTransportType, _stackAuto, _stackPort);

    private void InitializeStack()
    {
        if (_destroyed) return;
        MigrateTransport();
        if (!_bleCleanup.Pending.IsCompleted)
        {
            _initializeAfterCleanup = true;
            return;
        }
        try
        {
            if (!StackSettingsMatch())
            {
                DisposeStack();
                if (!_bleCleanup.Pending.IsCompleted)
                {
                    _initializeAfterCleanup = true;
                    return;
                }
                if (transportType == WssTransportType.BLE)
                    _bleLogContext = WssTransportSupport.CaptureLogContext();
                _transport = WssTransportSupport.Create(transportType, auto, deviceName);

                // Each completed layer owns the layer below it; retain the latest owner for partial failures.
                _wss = WssStimulationStack.Build(_transport, ConfigPath, maxSetupTries, ref _stackOwner);
                _wss.TryGetBasic(out basicWSS);
                basicSupported = basicWSS != null;
                _stackTransportType = transportType;
                _stackAuto = auto;
                _stackPort = deviceName;
                _stackConfigPath = ConfigPath;
                _stackMaxSetupTries = maxSetupTries;
            }

            if (_initialized) return;
            _wss.Initialize();
            _initialized = true;
        }
        catch (Exception ex)
        {
            Debug.LogError($"WSS {transportType} ({deviceName}) initialization failed: {ex}", this);
            DisposeStack();
        }
    }

    private void ShutdownStack()
    {
        _initializeAfterCleanup = false;
        _initialized = false;
        if (_transport is WssBleTransport) { DisposeStack(); return; }
        if (_wss == null) return;
        try { _wss.Shutdown(); }
        catch (Exception ex)
        {
            Debug.LogError($"WSS shutdown failed: {ex}", this);
            DisposeStack();
        }
    }

    private void DisposeStack()
    {
        _initializeAfterCleanup = false;
        var owner = _stackOwner;
        var transport = _transport;
        _initialized = false;
        _wss = null;
        _stackOwner = null;
        _transport = null;
        basicWSS = null;
        basicSupported = false;
        if (transport is WssBleTransport ble)
        {
            _bleCleanup.Release(owner, ble, _bleLogContext, $"WSS BLE ({_stackPort ?? deviceName})");
            return;
        }
        try
        {
            if (owner != null) owner.Dispose();
            else transport?.Dispose(); // Core construction did not complete; ownership never transferred.
        }
        catch (Exception ex)
        {
            Debug.LogError($"WSS disposal failed: {ex}", this);
            // Core.Dispose can throw from Shutdown before reaching transport disposal.
            if (owner != null)
            {
                try { transport?.Dispose(); }
                catch (Exception cleanupEx) { Debug.LogError($"WSS transport disposal failed: {cleanupEx}", this); }
            }
        }
    }

    #endregion

    #region ==== Connection Management ====

    /// <summary>
    /// Updates the ratio for one event and completes when the DLL returns its acknowledgement.
    /// This reflection bridge is temporary until EditEventRatio is exposed by IBasicStimulation.
    /// </summary>
    public Task<string> UpdateEventRatioAsync(int eventId, int ratio, int targetWSS = 0)
    {
        if (eventId < 1) throw new ArgumentOutOfRangeException(nameof(eventId));
        if (ratio < 1) throw new ArgumentOutOfRangeException(nameof(ratio));

        object core = GetPrivateField(WSS, "_inner");
        core = GetPrivateField(core, "_core");
        object client = GetPrivateField(core, "_wss");
        if (client == null) throw new InvalidOperationException("The WSS client is not initialized.");

        MethodInfo editRatio = client.GetType().GetMethod(
            "EditEventRatio",
            BindingFlags.Instance | BindingFlags.Public,
            null,
            new[] { typeof(int), typeof(int), typeof(WssTarget), typeof(CancellationToken) },
            null);
        if (editRatio == null)
            throw new MissingMethodException("This WSS DLL does not expose EditEventRatio.");

        try
        {
            var task = editRatio.Invoke(client, new object[]
            {
                eventId, ratio, IntToWssTarget(targetWSS), CancellationToken.None
            }) as Task<string>;
            return task ?? throw new InvalidOperationException($"Event {eventId} ratio update was not queued.");
        }
        catch (TargetInvocationException ex) when (ex.InnerException != null)
        {
            throw ex.InnerException;
        }
    }

    private static object GetPrivateField(object instance, string fieldName)
    {
        if (instance == null) return null;
        FieldInfo field = instance.GetType().GetField(fieldName, BindingFlags.Instance | BindingFlags.NonPublic);
        return field?.GetValue(instance);
    }

    /// <summary>Explicitly closes the radio connection.</summary>
    public void releaseRadio() => ShutdownStack();

    /// <summary>Resets the radio by shutting down and reinitializing the device.</summary>
    public void resetRadio()
    {
        ShutdownStack();
        InitializeStack();
    }

    #endregion

}

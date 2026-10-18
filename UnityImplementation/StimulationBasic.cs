using System;
using UnityEngine;
using UnityEngine.Serialization;
using System.Threading;
using Wss.CoreModule;
using Wss.Transports;

/// <summary>
/// Basic Unity MonoBehaviour wrapper for the WSS stimulation core.
/// Handles initialization, configuration, and waveform control for connected WSS stimulators.
/// Designed as the simplest interface layer exposing low-level stimulation functionality.
/// </summary>
public class Stimulationbasic : MonoBehaviour, ISerializationCallbackReceiver
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

    private IStimulationCore _wss;
    private IStimulationCore WSS => _wss ?? throw new InvalidOperationException("The WSS stack is not initialized. Enable the component or call resetRadio() to retry.");
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
    private IBasicStimulation basicWSS => (IBasicStimulation)WSS;
    public bool started = false;

    #region ==== Unity Lifecycle ====

    /// <summary>
    /// Defers stack construction to activation so port selection can be applied first.
    /// </summary>
    public void Awake()
    {
    }

    /// <summary>
    /// Initializes the WSS device connection when the component becomes active.
    /// </summary>
    void OnEnable() => InitializeStack();

    /// <summary>
    /// Performs periodic updates and tick cycles for communication and task execution.
    /// Press <c>A</c> key to manually reload the configuration file for testing.
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

    /// <summary>
    /// Ensures proper device shutdown when the component is disabled.
    /// </summary>
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
        _stackMaxSetupTries == maxSetupTries && _stackConfigPath == Application.streamingAssetsPath &&
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

                _stackOwner = new WssStimulationCore(_transport, new WssStimulationCoreOptions
                {
                    ConfigPath = Application.streamingAssetsPath,
                    MaxSetupTries = maxSetupTries
                });
                _wss = _stackOwner;
                _stackTransportType = transportType;
                _stackAuto = auto;
                _stackPort = deviceName;
                _stackConfigPath = Application.streamingAssetsPath;
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
    /// Explicitly releases the radio connection.
    /// </summary>
    public void releaseRadio() => ShutdownStack();

    /// <summary>
    /// Performs a radio reset by shutting down and re-initializing the connection.
    /// </summary>
    public void resetRadio()
    {
        ShutdownStack();
        InitializeStack();
    }

    #endregion

    #region ==== Stimulation Methods ====

    /// <summary>
    /// Sends an analog stimulation command to a mapped channel.
    /// </summary>
    /// <param name="finger">Finger name or channel alias (e.g., "index" or "ch2").</param>
    /// <param name="PW">Pulse width in microseconds.</param>
    /// <param name="amp">Amplitude in milliamps (default = 3).</param>
    /// <param name="IPI">Inter-pulse interval in milliseconds (default = 10).</param>
    public void StimulateAnalog(string finger, int PW, int amp = 3, int IPI = 10)
    {
        int channel = FingerToChannel(finger);
        WSS.StimulateAnalog(channel, PW, amp, IPI);
    }

    /// <inheritdoc cref="IStimulationCore.StartStim(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void StartStimulation() => WSS.StartStim(WssTarget.Broadcast);

    /// <inheritdoc cref="IStimulationCore.StopStim(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void StopStimulation() => WSS.StopStim(WssTarget.Broadcast);

    /// <inheritdoc cref="IBasicStimulation.Save(WssTarget)"/>
    public void Save(int targetWSS) => basicWSS.Save(IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.Save(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void Save() => basicWSS.Save(WssTarget.Broadcast);

    /// <inheritdoc cref="IBasicStimulation.Load(WssTarget)"/>
    public void load(int targetWSS) => basicWSS.Load(IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.Load(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void load() => basicWSS.Load(WssTarget.Broadcast);

    /// <inheritdoc cref="IBasicStimulation.Request_Configs(int,int,WssTarget)"/>
    public void request_Configs(int targetWSS, int command, int id)
        => basicWSS.Request_Configs(command, id, IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(int[],int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void updateWaveform(int[] waveform, int eventID)
        => basicWSS.UpdateWaveform(waveform, eventID, WssTarget.Broadcast);

    public void updateWaveform(int targetWSS, int[] waveform, int eventID)
        => basicWSS.UpdateWaveform(waveform, eventID, IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.UpdateEventShape(int,int,int,WssTarget)"/>
    public void updateWaveform(int cathodicWaveform, int anodicWaveform, int eventID)
        => basicWSS.UpdateEventShape(cathodicWaveform, anodicWaveform, eventID, WssTarget.Broadcast);

    public void updateWaveform(int targetWSS, int cathodicWaveform, int anodicWaveform, int eventID)
        => basicWSS.UpdateEventShape(cathodicWaveform, anodicWaveform, eventID, IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(WaveformBuilder,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void updateWaveform(WaveformBuilder waveform, int eventID)
        => basicWSS.UpdateWaveform(waveform, eventID, WssTarget.Broadcast);

    public void updateWaveform(int targetWSS, WaveformBuilder waveform, int eventID)
        => basicWSS.UpdateWaveform(waveform, eventID, IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.LoadWaveform(string,int)"/>
    public void loadWaveform(string fileName, int eventID)
        => basicWSS.LoadWaveform(fileName, eventID);

    /// <inheritdoc cref="IBasicStimulation.WaveformSetup(WaveformBuilder,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void WaveformSetup(WaveformBuilder wave, int eventID)
        => basicWSS.WaveformSetup(wave, eventID, WssTarget.Broadcast);

    public void WaveformSetup(int targetWSS, WaveformBuilder wave, int eventID)
        => basicWSS.WaveformSetup(wave, eventID, IntToWssTarget(targetWSS));

    /// <inheritdoc cref="IBasicStimulation.UpdateIPD(int,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void UpdateIPD(int ipd, int eventID)
        => basicWSS.UpdateIPD(ipd, eventID, WssTarget.Broadcast);

    /// <inheritdoc cref="IBasicStimulation.UpdateIPD(int,int,WssTarget)"/>
    public void UpdateIPD(int targetWSS, int ipd, int eventID)
        => basicWSS.UpdateIPD(ipd, eventID, IntToWssTarget(targetWSS));

    #endregion

    #region ==== Getters ====

    /// <summary>Returns <c>true</c> if the device has completed setup and is ready.</summary>
    public bool Ready() => _initialized && _wss != null && _wss.Ready();

    /// <summary>Returns <c>true</c> if stimulation is currently active.</summary>
    public bool Started() => _initialized && _wss != null && _wss.Started();

    /// <summary>Provides access to the core configuration controller.</summary>
    public CoreConfigController GetCoreConfigCTRL() => WSS.GetCoreConfigController();

    #endregion

    #region ==== Utility ====

    private WssTarget IntToWssTarget(int i) =>
        i switch
        {
            0 => WssTarget.Broadcast,
            1 => WssTarget.Wss1,
            2 => WssTarget.Wss2,
            3 => WssTarget.Wss3,
            _ => WssTarget.Wss1
        };

    private int FingerToChannel(string fingerOrAlias)
    {
        if (string.IsNullOrWhiteSpace(fingerOrAlias)) return 0;

        if (fingerOrAlias.StartsWith("ch", StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(fingerOrAlias.Substring(2), out var n))
            return n;

        return fingerOrAlias.ToLowerInvariant() switch
        {
            "thumb" => 1,
            "index" => 2,
            "middle" => 3,
            "ring" => 4,
            "pinky" or "little" => 5,
            _ => 0
        };
    }

    #endregion
}

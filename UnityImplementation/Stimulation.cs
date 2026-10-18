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
public class Stimulation : MonoBehaviour, ISerializationCallbackReceiver
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
                _stackOwner = new WssStimulationCore(_transport, new WssStimulationCoreOptions
                {
                    ConfigPath = ConfigPath,
                    MaxSetupTries = maxSetupTries
                });
                _stackOwner = new StimParamsLayer(_stackOwner, ConfigPath);
                _stackOwner = new ModelParamsLayer((IStimParamsCore)_stackOwner, ConfigPath);
                _wss = (IModelParamsCore)_stackOwner;
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

    #region ==== Stimulation methods: basic and core ====

    /// <summary>
    /// Direct analog stimulation using raw parameters.
    /// Recommended only for discrete-sensor triggers.
    /// </summary>
    /// <param name="finger">Finger label or alias (e.g., "index" or "ch2").</param>
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

    /// <summary>Stops stimulation for a selected WSS.</summary>
    /// <param name="targetWSS">Target index: zero broadcasts; one through three select a WSS.</param>
    public void StopStimulation(int targetWSS) => WSS.StopStim(IntToWssTarget(targetWSS));

    /// <summary>Updates an Event ratio through the shared basic-stimulation API.</summary>
    /// <param name="targetWSS">Target index: zero broadcasts; one through three select a WSS.</param>
    /// <param name="ratio">Event ratio accepted by the Core API.</param>
    /// <param name="eventID">Event identifier accepted by the Core API.</param>
    public void UpdateEventRatio(int targetWSS, int ratio, int eventID)
    {
        if (!basicSupported) throw new InvalidOperationException("Basic stimulation is not supported.");
        basicWSS.UpdateEventRatio(ratio, eventID, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.Save(WssTarget)"/>
    public void Save(int targetWSS)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.Save(IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.Save(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void Save()
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.Save(WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.Load(WssTarget)"/>
    public void load(int targetWSS)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.Load(IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.Load(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void load()
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.Load(WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.Request_Configs(int,int,WssTarget)"/>
    public void request_Configs(int targetWSS, int command, int id)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.Request_Configs(command, id, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(int[],int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void updateWaveform(int[] waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(int[],int,WssTarget)"/>
    public void updateWaveform(int targetWSS, int[] waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateEventShape(int,int,int,WssTarget)"/>
    public void updateWaveform(int cathodicWaveform, int anodicWaveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateEventShape(cathodicWaveform, anodicWaveform, eventID, WssTarget.Broadcast);
    }

    /// <summary>
    /// Selects predefined or custom waveform shapes for a specific WSS target.
    /// </summary>
    public void updateWaveform(int targetWSS, int cathodicWaveform, int anodicWaveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateEventShape(cathodicWaveform, anodicWaveform, eventID, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(WaveformBuilder,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void updateWaveform(WaveformBuilder waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, WssTarget.Broadcast);
    }

    /// <summary>Loads a waveform definition from JSON for a target unit.</summary>
    public void updateWaveform(int targetWSS, WaveformBuilder waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, IntToWssTarget(targetWSS));
    }

    /// <summary>Loads a waveform file into memory.</summary>
    public void loadWaveform(string fileName, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.LoadWaveform(fileName, eventID);
    }

    /// <summary>Defines a custom waveform for an event slot on all units.</summary>
    public void WaveformSetup(WaveformBuilder wave, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.WaveformSetup(wave, eventID, WssTarget.Broadcast);
    }

    /// <summary>Defines a custom waveform for an event slot on a specific unit.</summary>
    public void WaveformSetup(int targetWSS, WaveformBuilder wave, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.WaveformSetup(wave, eventID, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateIPD(int,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units.</remarks>
    public void UpdateIPD(int ipd, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateIPD(ipd, eventID, WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateIPD(int,int,WssTarget)"/>
    public void UpdateIPD(int targetWSS, int ipd, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported."); return; }
        basicWSS.UpdateIPD(ipd, eventID, IntToWssTarget(targetWSS));
    }

    #endregion

    #region ==== Stimulation methods: params and model layers ====

    /// <summary>
    /// Normalized drive [0..1]. Computes PW via per-finger calibration and model constants, then stimulates.
    /// </summary>
    public void StimulateNormalized(string finger, float magnitude)
    {
        int ch = FingerToChannel(finger);
        WSS.StimulateNormalized(ch, magnitude);
    }

    /// <summary>Returns last computed pulse width for the specified finger.</summary>
    public int GetStimIntensity(string finger)
    {
        int ch = FingerToChannel(finger);
        return (int)WSS.GetStimIntensity(ch);
    }

    /// <summary>Saves model-layer parameters JSON to disk.</summary>
    public void SaveParamsJson() => WSS.SaveParamsJson();

    /// <summary>Loads model-layer parameters JSON from default location.</summary>
    public void LoadParamsJson() => WSS.LoadParamsJson();

    /// <summary>Loads model-layer parameters JSON from a specified path.</summary>
    public void LoadParamsJson(string pathOrDir) => WSS.LoadParamsJson(pathOrDir);

    /// <summary>Sets a parameter by dotted key (e.g., "stim.ch.1.amp").</summary>
    public void AddOrUpdateStimParam(string key, float value) => WSS.AddOrUpdateStimParam(key, value);

    /// <summary>Gets a parameter by dotted key.</summary>
    public float GetStimParam(string key) => WSS.GetStimParam(key);

    /// <summary>Attempts to read a parameter by key, returns <c>true</c> on success.</summary>
    public bool TryGetStimParam(string key, out float v) => WSS.TryGetStimParam(key, out v);

    /// <summary>Returns a dictionary copy of all current stimulation parameters.</summary>
    public Dictionary<string, float> GetAllStimParams() => WSS.GetAllStimParams();

    /// <summary>Sets per-finger amplitude in milliamps.</summary>
    public void SetChannelAmp(string finger, float mA)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelAmp(ch, mA);
    }

    /// <summary>Sets per-finger minimum PW in microseconds.</summary>
    public void SetChannelPWMin(string finger, int us)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelPWMin(ch, us);
    }

    /// <summary>Sets per-finger maximum PW in microseconds.</summary>
    public void SetChannelPWMax(string finger, int us)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelPWMax(ch, us);
    }

    /// <summary>Sets per-finger IPI in milliseconds.</summary>
    public void SetChannelIPI(string finger, int ms)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelIPI(ch, ms);
    }

    /// <summary>Gets per-finger amplitude in milliamps.</summary>
    public float GetChannelAmp(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelAmp(ch);
    }

    /// <summary>Gets per-finger minimum PW in microseconds.</summary>
    public int GetChannelPWMin(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelPWMin(ch);
    }

    /// <summary>Gets per-finger maximum PW in microseconds.</summary>
    public int GetChannelPWMax(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelPWMax(ch);
    }

    /// <summary>Gets per-finger IPI in milliseconds.</summary>
    public int GetChannelIPI(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelIPI(ch);
    }

    /// <summary>Checks whether the specified finger maps to a valid channel index.</summary>
    public bool IsFingerValid(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.IsChannelInRange(ch);
    }

    /// <summary>
    /// Applies model-driven stimulation using proportional or PD mode.
    /// </summary>
    /// <param name="finger">Finger label or alias.</param>
    /// <param name="magnitude">Normalized or physical magnitude input to the model.</param>
    public void StimWithMode(string finger, float magnitude)
    {
        int ch = FingerToChannel(finger);
        WSS.StimWithMode(ch, magnitude);
    }

    /// <summary>
    /// Updates calibration parameters for a specific finger.
    /// </summary>
    public void UpdateChannelParams(string finger, int max, int min, int amp)
    {
        int ch = FingerToChannel(finger);
        if (!WSS.IsChannelInRange(ch))
            throw new ArgumentOutOfRangeException(nameof(finger), $"Channel {ch} is not valid for current config.");

        string baseKey = $"stim.ch.{ch}";
        WSS.AddOrUpdateStimParam($"{baseKey}.maxPW", max);
        WSS.AddOrUpdateStimParam($"{baseKey}.minPW", min);
        WSS.AddOrUpdateStimParam($"{baseKey}.defaultPA", amp);
    }

    #endregion

    #region ==== Config and state ====

    /// <summary>Returns <c>true</c> if the model mode currently loaded is valid.</summary>
    public bool isModeValid() => WSS.IsModeValid();

    /// <summary>Returns <c>true</c> if the device is initialized and ready.</summary>
    public bool Ready() => _initialized && _wss != null && _wss.Ready();

    /// <summary>Returns <c>true</c> if stimulation is currently active.</summary>
    public bool Started() => _initialized && _wss != null && _wss.Started();

    /// <summary>Provides access to the model configuration controller.</summary>
    public ModelConfigController GetModelConfigCTRL() => WSS.GetModelConfigController();

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

    /// <summary>
    /// Maps a finger label or alias to its numeric channel.
    /// Supports "thumb", "index", "middle", "ring", "pinky" or "little",
    /// and generic "chN" notation. Returns 0 if invalid.
    /// </summary>
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

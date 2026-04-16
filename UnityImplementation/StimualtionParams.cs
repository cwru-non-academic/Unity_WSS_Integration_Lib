using UnityEngine;
using System.Collections.Generic;
using System;
using Wss.CoreModule;
using Wss.CalibrationModule;

/// <summary>
/// Provides a Unity-facing API for WSS stimulation using the core + params layer.
/// </summary>
/// <remarks>
/// This component composes <c>WssStimulationCore</c> -> <c>StimParamsLayer</c> and exposes
/// convenience methods that accept finger aliases (e.g., "index" or "ch2").
/// 
/// Lifecycle: the device is initialized in <see cref="OnEnable"/>, ticked in <see cref="Update"/>,
/// and shut down in <see cref="OnDisable"/>.
///
/// When <see cref="forcePort"/> is <c>false</c>, the wrapper auto-selects a serial port. When
/// <see cref="testMode"/> is <c>true</c>, it uses an in-memory test transport instead of hardware.
/// </remarks>
public class StimulationParams : MonoBehaviour
{
    #region ==== Serialized Fields ====

    /// <summary>
    /// Forces connection to a specific COM port instead of auto-detecting.
    /// </summary>
    [SerializeField] public bool forcePort = false;

    /// <summary>
    /// Enables simulated test mode without real hardware communication.
    /// </summary>
    [SerializeField] private bool testMode = true;

    /// <summary>
    /// Maximum number of setup retries before failing initialization.
    /// </summary>
    [SerializeField] private int maxSetupTries = 5;

    /// <summary>
    /// Target COM port to use when <c>forcePort</c> is enabled.
    /// </summary>
    [SerializeField] public string comPort = "COM7";

    #endregion

    private IStimParamsCore WSS;
    private IBasicStimulation basicWSS;
    /// <summary>
    /// Gets or sets a user-managed flag indicating whether stimulation is considered started.
    /// </summary>
    /// <remarks>
    /// This wrapper does not update this field; use <c>Started()</c> to query device state.
    /// </remarks>
    public bool started = false;
    /// <summary>True if the underlying core exposes basic-stimulation APIs.</summary>
    private bool basicSupported = false;

    #region ==== Unity Lifecycle ====

    /// <summary>
    /// Builds the transport and core WSS, then wraps it with <c>StimParamsLayer</c>.
    /// Tries to expose <see cref="IBasicStimulation"/> if available.
    /// </summary>
    /// <remarks>Uses <see cref="Application.streamingAssetsPath"/> as the configuration root.</remarks>
    public void Awake()
    {
        ITransport transport =
            testMode
            ? new TestModeTransport(new TestModeTransportOptions())
            : forcePort
                ? new SerialPortTransport(new SerialPortTransportOptions { PortName = comPort })
                : new SerialPortTransport(new SerialPortTransportOptions { AutoSelectPort = true });

        IStimulationCore WSScore = new WssStimulationCore(
            transport,
            new WssStimulationCoreOptions
            {
                ConfigPath = Application.streamingAssetsPath,
                MaxSetupTries = maxSetupTries,
            });

        WSS = new StimParamsLayer(WSScore, Application.streamingAssetsPath);
        WSS.TryGetBasic(out basicWSS);
        basicSupported = (basicWSS != null);
    }

    /// <summary>
    /// Initializes the WSS device connection when the component becomes active.
    /// </summary>
    void OnEnable() => WSS.Initialize();

    /// <summary>
    /// Performs periodic updates and tick cycles for communication and task execution.
    /// Press <c>A</c> to manually reload the core configuration file for testing.
    /// </summary>
    void Update()
    {
        WSS.Tick();
        if (Input.GetKeyDown(KeyCode.A))
            WSS.LoadConfigFile();
    }

    /// <summary>
    /// Ensures proper device shutdown when the component is disabled.
    /// </summary>
    void OnDisable() => WSS.Shutdown();

    #endregion

    #region ==== Connection Management ====

    /// <summary>
    /// Explicitly releases the radio connection.
    /// </summary>
    public void releaseRadio() => WSS.Shutdown();

    /// <summary>
    /// Performs a radio reset by shutting down and re-initializing the connection.
    /// </summary>
    public void resetRadio()
    {
        WSS.Shutdown();
        WSS.Initialize();
    }

    #endregion

    #region ==== Stimulation methods: basic and core ====

    /// <summary>
    /// Sends a direct analog stimulation command using raw parameters.
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
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void Save(int targetWSS)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.Save(IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.Save(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units. No-op and logs an error when basic stimulation is unavailable.</remarks>
    public void Save()
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.Save(WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.Load(WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void load(int targetWSS)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.Load(IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.Load(WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units. No-op and logs an error when basic stimulation is unavailable.</remarks>
    public void load()
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.Load(WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.Request_Configs(int,int,WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <param name="command">Configuration block selector.</param>
    /// <param name="id">Optional block id.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void request_Configs(int targetWSS, int command, int id)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.Request_Configs(command, id, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(int[],int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units. No-op and logs an error when basic stimulation is unavailable.</remarks>
    /// <param name="waveform">Serialized device waveform.</param>
    /// <param name="eventID">Target event slot.</param>
    public void updateWaveform(int[] waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, WssTarget.Broadcast);
    }

    /// <summary>
    /// Updates the waveform parameters for a specific event on a target unit.
    /// </summary>
    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(int[],int,WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void updateWaveform(int targetWSS, int[] waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, IntToWssTarget(targetWSS));
    }

    /// <summary>
    /// Selects a predefined or custom waveform shape from device memory.
    /// </summary>
    /// <inheritdoc cref="IBasicStimulation.UpdateEventShape(int,int,int,WssTarget)"/>
    /// <remarks>
    /// Slots 0-10 are predefined. Slots 11-13 are custom. No-op and logs an error when basic
    /// stimulation is unavailable from the wrapped core.
    /// </remarks>
    public void updateWaveform(int cathodicWaveform, int anodicWaveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateEventShape(cathodicWaveform, anodicWaveform, eventID, WssTarget.Broadcast);
    }

    /// <summary>
    /// Selects a predefined or custom waveform shape for a target unit.
    /// </summary>
    /// <inheritdoc cref="IBasicStimulation.UpdateEventShape(int,int,int,WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void updateWaveform(int targetWSS, int cathodicWaveform, int anodicWaveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateEventShape(cathodicWaveform, anodicWaveform, eventID, IntToWssTarget(targetWSS));
    }

    /// <summary>
    /// Updates waveform using JSON-loaded builder definition for all units.
    /// </summary>
    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(WaveformBuilder,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units. No-op and logs an error when basic stimulation is unavailable.</remarks>
    public void updateWaveform(WaveformBuilder waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, WssTarget.Broadcast);
    }

    /// <summary>
    /// Updates waveform using JSON-loaded builder definition for a target unit.
    /// </summary>
    /// <inheritdoc cref="IBasicStimulation.UpdateWaveform(WaveformBuilder,int,WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <param name="waveform">Waveform builder definition to serialize and send.</param>
    /// <param name="eventID">Target event slot.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void updateWaveform(int targetWSS, WaveformBuilder waveform, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateWaveform(waveform, eventID, IntToWssTarget(targetWSS));
    }

    /// <summary>Loads a waveform definition from external file.</summary>
    /// <inheritdoc cref="IBasicStimulation.LoadWaveform(string,int)"/>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void loadWaveform(string fileName, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.LoadWaveform(fileName, eventID);
    }

    /// <summary>Defines a custom waveform for the specified event slot on all units.</summary>
    /// <inheritdoc cref="IBasicStimulation.WaveformSetup(WaveformBuilder,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units. No-op and logs an error when basic stimulation is unavailable.</remarks>
    public void WaveformSetup(WaveformBuilder wave, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.WaveformSetup(wave, eventID, WssTarget.Broadcast);
    }

    /// <summary>Defines a custom waveform for the specified event slot on a target unit.</summary>
    /// <inheritdoc cref="IBasicStimulation.WaveformSetup(WaveformBuilder,int,WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <param name="wave">Waveform builder definition to store on the device.</param>
    /// <param name="eventID">Target event slot.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void WaveformSetup(int targetWSS, WaveformBuilder wave, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.WaveformSetup(wave, eventID, IntToWssTarget(targetWSS));
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateIPD(int,int,WssTarget)"/>
    /// <remarks>Broadcasts to all connected WSS units. No-op and logs an error when basic stimulation is unavailable.</remarks>
    public void UpdateIPD(int ipd, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateIPD(ipd, eventID, WssTarget.Broadcast);
    }

    /// <inheritdoc cref="IBasicStimulation.UpdateIPD(int,int,WssTarget)"/>
    /// <param name="targetWSS">0=broadcast, 1..3=unit index.</param>
    /// <param name="ipd">Inter-phase delay value forwarded to the basic API.</param>
    /// <param name="eventID">Target event slot.</param>
    /// <remarks>No-op and logs an error when basic stimulation is unavailable from the wrapped core.</remarks>
    public void UpdateIPD(int targetWSS, int ipd, int eventID)
    {
        if (!basicSupported) { Log.Error("Basic stimulation not supported on this Stimulator."); return; }
        basicWSS.UpdateIPD(ipd, eventID, IntToWssTarget(targetWSS));
    }

    #endregion

    #region ==== Stimulation methods: params layer (finger APIs) ====

    /// <summary>
    /// Stimulates using a normalized drive value in the range [0, 1].
    /// </summary>
    /// <param name="finger">Finger label or alias (e.g., "index", "ring", "ch2").</param>
    /// <param name="value01">Normalized drive in [0,1]. Values are clamped.</param>
    /// <remarks>Finger aliases are translated to numeric channels before forwarding to the params layer.</remarks>
    public void StimulateNormalized(string finger, float value01)
    {
        int ch = FingerToChannel(finger);
        WSS.StimulateNormalized(ch, value01);
    }

    /// <summary>
    /// Gets the last computed stimulation intensity for a finger.
    /// </summary>
    /// <remarks>For PW-driven systems this value is pulse width in microseconds.</remarks>
    /// <param name="finger">Finger label or alias.</param>
    /// <returns>The last intensity value produced for the resolved channel.</returns>
    public int GetLastPulseWidth(string finger)
    {
        int ch = FingerToChannel(finger);
        return (int)WSS.GetStimIntensity(ch);
    }

    /// <summary>Sets per-finger amplitude in mA.</summary>
    /// <inheritdoc cref="IStimParamsCore.SetChannelAmp(int,float)"/>
    public void SetChannelAmp(string finger, float mA)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelAmp(ch, mA);
    }

    /// <summary>Sets per-finger minimum pulse width in microseconds.</summary>
    /// <inheritdoc cref="IStimParamsCore.SetChannelPWMin(int,int)"/>
    public void SetChannelPWMin(string finger, int us)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelPWMin(ch, us);
    }

    /// <summary>Sets per-finger maximum pulse width in microseconds.</summary>
    /// <inheritdoc cref="IStimParamsCore.SetChannelPWMax(int,int)"/>
    public void SetChannelPWMax(string finger, int us)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelPWMax(ch, us);
    }

    /// <summary>Sets per-finger IPI in ms.</summary>
    /// <inheritdoc cref="IStimParamsCore.SetChannelIPI(int,int)"/>
    public void SetChannelIPI(string finger, int ms)
    {
        int ch = FingerToChannel(finger);
        WSS.SetChannelIPI(ch, ms);
    }

    /// <summary>Gets per-finger amplitude in mA.</summary>
    /// <inheritdoc cref="IStimParamsCore.GetChannelAmp(int)"/>
    public float GetChannelAmp(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelAmp(ch);
    }

    /// <summary>Gets per-finger minimum pulse width in microseconds.</summary>
    /// <inheritdoc cref="IStimParamsCore.GetChannelPWMin(int)"/>
    public int GetChannelPWMin(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelPWMin(ch);
    }

    /// <summary>Gets per-finger maximum pulse width in microseconds.</summary>
    /// <inheritdoc cref="IStimParamsCore.GetChannelPWMax(int)"/>
    public int GetChannelPWMax(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelPWMax(ch);
    }

    /// <summary>Gets per-finger IPI in ms.</summary>
    /// <inheritdoc cref="IStimParamsCore.GetChannelIPI(int)"/>
    public int GetChannelIPI(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.GetChannelIPI(ch);
    }

    /// <summary>Returns true if the finger maps to a valid channel for the current configuration.</summary>
    /// <param name="finger">Finger label or alias.</param>
    /// <returns><c>true</c> when the resolved channel is within the current configuration range.</returns>
    public bool IsFingerValid(string finger)
    {
        int ch = FingerToChannel(finger);
        return WSS.IsChannelInRange(ch);
    }

    #endregion

    #region ==== Params JSON and calibration ====

    /// <summary>Saves current params JSON to disk.</summary>
    /// <inheritdoc cref="IStimParamsCore.SaveParamsJson()"/>
    public void SaveParamsJson() => WSS.SaveParamsJson();

    /// <summary>Loads params JSON from default location.</summary>
    /// <inheritdoc cref="IStimParamsCore.LoadParamsJson()"/>
    public void LoadParamsJson() => WSS.LoadParamsJson();

    /// <summary>Loads params JSON from a given file or directory.</summary>
    /// <param name="pathOrDir">File path or directory with default name.</param>
    /// <inheritdoc cref="IStimParamsCore.LoadParamsJson(string)"/>
    public void LoadParamsJson(string pathOrDir) => WSS.LoadParamsJson(pathOrDir);

    /// <summary>
    /// Sets a parameter by dotted key. Examples: "stim.ch.0.amp", "stim.ch.1.minPW".
    /// </summary>
    /// <inheritdoc cref="IStimParamsCore.AddOrUpdateStimParam(string,float)"/>
    public void AddOrUpdateStimParam(string key, float value) => WSS.AddOrUpdateStimParam(key, value);

    /// <summary>Gets a parameter by dotted key.</summary>
    /// <inheritdoc cref="IStimParamsCore.GetStimParam(string)"/>
    public float GetStimParam(string key) => WSS.GetStimParam(key);

    /// <summary>Tries to read a parameter by dotted key.</summary>
    /// <inheritdoc cref="IStimParamsCore.TryGetStimParam(string, out float)"/>
    public bool TryGetStimParam(string key, out float v) => WSS.TryGetStimParam(key, out v);

    /// <summary>Returns a copy of all current params as dotted-key map.</summary>
    /// <inheritdoc cref="IStimParamsCore.GetAllStimParams()"/>
    public Dictionary<string, float> GetAllStimParams() => WSS.GetAllStimParams();

    /// <summary>
    /// Updates per-finger calibration params.
    /// </summary>
    /// <param name="finger">e.g., "index", "ring", or "ch2".</param>
    /// <param name="max">Maximum pulse width in microseconds.</param>
    /// <param name="min">Minimum pulse width in microseconds.</param>
    /// <param name="amp">Amplitude (mA).</param>
    /// <exception cref="ArgumentOutOfRangeException">If finger maps to an invalid channel.</exception>
    /// <remarks>Updates the backing dotted-key parameter entries used by the params layer.</remarks>
    public void UpdateChannelParams(string finger, int max, int min, int amp)
    {
        int ch = FingerToChannel(finger);
        if (!WSS.IsChannelInRange(ch))
            throw new ArgumentOutOfRangeException(nameof(finger), $"Channel {ch} is not valid for current config.");

        string baseKey = $"stim.ch.{ch}";
        WSS.AddOrUpdateStimParam($"{baseKey}.maxPW", max);
        WSS.AddOrUpdateStimParam($"{baseKey}.minPW", min);
        WSS.AddOrUpdateStimParam($"{baseKey}.amp", amp);
    }

    #endregion

    #region ==== Getters ====

    /// <inheritdoc cref="IStimulationCore.Ready()"/>
    public bool Ready() => WSS.Ready();

    /// <inheritdoc cref="IStimulationCore.Started()"/>
    public bool Started() => WSS.Started();

    /// <summary>Provides access to the core configuration controller.</summary>
    /// <returns>The current core configuration controller owned by the wrapper.</returns>
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
    /// Maps a finger label or alias to a device channel.
    /// Supports "thumb/index/middle/ring/pinky" and "chN" aliases.
    /// Returns 0 on invalid or empty input.
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

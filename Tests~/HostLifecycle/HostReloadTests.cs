using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using NUnit.Framework;
using UnityEngine;
using Wss.CoreModule;
using Wss.ModelModule;
using Wss.Testing;
using Wss.Transports;

[TestFixture, NonParallelizable]
public sealed class HostReloadTests
{
    private string directory;
    private MonoBehaviour host;
    private readonly List<ControlledTransport> transports = new List<ControlledTransport>();
    private SynchronizationContext previousContext;
    private bool ble;
    private Action<int, ControlledTransport> creating;

    [SetUp]
    public void SetUp()
    {
        directory = Path.Combine(Path.GetTempPath(), "unity-host-reload-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        Application.streamingAssetsPath = directory;
        previousContext = SynchronizationContext.Current;
        SynchronizationContext.SetSynchronizationContext(new SynchronizationContext());
        WriteCore(1); WriteParameters(); WriteModel(1);
        transports.Clear(); creating = null; Input.NextA = false; ble = false;
        WssTransportSupport.TestFactory = (type, auto, name) =>
        {
            var transport = new ControlledTransport();
            transports.Add(transport);
            creating?.Invoke(transports.Count, transport);
            return ble ? (ITransport)new WssBleTransport(transport) : transport;
        };
    }

    [TearDown]
    public void TearDown()
    {
        foreach (var transport in transports) transport.ReleaseDispose.Set();
        if (host != null) Invoke("OnDestroy");
        var cleanup = host == null ? null : Get<WssBleCleanup>("_bleCleanup");
        if (cleanup != null) { try { cleanup.Pending.GetAwaiter().GetResult(); } catch { } }
        host = null; WssTransportSupport.TestFactory = null;
        SynchronizationContext.SetSynchronizationContext(previousContext);
        Directory.Delete(directory, true);
    }

    [TestCase(typeof(Stimulation), false)]
    [TestCase(typeof(Stimulation), true)]
    [TestCase(typeof(StimulationParams), false)]
    [TestCase(typeof(StimulationParams), true)]
    [TestCase(typeof(Stimulationbasic), false)]
    [TestCase(typeof(Stimulationbasic), true)]
    public void AKeyStagesEditedCoreAndUsesTheHostResetPath(Type type, bool useBle)
    {
        Start(type, useBle);
        var old = Owner;
        if (useBle) transports[0].HoldDispose = true;
        WriteCore(2);
        Input.NextA = true;
        Invoke("Update");
        if (useBle)
        {
            Assert.That(transports[0].DisposeEntered.Wait(3000), Is.True);
            Assert.That(transports.Count, Is.EqualTo(1), "Replacement must wait for cleanup.");
            foreach (string file in new[] { "stimConfig.json", "stimParams.json", "modelConfig.json" })
                File.WriteAllText(Path.Combine(directory, file), "changed after staging");
            transports[0].ReleaseDispose.Set();
        }
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.Multiple(() =>
        {
            Assert.That(Owner, Is.Not.SameAs(old));
            Assert.That(Owner.GetCoreConfigController().MaxWss, Is.EqualTo(2));
            Assert.That(transports.Count, Is.EqualTo(2));
            Assert.That(State.Active.DefaultCorePath, Is.EqualTo(Path.Combine(directory, "stimConfig.json")));
        });
        Assert.Throws<ObjectDisposedException>(() => old.StimulateAnalog(1, 100, 4, 10), "A retired stack must not accept stimulation.");
    }

    [Test]
    public void ProfileFileAndDefaultPathsSurviveReconstructionAndWorkingDirectoryChanges()
    {
        Start(typeof(Stimulation), true);
        string profile = Path.Combine(directory, "profile with spaces"); Directory.CreateDirectory(profile);
        string core = Path.Combine(profile, "stimConfig.json");
        File.WriteAllText(core, "{\"maxWSS\":2,\"firmware\":\"J03\"}");
        File.Copy(Path.Combine(directory, "stimParams.json"), Path.Combine(profile, "stimParams.json"));
        File.Copy(Path.Combine(directory, "modelConfig.json"), Path.Combine(profile, "modelConfig.json"));
        Invoke("LoadParamsJson", profile);
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.That(State.Active.CorePath, Is.EqualTo(core));
        File.WriteAllText(core, "{\"maxWSS\":3,\"firmware\":\"J03\"}");
        Invoke("resetRadio");
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.That(Owner.GetCoreConfigController().MaxWss, Is.EqualTo(3));
        string custom = Path.Combine(profile, "specific parameters.json");
        File.Copy(Path.Combine(directory, "stimParams.json"), custom);
        Invoke("LoadParamsJson", custom);
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.That(Owner.GetCoreConfigController().MaxWss, Is.EqualTo(1), "A file override must use default Core, not its siblings.");
        Assert.That(State.Active.ParamsPath, Is.EqualTo(custom));
        Assert.That(State.Active.ModelPath, Is.EqualTo(Path.Combine(directory, "modelConfig.json")));
        Assert.That(((Wss.CalibrationModule.IStimParamsCore)Owner).IsChannelInRange(4), Is.False);
        string previous = Environment.CurrentDirectory;
        try
        {
            Environment.CurrentDirectory = profile;
            Invoke("LoadParamsJson");
            Assert.That(State.Active.ParamsPath, Is.EqualTo(Path.Combine(directory, "stimParams.json")));
            Assert.That(State.Active.DefaultCorePath, Is.EqualTo(Path.Combine(directory, "stimConfig.json")));
        }
        finally { Environment.CurrentDirectory = previous; }
    }

    [TestCase(typeof(Stimulation))]
    [TestCase(typeof(StimulationParams))]
    public void BulkUpdaterChangesCalibratedOutputAndSurvivesReload(Type type)
    {
        Start(type, false);
        Invoke("UpdateChannelParams", "ch2", 200, 100, 4);
        var parameters = (Wss.CalibrationModule.IStimParamsCore)Owner;
        for (int pass = 0; pass < 2; pass++)
        {
            long baseline = transports[0].Emulator.Conformance.MessageHistory.Last().SequenceNumber;
            parameters.StimulateNormalized(2, .5f);
            PumpUntil(() => transports[0].Emulator.Conformance.StimulationHistory.Any(item => item.SequenceNumber > baseline && item.Channel == 2 && item.PulseWidth == 150 && item.PulseAmplitude == 4));
            Assert.That(transports[0].Emulator.Conformance.StimulationHistory.Last(item => item.Channel == 1).PulseWidth, Is.Zero);
            if (pass == 0) Invoke("LoadParamsJson");
        }
    }

    [Test]
    public void DisableEnableDuringPendingCleanupCancelsTheObsoletePlan()
    {
        Start(typeof(Stimulation), true);
        transports[0].HoldDispose = true;
        WriteCore(2); Invoke("resetRadio");
        host.isActiveAndEnabled = false; Invoke("OnDisable");
        WriteCore(3);
        host.isActiveAndEnabled = true; Invoke("OnEnable");
        Assert.That(transports.Count, Is.EqualTo(1));
        transports[0].ReleaseDispose.Set();
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.That(Owner.GetCoreConfigController().MaxWss, Is.EqualTo(3));
        Assert.That(transports.Count, Is.EqualTo(2));
    }

    [Test]
    public void NewerRequestSupersedesPendingCleanupAndExplicitShutdownCancelsIt()
    {
        Start(typeof(Stimulation), true);
        transports[0].HoldDispose = true;
        WriteCore(2); Invoke("resetRadio");
        WriteCore(3); Invoke("resetRadio");
        transports[0].ReleaseDispose.Set();
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.That(Owner.GetCoreConfigController().MaxWss, Is.EqualTo(3));
        transports[1].HoldDispose = true;
        WriteCore(1); Invoke("resetRadio"); Invoke("releaseRadio");
        transports[1].ReleaseDispose.Set();
        PumpUntil(() => Get<WssBleCleanup>("_bleCleanup").Pending.IsCompleted);
        for (int i = 0; i < 10; i++) Invoke("Update");
        Assert.That(Owner, Is.Null);
        Assert.That(transports.Count, Is.EqualTo(2));
    }

    [TestCase(false)]
    [TestCase(true)]
    public void DisableDuringConstructionPreventsStalePublication(bool duringConnect)
    {
        Start(typeof(Stimulation), false);
        var active = State.Active;
        creating = (count, transport) =>
        {
            if (count != 2) return;
            Action disable = () => { host.isActiveAndEnabled = false; Invoke("OnDisable"); };
            if (duringConnect) transport.Connecting = disable; else disable();
        };
        WriteCore(2); Invoke("resetRadio");
        Assert.That(Owner, Is.Null);
        Assert.That(State.Active, Is.SameAs(active));
        Assert.That(transports[1].Disposed, Is.True);
    }

    [TestCase(false)]
    [TestCase(true)]
    public void CleanupFaultBlocksConstructionAndRetryUsesTheValidatedSnapshot(bool useBle)
    {
        Start(typeof(Stimulation), useBle);
        transports[0].ThrowOnDisposeOnce = true;
        var active = State.Active;
        WriteCore(2); Invoke("resetRadio");
        PumpUntil(() => useBle ? Get<WssBleCleanup>("_bleCleanup").Pending.IsCompleted : State.CleanupError != null);
        Invoke("Update");
        if (useBle) Assert.That(Get<WssBleCleanup>("_bleCleanup").Pending.IsFaulted, Is.True);
        else Assert.That(State.CleanupError, Is.Not.Null);
        Assert.That(State.Error, Is.Not.Null);
        Assert.That(State.Active, Is.SameAs(active));
        Assert.That(transports.Count, Is.EqualTo(1));
        File.WriteAllText(Path.Combine(directory, "stimConfig.json"), "invalid after staging");
        Invoke("RetryReload");
        PumpUntil(() => Owner != null && Owner.Started());
        Assert.That(Owner.GetCoreConfigController().MaxWss, Is.EqualTo(2));
        Assert.That(State.Error, Is.Null);
        Assert.That(transports[0].Disposed, Is.True, "Retry must not merely suppress a failed adapter disposal.");
    }

    [Test]
    public void ExplicitInactiveConformanceInitializationIsPreservedAndDisableCancelsIt()
    {
        WssTransportSupport.TestFactory = null;
        host = new Stimulation { isActiveAndEnabled = false };
        Invoke("ConfigureConformance", directory);
        Invoke("resetRadio");
        var timer = System.Diagnostics.Stopwatch.StartNew();
        while (!Owner.Started() && timer.ElapsedMilliseconds < 3000) { Invoke("TickConformance"); Thread.Sleep(1); }
        Assert.That(Owner.Started(), Is.True);
        Invoke("OnDisable");
        Invoke("resetRadio");
        Assert.That(Get<bool>("_initialized"), Is.False);
    }

    [Test]
    public void NoRestartReloadPublishesConfiguredModelAndCalibrationOutput()
    {
        Start(typeof(Stimulation), false);
        var original = Owner;
        WriteParameters(100, 200, 4, 13); WriteModel(.5);
        Invoke("LoadParamsJson");
        Assert.That(Owner, Is.SameAs(original));
        Assert.That(transports.Count, Is.EqualTo(1));
        var model = (IModelParamsCore)Owner;
        long baseline = transports[0].Emulator.Conformance.MessageHistory.Last().SequenceNumber;
        model.StimWithMode(2, .5f);
        PumpUntil(() => transports[0].Emulator.Conformance.StimulationHistory.Any(item => item.SequenceNumber > baseline && item.Channel == 2 && item.PulseWidth == 125 && item.PulseAmplitude == 4 && item.InterPulseInterval == 13));
    }

    [Test]
    public void InvalidCoreFileDoesNotShutDownTheWorkingHost()
    {
        Start(typeof(Stimulation), true);
        var original = Owner; var active = State.Active;
        File.WriteAllText(Path.Combine(directory, "stimConfig.json"), "invalid");
        Assert.Throws<InvalidDataException>(() => Invoke("resetRadio"));
        Assert.That(Owner, Is.SameAs(original));
        Assert.That(State.Active, Is.SameAs(active));
        Assert.That(transports.Count, Is.EqualTo(1));
        Assert.That(transports[0].Disposed, Is.False);
    }

    private void Start(Type type, bool useBle)
    {
        ble = useBle;
        host = (MonoBehaviour)Activator.CreateInstance(type);
        Set("transportSerializationVersion", 1);
        Set("transportType", useBle ? WssTransportType.BLE : WssTransportType.Serial);
        Invoke("OnEnable");
        PumpUntil(() => Owner != null && Owner.Started());
    }
    private IStimulationCore Owner => host == null ? null : Get<IStimulationCore>("_stackOwner");
    private WssReloadState State => Get<WssReloadState>("_reload");
    private T Get<T>(string name) => (T)host.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).GetValue(host);
    private void Set(string name, object value) => host.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).SetValue(host, value);
    private void Invoke(string name, params object[] arguments)
    {
        try { host.GetType().GetMethod(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, arguments.Select(value => value.GetType()).ToArray(), null).Invoke(host, arguments); }
        catch (TargetInvocationException ex) { System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(ex.InnerException).Throw(); }
    }
    private void PumpUntil(Func<bool> condition)
    {
        var timer = System.Diagnostics.Stopwatch.StartNew();
        while (timer.ElapsedMilliseconds < 3000) { Invoke("Update"); if (condition()) return; Thread.Sleep(1); }
        Assert.Fail("Host lifecycle did not reach the expected state. " + State.Error);
    }
    private void WriteCore(int count) => File.WriteAllText(Path.Combine(directory, "stimConfig.json"), "{\"maxWSS\":" + count + ",\"firmware\":\"J03\",\"useConfigAmpCurves\":true,\"ampCurves\":[{\"LowThreshold\":0,\"LowConst\":1,\"ExpPower\":1,\"LinearOffset\":-1,\"LinearSlope\":1}]}");
    private void WriteParameters(int min = 50, int max = 150, int amp = 2, int ipi = 10)
    {
        string channels = string.Join(",", Enumerable.Range(1, 9).Select(ch => "\"" + ch + "\":{\"ampMode\":\"PW\",\"minPW\":" + min + ",\"maxPW\":" + max + ",\"defaultPA\":" + amp + ",\"IPI\":" + ipi + "}"));
        File.WriteAllText(Path.Combine(directory, "stimParams.json"), "{\"stim\":{\"ch\":{" + channels + "}}}");
    }
    private void WriteModel(double gain) => File.WriteAllText(Path.Combine(directory, "modelConfig.json"), "{\"calib\":{\"mode\":\"P\"},\"constants\":{\"PModeProportional\":" + gain.ToString(System.Globalization.CultureInfo.InvariantCulture) + "}}");

    private sealed class ControlledTransport : ITransport
    {
        internal readonly EmulatedWssTransport Emulator = new EmulatedWssTransport();
        internal readonly ManualResetEventSlim DisposeEntered = new ManualResetEventSlim();
        internal readonly ManualResetEventSlim ReleaseDispose = new ManualResetEventSlim();
        internal bool HoldDispose, Disposed, ThrowOnDisposeOnce;
        internal Action Connecting;
        public bool IsConnected => Emulator.IsConnected;
        public event Action<byte[]> BytesReceived { add => Emulator.BytesReceived += value; remove => Emulator.BytesReceived -= value; }
        public Task ConnectAsync(CancellationToken ct = default) { Connecting?.Invoke(); return Emulator.ConnectAsync(ct); }
        public Task DisconnectAsync(CancellationToken ct = default) => Emulator.DisconnectAsync(ct);
        public Task SendAsync(byte[] data, CancellationToken ct = default) => Emulator.SendAsync(data, ct);
        public void Dispose()
        {
            DisposeEntered.Set();
            if (HoldDispose && !ReleaseDispose.Wait(5000)) throw new TimeoutException("Controlled cleanup was not released.");
            if (ThrowOnDisposeOnce) { ThrowOnDisposeOnce = false; throw new IOException("Controlled emulator transport disposal failure."); }
            Emulator.Dispose(); Disposed = true;
        }
    }

}

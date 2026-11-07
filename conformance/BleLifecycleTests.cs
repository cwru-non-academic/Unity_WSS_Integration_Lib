using NUnit.Framework;
using Wss.Transports;

// Fake transport boundary only: no native backend, adapter, peripheral or Unity engine.
[TestFixture]
public sealed class BleLifecycleTests
{
    [Test]
    public async Task ConnectionIsSingleFlightAndCancellationPermanentlyFencesActivation()
    {
        var inner = new FakeTransport();
        using var transport = new WssBleTransport(inner);
        Task first = transport.ConnectAsync();
        Assert.That(transport.ConnectAsync(), Is.SameAs(first));
        await inner.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        transport.CancelConnection();
        Assert.That(async () => await first, Throws.InstanceOf<OperationCanceledException>());
        Assert.ThrowsAsync<TaskCanceledException>(async () => await transport.ConnectAsync());
        await transport.DisconnectAsync();
        Assert.That(inner.Disconnections, Is.EqualTo(1));
    }

    [Test]
    public async Task BytesAndCustomTargetPassThroughWithoutReencoding()
    {
        var inner = new FakeTransport();
        using var transport = new WssBleTransport(inner);
        byte[] bytes = { 0x80, 0x7e, 0x7d, 0x00, 0xff };
        byte[] received = null!;
        transport.BytesReceived += data => received = data;
        await transport.SendAsync(bytes);
        inner.Emit(bytes);
        Assert.Multiple(() =>
        {
            Assert.That(inner.Sent, Is.EqualTo(bytes));
            Assert.That(received, Is.EqualTo(bytes));
        });
    }

    [Test]
    public void DisposeIsIdempotentAndRejectsConnectionReuse()
    {
        var inner = new FakeTransport();
        var transport = new WssBleTransport(inner);
        transport.Dispose();
        transport.Dispose();
        Assert.Multiple(() =>
        {
            Assert.That(inner.Disposals, Is.EqualTo(1));
            Assert.That(() => transport.ConnectAsync(), Throws.TypeOf<ObjectDisposedException>());
        });
    }

    private sealed class FakeTransport : ITransport
    {
        internal readonly TaskCompletionSource<bool> Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal byte[] Sent = Array.Empty<byte>();
        internal int Disconnections, Disposals;
        public bool IsConnected => false;
        public event Action<byte[]>? BytesReceived;
        public async Task ConnectAsync(CancellationToken token = default)
        {
            Entered.TrySetResult(true);
            await Task.Delay(Timeout.Infinite, token);
        }
        public Task DisconnectAsync(CancellationToken token = default) { Disconnections++; return Task.CompletedTask; }
        public Task SendAsync(byte[] data, CancellationToken token = default) { Sent = data.ToArray(); return Task.CompletedTask; }
        internal void Emit(byte[] bytes) => BytesReceived?.Invoke(bytes);
        public void Dispose() => Disposals++;
    }
}

namespace UnityEngine
{
    internal static class Debug
    {
        public static void Log(object value) => throw new InvalidOperationException("Unity engine logging is unavailable in this fake-transport suite.");
        public static void LogWarning(object value) => Log(value);
        public static void LogError(object value) => Log(value);
    }
}

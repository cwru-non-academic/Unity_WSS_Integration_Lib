#nullable disable
using System;
using System.Threading;
using System.Threading.Tasks;
using Wss.Testing;
#if GUI_CONFORMANCE
using Endpoint = WssConformanceController;
#else
using Endpoint = Stimulation;
#endif

// Only hosting/scheduling differs from Unity: all commands below reach the same
// production partial methods. The canonical fixture and assertions are unchanged.
internal sealed class DotNetConformanceAdapter : IDisposable
{
    private readonly Endpoint _controller;
    private readonly object _gate = new object();
    private readonly CancellationTokenSource _stop = new CancellationTokenSource();
    private Task _ticks = Task.CompletedTask;
    private Exception _tickFailure;

    internal DotNetConformanceAdapter(string directory) => _controller = new Endpoint(directory);

    public void Initialize()
    {
        lock (_gate) _controller.Initialize();
        _ticks = Task.Run(async () =>
        {
            try
            {
                while (!_stop.IsCancellationRequested)
                {
                    lock (_gate) _controller.Tick();
                    await Task.Delay(1, _stop.Token).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
            catch (Exception ex) { lock (_gate) _tickFailure = ex; }
        });
    }

    private void CheckTick()
    {
        if (_tickFailure != null) throw new InvalidOperationException("Shared wrapper tick failed.", _tickFailure);
    }

    public bool Ready() { lock (_gate) { CheckTick(); return _controller.Ready(); } }
    public bool Started() { lock (_gate) { CheckTick(); return _controller.Started(); } }
    public bool TryGetConformance(out IWssConformance conformance)
    { lock (_gate) { CheckTick(); return _controller.TryGetConformance(out conformance); } }
    public void StimulateAnalog(string channel, int pw, int amplitude, int ipi)
    { lock (_gate) { CheckTick(); _controller.StimulateAnalog(channel, pw, amplitude, ipi); } }
    public void StimulateNormalized(string channel, float input)
    { lock (_gate) { CheckTick(); _controller.StimulateNormalized(channel, input); } }
    public void UpdateEventRatio(int target, int ratio, int eventId)
    { lock (_gate) { CheckTick(); _controller.UpdateEventRatio(target, ratio, eventId); } }
    public void StopStimulation(int target)
    { lock (_gate) { CheckTick(); _controller.StopStimulation(target); } }

    public void Dispose()
    {
        _stop.Cancel();
        _ticks.GetAwaiter().GetResult();
        lock (_gate) _controller.Dispose();
        _stop.Dispose();
    }
}

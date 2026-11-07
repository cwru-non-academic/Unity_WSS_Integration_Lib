using System;
using Wss.CoreModule;
using Wss.Transports;

// Shared transaction state; transport ownership stays in each component's
// existing ShutdownStack/InitializeStack path. All calls run on Unity's main thread.
internal sealed class WssReloadState
{
    internal WssConfigurationSnapshot Active { get; private set; }
    internal WssConfigurationSnapshot Pending { get; private set; }
    internal long Generation { get; private set; }
    internal bool Enabled { get; private set; }
    internal Exception Error { get; private set; }
    internal Exception CleanupError { get; private set; }
    private IStimulationCore failedOwner;
    private ITransport failedTransport;
    internal void DisposeDetached(IStimulationCore owner, ITransport transport)
    {
        if (owner == null && transport == null) return;
        try
        {
            if (owner != null) owner.Dispose(); else transport?.Dispose();
            CleanupError = null; failedOwner = null; failedTransport = null;
        }
        catch (Exception ex)
        {
            failedOwner = owner; failedTransport = transport;
            CleanupError = ex; Error = ex;
            try { transport?.Dispose(); }
            catch (Exception fallback) { CleanupError = new AggregateException(ex, fallback); }
            throw new InvalidOperationException("WSS cleanup failed; an explicit retry is required.", CleanupError);
        }
    }
    internal void RetryCleanup()
    {
        if (CleanupError != null) DisposeDetached(failedOwner, failedTransport);
    }
    internal void Enable() { Enabled = true; }
    internal void Disable() { Enabled = false; Cancel(); }
    internal void Cancel() { Generation++; Pending = null; }
    internal long Request(WssConfigurationSnapshot snapshot)
    {
        Pending = snapshot ?? throw new ArgumentNullException(nameof(snapshot));
        Error = null;
        return ++Generation;
    }
    internal bool IsCurrent(long generation) => Enabled && generation == Generation && Pending != null;
    internal bool Publish(long generation)
    {
        if (!IsCurrent(generation)) return false;
        Active = Pending; Pending = null; Error = null;
        return true;
    }
    internal void Fail(long generation, Exception error) { if (generation == Generation) Error = error; }
    internal WssConfigurationSnapshot Current(IStimulationCore stack, string directory)
    {
        var snapshot = Active ?? WssConfigurationSnapshot.ReadDefaults(directory);
        return stack == null ? snapshot : snapshot.CaptureCurrent(stack);
    }
}

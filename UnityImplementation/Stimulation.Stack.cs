using Wss.CoreModule;
using Wss.CalibrationModule;
using Wss.ModelModule;
using Wss.Transports;

// Both hosts use this production stack composition. The caller retains the latest
// owner so a failed layer constructor is cleaned up by the same ownership rules.
internal static class WssStimulationStack
{
    internal static IModelParamsCore Build(ITransport transport, string directory,
        int maxSetupTries, ref IStimulationCore owner)
    {
        owner = new WssStimulationCore(transport, new WssStimulationCoreOptions
        {
            ConfigPath = directory,
            MaxSetupTries = maxSetupTries
        });
        owner = new StimParamsLayer(owner, directory);
        owner = new ModelParamsLayer((IStimParamsCore)owner, directory);
        return (IModelParamsCore)owner;
    }
}

# Unity repository conformance automation

Automated acceptance runs in **ordinary .NET 9**, without starting or activating
Unity. It tests the real production command source shared with the Unity wrapper.
The retained manual EditMode harness provides separate Unity Editor evidence.
Neither path exercises UI input/rendering, scenes, player packaging or hardware.

## Production path and unchanged cases

`UnityImplementation/Stimulation.Commands.cs` is the original production command
and mapping body, moved without rewriting it. Unity `Stimulation.cs` and the
emulator-only `Conformance~/Stimulation.DotNet.cs` are alternate partial hosts.
Both call `Stimulation.Stack.cs` to compose the same `WssStimulationCore` ->
`StimParamsLayer` -> `ModelParamsLayer` stack. The .NET host cannot select a physical
transport. There are no UnityEngine stubs.

Wrapper CI calls the shared `Stimulation` methods. GUI CI additionally compiles the
actual application's `WssConformanceController.cs` forwarding methods, with its
.NET lifetime host. That diagnostic entry point is also used by the manual Editor
harness; production UI managers call `Stimulation` directly and are not exercised.

`Conformance~/Prepare-Harness.ps1` reads the pinned canonical C# fixture from
`CSharp_WSS_Integration_Lib` commit `7145e2307f997f703748530bf74311ef94455e98`,
SHA256 `1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44`.
Only its controller factory and type alias change. Its ten cases, exact shared
values, finite waits, evaluator calls, Assert.Multiple blocks and eighteen
Assert.That expressions remain unchanged. Eighteen counts source expressions;
NUnit's runtime assertion count includes repeated setup/parameterized evaluations.
No independent scenario or expected-value suite is maintained here.

The generated project uses SDK9.0.316, net9.0, NUnit3.14.0 and the verified released
Core/JSON dependencies. It compiles the shared wrapper source, not the C# CLI
controller. Generated source, bin, obj, fixture JSON and results stay outside Assets
and source checkouts; Unity ignores the wrapper's `Conformance~` tooling folder.

## Checks and evidence

- `unity-compatibility.yml`: **WSS integration compatibility**, stable acceptance
  **Integration behavioral tests**.
- Wrapper `wss-preflight.yml`: **WSS downloaded-artifact preflight**, stable
  acceptance **Preflight behavioral tests**.
- GUI `unity-ci.yml`: **GUI CI**, stable acceptance **GUI general conformance**.
- GUI `wss-preflight.yml`: **WSS GUI preflight**, same GUI acceptance name.

Committed wrapper validation needs only its exact wrapper source and the pinned
canonical fixture. GUI validation derives the exact wrapper SHA from its mode160000
gitlink. These public read-only checkouts use the existing workflow token; normal
CI requires no GitHub App secret, Unity license or persistent local runner.

`Invoke-DotNetConformance.ps1` requires clean exact source SHAs, the pinned fixture
hash and the complete fifteen-DLL projection/hash/importer contract. It prepares a
fresh disposable host, runs bounded actual dotnet test, and validates real NUnit
XML: all ten exact case names discovered/executed/passed, zero skips/failures.
Diagnostics retain the test output and source-input manifest. Successful runs retain
`dotnet-conformance-evidence`; candidate runs retain `unity-preflight-evidence`
(the legacy artifact name denotes these repositories, not Editor execution).

Automated evidence is **wss-dotnet-evidence/v1** with `execution: dotnet`, exact SDK,
`unity_executed: false`, source/fixture/producer tuple, projection digest, eighteen
unchanged assertion expressions, XML/log hashes and ten real passes. Promotion
validators accept only that explicit runtime and exact successful acceptance job.
They never relabel a local Editor result as hosted .NET evidence or vice versa.

Candidate mode retains the exact producer run/artifact/archive/commit/hash resolver,
a fresh candidate-only DLL projection, both immutable source SHAs, dual preflights,
reviewed merge and normal-CI validation. No older/committed payload fallback is
allowed. The Unity-specific approval schema/marker remains separate from the C#
cascade. No-op and existing-PR/replay guards, dependency/gitlink diff allowlists,
no-force-push and manual merge behavior remain in place.

## Remaining promotion setup

Routine dependency promotion targets **dev** in both Unity repositories. Their
published baseline preserves wrapper history including ce6d9ef and the archived
amp_control tip; main merges remain the user's responsibility.

`baseline_ready` remains false: future candidate preflight/promotion and reviewed
merge dispatch require a separate approved baseline. The blank `gui_harness_sha`
is not used by normal .NET wrapper CI; candidate inputs already pin both sources.
Default branches still need user-reviewed workflow publication before future
workflow dispatch can be relied upon. Core-to-Unity automatic handoff is not enabled.

Repository-level Actions secret/variable name inventories were empty. Inherited
configuration is unverified. Future candidate promotion needs existing approved
`WSS_GITHUB_APP_ID` / `WSS_GITHUB_APP_PRIVATE_KEY` access and scoped permissions;
none were created, changed or assumed by this implementation.

## Manual Unity verification and coverage limits

`Invoke-UnityConformance.ps1` and the GUI's `tools/UnityConformance/Prepare-Harness.ps1`
retain the real Unity2022.3.62f3 / revision96770f904ca7 / UTF1.1.33 EditMode route.
Pass the locally licensed Editor explicitly with `-UnityExe`; its prerequisite
check now receives that exact path. Hosted Editor activation remains blocked.
The earlier real Editor run passed ten cases; it predates this source extraction,
so a fresh manual Editor import/run is still needed to validate these split files.
No Editor was launched for ordinary .NET CI implementation.

.NET acceptance proves shared API mapping, layer composition and emulator-observed
protocol/state behavior on .NET. It does not prove Unity importers/DLL resolution,
Mono runtime behavior, MonoBehaviour callbacks/serialization, scene references,
UI managers, player builds, BLE/Serial/native communication or device safety.
Shipping releases and ruleset/security changes are outside this work.

# WSS Unity Interface
C# class that has all the methods to communicate with the WSS and software specific classes that implements some of the functionalities necessary for that program.

All documentation about the API and other implementations can be found in [GitHub Pages](https://cwru-non-academic.github.io/WSS_Documentation/).

## Unity requirements

In Project Settings > Player > Other Settings > Configuration, select the .NET Framework API compatibility level. The manual validation harness pins Unity 2022.3.62f3; see the maintainer details below for its exact revision and coverage.

## Add this repository to an existing project
1. Close other software using the code solution (Unity, Visual Studio, etc)
2. If using git desktop, open the command prompt by going to `Repository>Open in Command Prompt`
3. Use command `git submodule add <submoduleURL> <pathInProject>`
    - if using a submodule inside of Unity make sure the path is inside the Assets folder
    - Ex HTTPS: `git submodule add https://github.com/cwru-non-academic/Unity_WSS_Integration_Lib.git Assets\SubModules\WSSInterfacingModule`
    - Ex SSH: `git submodule add git@github.com:cwru-non-academic/Unity_WSS_Integration_Lib.git Assets\SubModules\WSSInterfacingModule`
4. Click `Current repository>Add>Add existing repository..` and locate the folder where you installed the submodule `<pathInProject>`
5. Remove old scripts from the project that are now part of the submodule
6. Open solution dependent software and let it refactor.
7. (Unity Only) Make sure all your scripts in the scene are still available and linked correctly.
8. (Unity only) Add `"com.unity.nuget.newtonsoft-json": "3.2.1",` to your package manager manifest under dependencies found in `<project>/Packages/manifest.json`

## How to commit a git project that has submodules (Git Desktop)
1. This only applies if the changes were made to the submodule, otherwise just commit as normal.
2. Inside of the git Desktop a warning will appear that says there are submodule changes.
3. Changes to submodules must be committed first in the submodules repo.
4. If the submodule repo is already setup, just click open repository shortcut under the submodule changes warning.
5. If it is not setup, click the shortcut to add it to Git Desktop.
6. Once in the submodule repo, commit the changes as normal.
7. Return to the main repo and commit the changes there (The change in commit ID will be not be selected by default. select it and then commit).

## Commit submodule changes from the command line

Commit and push the changes inside the submodule first. Then commit and push its updated gitlink in the parent application repository. To initialize an existing application's submodules after cloning it, run `git submodule update --init --recursive` from the application checkout.

## How to pull a submodule change (Git Desktop)
1. Make sure the git submodule repo is already part of your repos in git desktop
2. If not add it by following [Add this repository to an existing project](#add-this-repository-to-an-existing-project)
3. Go to the submodule repo and pull changes as normal.
4. Pulling a submodule will add a change in commit ID to the main repo.
    - Multiple changes in commit ID can be committed to the main repo as a single commit and together with other changes to the main repo.

## Update the packaged DLLs

Use the reviewed candidate-promotion workflow described below. The payload in `Plugins/WSS_Core_Interface` is coupled to `.github/unity-candidate.json` and the Unity `.meta` importer settings. Copying an arbitrary release ZIP into this folder leaves the recorded hashes and projection inventory inconsistent. Review and merge the generated wrapper dependency PR before updating an application's wrapper gitlink.

## API and other Documentation
All documentation regarding hardware, API, and communication protocols can be found here [WSS Docs](https://cwru-non-academic.github.io/WSS_Documentation/).

## Desktop BLE and validation boundaries

This branch currently carries the 20-file payload, including the managed and native macOS BLE backend. The following platform and validation limits still apply.

The legacy 18-file main baseline has no macOS BLE backend. The macOS importer and backend requirements below apply only after adopting a declared macOS payload; they do not establish support for that legacy payload.

Select `BLE` with the existing transport controls; automatic discovery, `name:` and `id:` selectors retain their existing meaning. Windows uses the registered Windows backend. macOS Editor/standalone uses `MacBleBackend.Register()` with Mono. Both macOS plugin importers are restricted to OSX Editor and OSXUniversal standalone, use AnyCPU for the universal native binary, and exclude `ENABLE_IL2CPP`. Unity Linux BLE and macOS IL2CPP are explicitly unsupported; no new backend or AOT callback bridge is inferred from Core support.

macOS needs both `backends/macos/WSS.Transport.BLE.MacOS.dll` and `libwss_macos_ble.dylib`, macOS 11 or newer, and a compatible arm64/x86_64 host. Before shipping a Mac Player, the application maintainer must choose a supported deployment target and supply its Bluetooth Usage Description/authorization configuration. Existing application settings and stimulation configuration, including custom `0x80` targets, are not changed automatically. See [Unity macOS Player settings](https://docs.unity3d.com/2022.3/Documentation/Manual/PlayerSettings-macOS.html).

The separate `Invoke-BleLifecycleConformance.ps1` suite runs the same ten canonical C# scenarios and 18 unchanged assertion expressions through the production BLE lifetime adapter over the Core emulator, plus cancellation, unchanged byte forwarding and disposal regressions. It uses a fake transport, not a BLE backend or physical device. Native package/default-context/ABI checks remain separate. The GUI's disposable Unity harness additionally checks the real PluginImporter settings and offers load-only native diagnostics. Windows Editor proof does not establish macOS Editor/Player, IL2CPP, Bluetooth authorization or hardware proof. Run actual macOS Mono Editor and intended Player checks before claiming native Unity macOS compatibility.

Source synchronization may retain an exact legacy 18-file committed payload without adopting new Core bytes. The platform consumer reads the facade's declared capability: a declared macOS backend requires both matching managed/native files; an undeclared legacy backend must carry neither and is explicitly unsupported on macOS. Candidate projection stays on the strict 27-file universal / 20-file Unity path. link.xml preserves the reflected Mono bootstrap when the macOS assembly is present; it does not enable IL2CPP or manufacture backend support.

Dev release acceptance uses `release-receipt.yml` with the exact Core producer run
and frozen plan ID. It emits a read-only receipt after the human-reviewed bot
merge, paired preflights, candidate-byte/projection checks and fresh final-merge
CI. GUI acceptance additionally verifies the actual wrapper gitlink and its
post-merge preflight. Main supplies registered trusted tooling; stable releases
remain disabled. Coverage describes the .NET harness, not Unity Editor/Player,
IL2CPP or physical BLE validation.

## Maintainer validation and promotion

<details>
<summary>CI, promotion contracts, manual Unity validation and exact identifiers</summary>

### CI checks

Pull requests and pushes to `dev` and `main` expose the same separate contexts as the C# integration:

- `Integration behavioral tests`
- `Integration compatibility (Windows)`
- `Integration compatibility (Ubuntu)`
- `Integration compatibility (macOS)`

Behavioral validation runs the pinned C# canonical fixture through the shared production command/stack source: ten cases and eighteen unchanged assertion expressions. Each platform job additionally publishes a disposable .NET consumer, verifies every projected payload byte in build and publish output, and compiles the unmodified `WssTransportSupport` selector with that host's Unity platform symbol. Serial construction must load the exact OS-specific Ports runtime. Windows BLE checks backend loading and production native exports without scanning, connecting, or stimulating. macOS Mono selects the registered CoreBluetooth backend and verifies disconnected construction/disposal and native ABI loading. Ubuntu verifies the explicit unsupported Unity BLE exception; Linux BLE support in Core does not enable it in the Unity selector.

These checks run on .NET 9, **not the Unity engine**. A throwing shim supplies only the selector's unused Unity logging methods. They do not validate scenes, UI managers, Unity Editor/Player execution, Mono/IL2CPP compatibility, or hardware. The nested `runtimes/` payload is for .NET consumers and has disabled Unity importers; shipping it does not establish Unity Serial support. Licensed Unity EditMode validation remains a distinct explicit path.

Candidate preflight runs the same three platform checks against independently resolved exact producer artifacts. Promotion requires their successful completion in addition to the original canonical evidence, source, fixture, and projection gates. Platform evidence records the host and unsupported transport boundary separately from Unity execution.

### Unity repository conformance automation

Automated acceptance runs in **ordinary .NET 9**, without starting or activating
Unity. It tests the real production command source shared with the Unity wrapper.
The retained manual EditMode harness provides separate Unity Editor evidence.
Neither path exercises UI input/rendering, scenes, player packaging or hardware.

### Production path and unchanged cases

`UnityImplementation/Stimulation.Commands.cs` is the original production command
and mapping body, moved without rewriting it. Unity `Stimulation.cs` and the
emulator-only `Conformance~/Stimulation.DotNet.cs` are alternate partial hosts.
Both call `Stimulation.Stack.cs` to compose the same `WssStimulationCore` ->
`StimParamsLayer` -> `ModelParamsLayer` stack. The .NET host cannot select a physical
transport. The canonical host uses no UnityEngine stubs. The separate platform
load probe compiles the production transport selector with a throwing shim only
for its unused Unity logging calls; it never runs Unity lifecycle methods.

Wrapper CI calls the shared `Stimulation` methods. GUI CI additionally compiles the
actual application's `WssConformanceController.cs` forwarding methods, with its
.NET lifetime host. That diagnostic entry point is also used by the manual Editor
harness; production UI managers call `Stimulation` directly and are not exercised.

`Conformance~/Prepare-Harness.ps1` reads the pinned canonical C# fixture from
`CSharp_WSS_Integration_Lib` commit `7145e2307f997f703748530bf74311ef94455e98`,
Git-blob SHA256 `f6aeced83d35255532b6685d9c870307f856aad140da133695a77e9de6104ee2`.
Git controls checkout line endings; the digest identifies the immutable blob on
all hosts, and the fixture must have no index or worktree changes.
Only its controller factory and type alias change. Its ten cases, exact shared
values, finite waits, evaluator calls, Assert.Multiple blocks and eighteen
Assert.That expressions remain unchanged. Eighteen counts source expressions;
NUnit's runtime assertion count includes repeated setup/parameterized evaluations.
No independent scenario or expected-value suite is maintained here.

The generated project uses SDK 9.0.316, net9.0, NUnit 3.14.0 and the verified released
Core/JSON dependencies. It compiles the shared wrapper source, not the C# CLI
controller. Generated source, bin, obj, fixture JSON and results stay outside Assets
and source checkouts; Unity ignores the wrapper's `Conformance~` tooling folder.

### Checks and evidence

- `unity-compatibility.yml`: **WSS integration compatibility**, stable acceptance
  **Integration behavioral tests**.
- Wrapper `wss-preflight.yml`: **WSS downloaded-artifact preflight**, stable
  acceptance **Preflight behavioral tests**.
- GUI `unity-ci.yml`: **GUI CI**, stable acceptance **GUI general conformance**.
- GUI `wss-preflight.yml`: **WSS GUI preflight**, same GUI acceptance name.
- Separate top-level **Integration compatibility (Windows/Ubuntu/macOS)** and
  **GUI platform compatibility (Windows/Ubuntu/macOS)** jobs validate the package
  and production transport support boundary on each host. Candidate preflight
  also requires successful platform jobs for all three labels.

Committed wrapper validation needs only its exact wrapper source and the pinned
canonical fixture. GUI validation derives the exact wrapper SHA from its mode160000
gitlink. These public read-only checkouts use the existing workflow token; normal
CI requires no GitHub App secret, Unity license or persistent local runner.

`Invoke-DotNetConformance.ps1` requires clean exact source SHAs, the pinned fixture
hash and the declared 18-file legacy or 20-file macOS projection/hash/importer contract (including
the .NET-only OS Serial runtime tree). It prepares a
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

### Automatic promotion and deployment

Routine dependency promotion targets **dev** in both Unity repositories. All automatic PRs require human review and merge. Main supplies trusted workflow tooling; stable releases remain disabled.

`baseline_ready` is true in the execution configuration. The blank `gui_harness_sha` is not used by automated .NET validation; candidate inputs bind both exact sources.

Core's separate `propagate-unity.yml` completion workflow runs only after the exact
successful `artifacts.yml` **push to dev** completes. Opening a Core PR only tests
that PR. Its own handoff failure cannot change the producer result or interrupt
the existing C# cascade. It verifies producer identity/dev ancestry, all eleven
required producer jobs, the exact unexpired artifact ID and archive checksum before
requesting an existing App token restricted to Unity-wrapper Actions-write.

The wrapper revalidates that complete tuple, resolves a fresh candidate projection
and checks for a verified no-op before obtaining preflight dispatch credentials.
A changed projection requires BOTH source-bound .NET preflights and complete
evidence validation before a wrapper-only contents/PR token can create the
restricted dependency PR. Correlation includes producer/artifact IDs and both
immutable source SHAs; an old failed or ambiguous run is never blindly replaced.

After a human merges the canonical bot PR into wrapper dev, the trusted-base
dispatcher validates the actual merge, latest final-head normal PR CI, approval
and all committed DLL/importer bytes. It then dispatches GUI promotion. The GUI
revalidates the initial proof, executes a NEW candidate preflight against the actual
merged wrapper SHA and current GUI source, verifies it, and only then mints its
own contents/PR-write token for a gitlink-only PR. That PR carries both the original
approval marker and the exact merged-wrapper GUI preflight marker. Repeated exact
requests reuse the existing PR; conflicting/stale branches stop without force push.

Dispatch and completion workflows require presence on the default branch. The wrapper's current main and dev both include the promotion and receipt workflows. Candidate promotion uses existing `WSS_GITHUB_APP_ID` / `WSS_GITHUB_APP_PRIVATE_KEY` access with scoped permissions; runtime configuration must be verified at dispatch. Normal conformance uses public read-only checkout. Credentials and repository settings are not inferred from a previous run.

### Manual Unity verification and coverage limits

`Invoke-UnityConformance.ps1` and the GUI's `tools/UnityConformance/Prepare-Harness.ps1`
retain the Unity 2022.3.62f3 / revision 96770f904ca7 / UTF 1.1.33 EditMode route.
Pass the locally licensed Editor explicitly with `-UnityExe`; its prerequisite check receives that exact path. A fresh manual Editor import/run is required to establish evidence for the exact source being evaluated. Ordinary .NET CI does not launch or activate an Editor.

.NET acceptance proves shared API mapping, layer composition and emulator-observed
protocol/state behavior on .NET. It does not prove Unity importers/DLL resolution,
Mono runtime behavior, MonoBehaviour callbacks/serialization, scene references,
UI managers, player builds, BLE/Serial/native communication or device safety.

### Normalized candidate binding

Successful candidate preflights additionally publish artifact `wss-candidate-provenance` with exactly one six-field `candidate.json`. The caller job depends on the entire reusable validation result, reuses the existing richer proof validator, and rejects wrong source/candidate, corrupted XML and failed suites before output. Existing projection/native/canonical artifacts and validators remain mandatory. This artifact is not an acceptance receipt or release authorization, and it does not clear an earlier failed preflight. The separate release-receipt writer validates the shared acceptance contract.

### Why exact identifiers appear here

| Identifier | Purpose | Placement |
|---|---|---|
| C# fixture commit `7145e2307f997f703748530bf74311ef94455e98` | Selects the unchanged canonical test source so language comparisons use the same cases. | Operational value in [.github/unity-ci.json](.github/unity-ci.json); repeated here for maintainers. |
| Fixture SHA256 `f6aeced83d35255532b6685d9c870307f856aad140da133695a77e9de6104ee2` | Checks the Git blob bytes independently of host checkout line endings. | Operational value in configuration and harness validation. |
| Unity revision `96770f904ca7` | Distinguishes the exact Editor build used by the optional manual harness. | Operational value in execution configuration and prerequisite checks. |

Candidate commit IDs, workflow source pins, archive/file/importer hashes, projection digests, plan IDs and receipt IDs bind evidence to exact code and artifact bytes. They belong in machine-readable configuration, workflow pins and generated evidence. A propagation plan is a generated artifact consumed by validation; it is not a repository planning document. These operational values must stay consistent when dependencies change.

</details>

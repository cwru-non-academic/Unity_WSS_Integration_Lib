# Unity candidate propagation — prepared, not enabled

Development stays in the local Windows Codex task. GitHub-hosted CI is permitted
by the user, subject to a supported Unity license route. The user uses **Personal**
and does not want a paid license. No supported unattended hosted Personal activation
route was verified. All hosted validation/promotion entry points deliberately fail
before Unity execution or write-token creation. They must not be enabled by simply
changing a boolean, copying an activation file, or treating skipped tests as success.

Official references checked 18 October 2026:

- [Unity 2022.3 licensing](https://docs.unity3d.com/2022.3/Documentation/Manual/ManagingYourUnityLicense.html): activation is required; the documented headless command-line procedure is for Pro and excludes Personal. Personal uses Hub.
- [Activation methods](https://docs.unity.com/en-us/engine/6000.0/manual/get-started/install-and-upgrade/licenses-and-activation/license-activation-methods): Hub is the Personal activation route.
- [Unity test CLI](https://docs.unity3d.com/Packages/com.unity.test-framework@1.1/manual/reference-command-line.html): execution flags do not establish hosted activation rights or availability.

The already verified no-purchase alternative is local EditMode after Hub activation.
No local runner, manual-evidence approval handoff, paid activation or credential
export was implemented or assumed. A different execution/evidence design requires
a user decision and a reviewed implementation. Pure .NET checks cannot replace the
real Unity Editor evidence.

## Branch and publication prerequisites

Mirror the actual C# cascade's **dev** targets, not repository defaults:

- CSharp_WSS_Integration_Lib `.github/workflows/promote-wss.yml:38,94,519`
  validates/checks out dev and opens a dev PR.
- Its `dispatch-cli-promotion.yml:8-9` listens for reviewed dev merges;
  `WssAutomatic.ps1:47` resolves downstream dev.
- CLI_CSharp_WSS_Application `promote-integration.yml:29,72,81,333` targets dev.

This dev baseline preserves the newer local history, including
`ce6d9ef00fc2512540366b0bbe33217654b14566`, instead of resetting to older remote
main. Before publication that commit was unavailable from the canonical remote
(HTTP422). GUI dev must pin the published wrapper baseline. Before enabling
automation, review the published baselines, pin the accepted GUI SHA in
`unity-ci.json`, and make dispatchable workflow definitions available on each
default branch. Main merges remain the user's responsibility. Baseline approval
flags and the unresolved Personal license gate remain disabled.

Workflow/check display names intentionally match the C# counterparts, including
their CLI labels in the application repository. Unity filenames and provenance
roles remain distinct. Stable wrapper checks are **Integration behavioral tests**
(committed state) and **Preflight behavioral tests** (candidate state). The GUI
uses **CLI general conformance** in its committed and candidate workflows. Nested
shared-workflow helpers use the counterpart Resolve/preflight/compatibility labels;
validators bind the stable top-level check and its exact workflow path/source.

## Prepared files and contracts

| Path | Responsibility |
|---|---|
| `workflows/unity-compatibility.yml` | Normal committed wrapper acceptance using the pinned GUI harness. |
| `workflows/wss-preflight.yml` | Candidate-only acceptance at immutable wrapper/GUI revisions. |
| `workflows/_unity-validation.yml` | Windows-hosted job definition, explicit failing prerequisites, exact-source checkouts, same EditMode harness, retained evidence. |
| `workflows/promote-wss.yml` | Core tuple -> both Unity preflights -> dependency-only wrapper PR; manual merge. |
| `workflows/dispatch-unity-promotion.yml` | Trusted-base reviewed-merge validation -> GUI promotion request, with normal committed-state acceptance required. |
| `scripts/Resolve-WssRelease.ps1`, `Universal-WssFiles.ps1` | Reused CLI resolver/inventory; resolver additionally requires the exact artifact ID. No latest/older release fallback. |
| `scripts/UnityContract.ps1` | Exact projection, importer hashes, case inventory, secure XML parsing, candidate/source/diff contracts. |
| `scripts/Invoke-UnityConformance.ps1` | Fresh disposable host, pinned fixture, unchanged eighteen assertions, bounded Unity process, exact ten passing cases, XML/log hashes and source-bound evidence. |
| `scripts/UnityPromotion.ps1` | Unity-specific approval schema/marker, correlated dispatch/replay, immutable preflight/runtime evidence and reviewed merge validation. |
| `scripts/Prepare-UnityPromotion.ps1`, `Publish-UnityPromotion.ps1` | Validate before write credentials; reject source races; hash-verified no-op preserving provenance; exact open-PR reuse; closed/orphan conflicts rejected; no force push or merge. |
| `scripts/Dispatch-UnityGui.ps1` | Validate before minting GUI Actions-write credentials; no blind redispatch after uncertain outcomes. |
| `unity-candidate.json` | Current accepted producer tuple and fifteen DLL/importer hashes; original universal payload stays outside Assets. |

Routine wrapper changes are limited to the enumerated projected DLLs/importers and
`.github/unity-candidate.json`. GUI routine PRs change only the mode160000 gitlink
`Assets/SubModules/WSSInterfacingModule`. Bootstrap source/URL changes are separate.

`wss-unity-promotion/v1` binds Core commit/run/artifact/archive SHA256; exact wrapper
and GUI source/preflight IDs; fixture commit/hash; and projection digest. Each
preflight carries the same tuple, actual XML/log digests, ten executed passes and
the eighteen unchanged assertion expressions. C# schema2/CLI roles and its archived
bootstrap exceptions are deliberately not reused as Unity authority.

The fixture is pinned to CSharp_WSS_Integration_Lib commit
`7145e2307f997f703748530bf74311ef94455e98`, source SHA256
`1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44`.
There are no new scenarios, expected values, PlayMode jobs or GUI behavior suite.

## Setup and validation status

Names-only queries found no repository-level Actions secrets or variables in either
Unity repository. Inherited organization/environment configuration and App access
are unverified. Future setup needs `WSS_GITHUB_APP_ID` and
`WSS_GITHUB_APP_PRIVATE_KEY` in the appropriate GitHub scope, with read access to
Core/C# fixture and scoped Unity Actions/contents/PR permissions. No credentials or
permissions were created or changed. `WSS_UNITY_EDITOR_PATH` is only a provisioned
Editor-path variable; setting it does not activate Personal or remove the gate.

Checks actually executed locally: actionlint1.7.12 on eight workflows; PowerShell
parsing of ten scripts/twelve workflow blocks; fifteen transient result/provenance/
projection/scope/gating checks; fresh projection/harness preparation; generated
fixture byte-identical to the actual passing v4 fixture. No new Unity, remote CI,
dispatch or merge was executed for these definitions. The scoped dev baseline is
being published separately from enabling hosted execution. Earlier actual
local Unity2022.3.62f3 EditMode result remains ten passed, zero failed/skipped.

Stable check names: **Integration behavioral tests** for wrapper PRs,
**Preflight behavioral tests** for wrapper candidate evidence, and **CLI general
conformance** for GUI PR/candidate evidence. Establish real running jobs
and resolve the licensing/publication blockers before requiring green checks in
rulesets. The gates intentionally stay red meanwhile.

WSSCore is untouched. A separate future Core change would hand its exact successful
dev producer tuple to wrapper `promote-wss.yml`, after producer completion (the
existing CLI lane waits for that completion). No handoff should be enabled while
Unity prerequisites are unresolved. Shipping player publication is separate and
is not implemented by these dependency-promotion definitions.

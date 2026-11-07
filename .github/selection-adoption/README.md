# Unity selected-test adoption: inactive local review material

Nothing in this directory is loaded by GitHub Actions. Existing ordinary/candidate workflows, product gitlinks, payloads, shared locks and literal reusable-workflow pins are unchanged.

## Prerequisites before activation

1. Publish/review the compatible Core bootstrap. This draft was reviewed against local Core d35a96145014adb03623b4e5eb459946d43465b6. That is a LOCAL dependency reference, not a claim that it is remotely available. Coordinate the actual immutable Core lock and executable pins with the selection owner; do not substitute a floating ref.
2. Adopt compatible payload and reviewed canonical 16-case single/multi policy. Preserve ordinary legacy baseline until that adoption. Do not invoke the new runner against an older fixture/payload or weaken inventories to make it pass.
3. Publish reviewed Unity/GUI bundles and trusted wrapper adapter. GUI must continue using its actual product gitlink; never change it merely to obtain a test runner. If the fixed gitlink predates the adapter, use a separately pinned trusted tooling checkout and verify its identity, or wait for independently authorized product adoption.
4. Complete hosted validation. Windows Application Control blocked the final local DLL loads; no retry or bypass is authorized. Unity Editor, Linux and native Mac runtime validation remain hosted requirements.

## Legacy online wiring

The adjacent fragment and online inspect/evidence bridge description preserve
implemented API compatibility; they are not a deployable offline job graph.
Do not apply the unchanged fragment after readiness checks alone. Activation
requires a separately reviewed current-contract flow with immutable bootstrap
trust and a separate credential-free hosted executor receiving no source/plan,
App or publishing credentials, including read tokens.

The legacy fragment describes prerequisites for unity-wrapper or unity-gui. Read WSS_CI_CHANNEL from the verified channel, not a PR branch name. Preserve ownSha == GITHUB_SHA. Check out Core at the validated lock for ordinary and candidate runs; the old ordinary job may not currently do that.

Follow the reviewed Core tools/release/CAMPAIGN_TEST_SELECTION.md contract: upload the durable context.json only when created=true as wss-ci-test-context-<target-id>, without an attempt suffix, then independently load it before exposing authenticated outputs. Preserve v1/v2 durable recovery. Final evidence uses wss-selected-tests-<target-id>-a<run_attempt>; isolated executor handoff transport is separate and attempt-specific. Pass immutable selection_id, test_repository, test_commit and target_id outputs from prerequisites. Every suite uses the same frozen selection and a separate selected-tests checkout. Reusable candidate platform workflows need these four additional inputs, forwarded from prerequisites; do not select again per platform. This remains an inactive integration prerequisite.

Bridge Invoke-SelectedUnityTests.ps1 calls Core inspect before suites and evidence only after successful mandatory + selected gates. WSS_TEST_SELECTION_ID comes from prerequisite output, never context contents. roots.json binds wrapper, optional GUI, canonical fixture and locked Core tooling. Core rechecks all clean immutable source identities after tests.

Use -ConformanceOnly in the existing primary conformance job. Omit it in Windows/Linux/native Mac platform jobs. Preserve native architecture assertions and all universal-package rejection checks before projection. Retain required acceptance aggregation; add selection prerequisite and selected suite results to it rather than replacing existing mandatory jobs.

The resolver output paths in the fragment match the existing _unity-validation.yml: resolved/extracted/WSS-Universal and resolved/candidate.json. Retain the existing product ConfigPath for each caller. Add matrix label/architecture to suite artifact names to prevent macOS collisions. Upload recursive mandatory-baseline and ble-lifecycle-mandatory evidence, not just top-level globs. Do not include credentials or promote selected test evidence into release authority.

## Unchanged entry points needing eventual coordinated wiring

- Unity _unity-validation.yml prerequisites and conformance job.
- Unity _unity-platform-validation.yml candidate Windows/Linux and native Mac jobs, with frozen selection outputs passed through workflow_call.
- Unity unity-compatibility.yml ordinary platform/native Mac jobs.
- GUI unity-ci.yml and wss-preflight.yml callers, retaining immutable literal wrapper workflow pins.

No new workflow is activated by this commit. The fragment is a review recipe, not a drop-in workflow; the coordinated final patch must bind existing exact resolver paths, token read scope and caller inputs before CI can test it.

## Required security work before selected-suite activation

Selection remains inactive. The bridge now runs the fixed mandatory baseline in a distinct trusted child before any selected executable harness, then snapshots and rechecks its complete evidence inventory in the trusted parent after the selected child completes. Regression tests reject modification, insertion, deletion and directory changes. The redundant baseline inside the selected runner is not acceptance evidence. Selected PowerShell must not share validator/function scope with mandatory execution or post-test acceptance validation.

Authenticate and download producer artifacts in a separate trusted job. A selected executor must receive only verified immutable artifact inputs, never the App private key/token or a runner where those action temp/state secrets were present. Environment stripping alone does not provide this isolation. These prerequisites are independent of ordinary tooling/product separation and must be reviewed before enabling selected policies or workflows.

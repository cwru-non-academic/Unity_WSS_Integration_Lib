# Unity selected-test adoption: inactive local review material

Nothing in this directory is loaded by GitHub Actions. Existing ordinary/candidate workflows, product gitlinks, payloads, shared locks and literal reusable-workflow pins are unchanged.

## Prerequisites before activation

1. Publish/review the compatible Core bootstrap. This draft was reviewed against local Core d35a96145014adb03623b4e5eb459946d43465b6. That is a LOCAL dependency reference, not a claim that it is remotely available. Coordinate the actual immutable Core lock and executable pins with the selection owner; do not substitute a floating ref.
2. Adopt compatible payload and reviewed canonical 16-case single/multi policy. Preserve ordinary legacy baseline until that adoption. Do not invoke the new runner against an older fixture/payload or weaken inventories to make it pass.
3. Publish reviewed Unity/GUI bundles and trusted wrapper adapter. GUI must continue using its actual product gitlink; never change it merely to obtain a test runner. If the fixed gitlink predates the adapter, use a separately pinned trusted tooling checkout and verify its identity, or wait for independently authorized product adoption.
4. Complete hosted validation. Windows Application Control blocked the final local DLL loads; no retry or bypass is authorized. Unity Editor, Linux and native Mac runtime validation remain hosted requirements.

## Wiring

Apply the adjacent fragment to existing prerequisites once, after source and readiness checks, for unity-wrapper or unity-gui. Read WSS_CI_CHANNEL from the verified channel, not a PR branch name. Preserve ownSha == GITHUB_SHA. Check out Core at the validated lock for ordinary and candidate runs; the old ordinary job may not currently do that.

Upload context.json once as wss-selected-tests-<target-id>-a<run_attempt>. Pass immutable selection_id, test_repository, test_commit and target_id outputs from prerequisites. Every suite downloads the same artifact in the same run and uses a separate selected-tests checkout. Reusable candidate platform workflows need these four additional inputs, forwarded from prerequisites; do not select again per platform.

Bridge Invoke-SelectedUnityTests.ps1 calls Core inspect before suites and evidence only after successful mandatory + selected gates. WSS_TEST_SELECTION_ID comes from prerequisite output, never context contents. roots.json binds wrapper, optional GUI, canonical fixture and locked Core tooling. Core rechecks all clean immutable source identities after tests.

Use -ConformanceOnly in the existing primary conformance job. Omit it in Windows/Linux/native Mac platform jobs. Preserve native architecture assertions and all universal-package rejection checks before projection. Retain required acceptance aggregation; add selection prerequisite and selected suite results to it rather than replacing existing mandatory jobs.

The resolver output paths in the fragment match the existing _unity-validation.yml: resolved/extracted/WSS-Universal and resolved/candidate.json. Retain the existing product ConfigPath for each caller. Add matrix label/architecture to suite artifact names to prevent macOS collisions. Upload recursive mandatory-baseline and ble-lifecycle-mandatory evidence, not just top-level globs. Do not include credentials or promote selected test evidence into release authority.

## Unchanged entry points needing eventual coordinated wiring

- Unity _unity-validation.yml prerequisites and conformance job.
- Unity _unity-platform-validation.yml candidate Windows/Linux and native Mac jobs, with frozen selection outputs passed through workflow_call.
- Unity unity-compatibility.yml ordinary platform/native Mac jobs.
- GUI unity-ci.yml and wss-preflight.yml callers, retaining immutable literal wrapper workflow pins.

No new workflow is activated by this commit. The fragment is a review recipe, not a drop-in workflow; the coordinated final patch must bind existing exact resolver paths, token read scope and caller inputs before CI can test it.

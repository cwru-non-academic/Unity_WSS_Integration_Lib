# Trusted Unity payload profiles

The shared .NET runners classify the immutable installed package before compiling a test harness. Full legacy baseline APIs and no layered sentinels identify legacy-v1; all modern APIs must exist for layered-v1. Partial APIs fail closed. Legacy is further restricted to the reviewed producer/run/archive/Core DLL registry. Existing projection, resolver, source, native runtime and release gates still apply.

- Ordinary legacy product: unchanged ten canonical cases, eighteen assertion expressions, plus thirteen BLE canonical/lifecycle cases and the complete platform/projection probes.
- Modern product: unchanged sixteen single-device and sixteen multi-device cases, twenty assertion expressions, plus nineteen BLE canonical/lifecycle cases and the complete platform/projection probes.
- Selected suites and candidate campaigns require modern APIs. Selected suites remain additive to the fixed product baseline. Selection is still inactive until coordinated reviewed Core/tooling adoption.

The identical dev/main config contains both reviewed fixture commits, hashes and case inventories. Ordinary prerequisites select the fixture using verified installed payload identity; candidate prerequisites require the modern fixture and the runner verifies candidate APIs after download. Missing, unknown or altered profile records fail closed. A fixture/payload mismatch is an adoption blocker, not permission to replace fixtures or product source. Modern wrapper and GUI products have adopted compatible modern source/payload pairs on dev and main. Historical legacy regression must still use the matching historical source and payload; do not export historical source into a modern product harness. GUI keeps its actual product gitlink and config. Product adoption alone does not activate selected campaigns: caller integration, source authentication and end-to-end verification remain separate prerequisites, and selection remains inactive.

The hosted legacy regression commits only a synthetic test checkout with the exact current dev config and tooling over the immutable historical product. Its results are runner regression evidence, never authenticated frozen-campaign acceptance evidence. Windows and Ubuntu execute the complete legacy platform runner; macOS performs metadata and isolation checks only in this regression job. Existing modern native Mac jobs remain mandatory.

## Historical tooling-only branch adoption

The protected scripts bind both external mandatory harness builders by strict UTF-8/LF SHA-256. Only the reviewed historical builder is additionally allowed for legacy payloads. That tooling-only adoption preserved each branch's product code, host adapters, tests and payloads; later reviewed product adoption is separate.

The identical host-lifecycle workflow retains the modern reload suite for modern products. Historical products run their complete existing canonical/BLE/platform baseline instead; tooling-only adoption does not copy modern tests or host implementations into a historical product to make it compile. Both native Mac consumer jobs continue to run through the ordinary platform workflow.

## Separate immutable tooling for GUI products

A GUI caller derives its tooling revision from the literal reusable workflow SHA in its exact checked-out workflow. It does not accept tooling identity from selected tests, a branch, or an arbitrary workflow input. Candidate platform calls compare their tooling input to that same authenticated caller pin before executing tooling. Wrapper callers use their own exact source revision.

ToolRoot and ToolSha are paired assertions against the executing helper checkout, not a mechanism to select helper code. ConfigPath must be the common config inside that checkout. Clean roots, hidden index flags, ignored execution inputs and filesystem links are checked; tooling/config are rechecked after execution. BLE receives the same explicit config instead of reading historical product config. Product wrappers, GUI source and gitlinks remain distinct and unchanged. External product builders still require protected hashes and cannot fall back to tooling source when missing.

The hosted separation matrix uses immutable actual GUI dev/main products and their own gitlinks for ordinary checks. Modern candidate regression uses the previously staged GUI064de7b and modern wrapper eb1439a plus the authenticated approved producer package. These are regression proofs, not new frozen campaign acceptance or release receipts.

# Trusted Unity payload profiles

The shared .NET runners classify the immutable installed package before compiling a test harness. Full legacy baseline APIs and no layered sentinels identify legacy-v1; all modern APIs must exist for layered-v1. Partial APIs fail closed. Legacy is further restricted to the reviewed producer/run/archive/Core DLL registry. Existing projection, resolver, source, native runtime and release gates still apply.

- Ordinary legacy product: unchanged ten canonical cases, eighteen assertion expressions, plus thirteen BLE canonical/lifecycle cases and the complete platform/projection probes.
- Modern product: unchanged sixteen single-device and sixteen multi-device cases, twenty assertion expressions, plus nineteen BLE canonical/lifecycle cases and the complete platform/projection probes.
- Selected suites and candidate campaigns require modern APIs. Selected suites remain additive to the fixed product baseline. Selection is still inactive until coordinated reviewed Core/tooling adoption.

A fixture/payload mismatch is an adoption blocker, not permission to replace fixtures or product source. The modern dev host requires modern Core APIs; use actual legacy main product source with its legacy payload. Do not export historical source into a modern product harness. GUI keeps its actual product gitlink and config, and therefore remains blocked on modern selected campaigns until supported product adoption.

The hosted legacy regression commits only a synthetic test checkout with current tooling over the immutable historical product. Its results are runner regression evidence, never authenticated frozen-campaign acceptance evidence. Windows and Ubuntu execute the complete legacy platform runner; macOS performs metadata and isolation checks only in this regression job. Existing modern native Mac jobs remain mandatory.

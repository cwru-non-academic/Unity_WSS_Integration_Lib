# WSS Unity Interface
C# class that has all the methods to communicate with the WSS and software specific classes that implements some of the functionalities necessary for that program.

All documentation about the API and other implementations can be found in [GitHub Pages](https://cwru-non-academic.github.io/WSS_Documentation/).

## Try the library without hardware

Open the [Unity GUI application quickstart](https://github.com/cwru-non-academic/GUI_Unity_WSS_Application#first-stimulation-in-the-unity-editor). Its Console scene contains a configured `Stimulation` component. Select **Test** in the Inspector before Play mode to exercise the UI without opening a live transport. The GUI uses its pinned wrapper revision.

To add the wrapper to a Unity project, [add it as a submodule](#add-the-library-to-a-unity-project) and use the Unity Editor version pinned by that project. To exercise this checkout's .NET lifecycle tests, see [Local lifecycle tests](#local-lifecycle-tests).

## Configuration reload

This source requires Core's `WssConfigurationSnapshot` API. This candidate
couples the runtime source with the authenticated modern Core distribution.
Applications must adopt this wrapper and payload together.

Press **A**, call `resetRadio()`, or call `Stimulation.LoadCoreConfigFile()` to
stage edited contents of the active `stimConfig.json` and use the existing host
reset path. Calibration/model values remain as currently applied. The three
components (`Stimulation`, `StimulationParams`, `Stimulationbasic`) use the same
enable/disable and deferred BLE cleanup behavior. A reset installs a new
configuration generation even when its file path has not changed.

For model/calibration hosts, `LoadParamsJson()` reloads **all three JSON files**
from their original startup/default paths. It returns to those defaults after
an earlier override; it does not reload the last selected profile implicitly.
`LoadParamsJson(directory)` selects all three standard filenames there.
**`LoadParamsJson(explicitParameterFile)` uses that parameter file and the
startup-default Core and model files. It does not use sibling Core/model files.**
Startup paths are anchored once, so later working-directory changes do not
change defaults.

Staging is read-only. Reconstruction installs the exact validated snapshots,
even if files change during cleanup. Any Core value change uses the host reset;
unchanged Core allows atomic model/calibration publication without reconnecting.
BLE reset may complete on a later `Update()` after old cleanup finishes. Returning
from the request is not a claim that the replacement has reached operational state.

Validation errors leave the running configuration unchanged. Cleanup or
construction failure leaves the host not initialized, reports `LastReloadError`,
and does not replay old stimulation. `RetryReload()` retries a retained validated
request without rereading its files; a new reload request stages new contents.
External disable, shutdown or destruction cancels pending reconstruction. A later
enable starts a fresh request; obsolete requests cannot publish a replacement.

## Local lifecycle tests

`Tests~/HostLifecycle` links the production component lifecycle methods, reset
path, transport adapter and cleanup code. It substitutes engine services and
uses Core's emulator for all transport I/O. These are ordinary .NET tests:
**they do not establish Unity Editor/Play execution, native BLE execution, or
universal-package acceptance**. The `~` folder keeps shims out of Unity imports.

Use the same test project/command for all three component types; do not copy
their behavior matrix into separate CI jobs. Supply explicit Core and transport
inputs, for example:

```powershell
dotnet test 'Tests~/HostLifecycle/Wss.Unity.HostLifecycle.Tests.csproj' -c Release `
  -p:WSS_CORE_PROJECT='<Core checkout>/WSS_Core_Interface.csproj' `
  -p:WSS_TRANSPORT_ARTIFACT_DIR='<transport distribution>'
```

For binary-input testing, supply `WSS_ARTIFACT_DIR` instead of `WSS_CORE_PROJECT`.
Release/provenance checks remain separate from this source lifecycle suite.

## Unity requirements

Use the Editor version defined by the consuming project. In a new project, use
**Edit → Project Settings → Player → Other Settings → Configuration** to select
the **.NET Framework** API Compatibility Level needed by the wrapper. The Unity
GUI configures its own project and ships the Unity Package Manager dependencies.

## CI checks

Pull requests and pushes to `dev` and `main` expose the same separate contexts as the C# integration:

- `Integration behavioral tests`
- `Integration compatibility (Windows)`
- `Integration compatibility (Ubuntu)`
- `Integration compatibility (macOS)`

Behavioral validation runs the C# canonical fixture selected by the verified payload profile through the shared production command/stack source. Modern products require both single-device and multi-device suites; the reviewed legacy profile retains its original ten-case/eighteen-expression baseline. Fixture identities and complete case inventories are declared in [`.github/unity-ci.json`](.github/unity-ci.json). Each platform job additionally publishes a disposable .NET consumer, verifies every projected payload byte in build and publish output, and compiles the unmodified `WssTransportSupport` selector with that host's Unity platform symbol. Serial construction must load the exact OS-specific Ports runtime. Windows BLE checks backend loading and production native exports without scanning, connecting, or stimulating. macOS Mono selects the registered CoreBluetooth backend and verifies disconnected construction/disposal and native ABI loading. Ubuntu verifies the explicit unsupported Unity BLE exception; Linux BLE support in Core does not enable it in the Unity selector.

These checks run on .NET 9, **not the Unity engine**. A throwing shim supplies only the selector's unused Unity logging methods. They do not validate scenes, UI managers, Unity Editor/Player execution, Mono/IL2CPP compatibility, or hardware. The nested `runtimes/` payload is for .NET consumers and has disabled Unity importers; shipping it does not establish Unity Serial support. Licensed Unity EditMode validation remains a distinct explicit path.

Candidate preflight runs the same three platform checks against independently resolved exact producer artifacts. Promotion requires their successful completion in addition to the original canonical evidence, source, fixture, and projection gates. Platform evidence records the host and unsupported transport boundary separately from Unity execution.

## Add the library to a Unity project

For an existing WSS application checkout, use `git submodule update --init --recursive`
from the application root to restore its pinned wrapper. For a new consuming
Unity project, add the current library repository from the project root:

```bash
git submodule add https://github.com/cwru-non-academic/Unity_WSS_Integration_Lib.git Assets/SubModules/WSSInterfacingModule
```

Check out the intended released wrapper revision in the new submodule and
commit the recorded submodule revision in the consuming project. If the
project does not already depend on `com.unity.nuget.newtonsoft-json`, add
version `3.2.1` to `Packages/manifest.json`. On import, check the Unity Console
for package and plugin errors before adding the desired stimulation component.

## Update the wrapper or Core dependency

For application updates, change the wrapper pin through a reviewed application
change. If you maintain the wrapper's Core payload, follow the [Core distribution reference](https://github.com/cwru-non-academic/WSSCore#one-universal-distribution)
and the candidate checks above. Adopt the full payload with its Unity import
settings and verify it on the target platform before advancing an application pin.

## API and other Documentation
All documentation reagarding hardware, API, and communication protocols can be found here [WSS Docs](https://cwru-non-academic.github.io/WSS_Documentation/).

## Desktop BLE and validation boundaries

Select `BLE` with the existing transport controls; automatic discovery, `name:` and `id:` selectors retain their existing meaning. Windows uses the registered Windows backend. macOS Editor/standalone uses `MacBleBackend.Register()` with Mono. Both macOS plugin importers are restricted to OSX Editor and OSXUniversal standalone, use AnyCPU for the universal native binary, and exclude `ENABLE_IL2CPP`. Unity Linux BLE and macOS IL2CPP are explicitly unsupported; no new backend or AOT callback bridge is inferred from Core support.

macOS needs both `backends/macos/WSS.Transport.BLE.MacOS.dll` and `libwss_macos_ble.dylib`, macOS 11 or newer, and a compatible arm64/x86_64 host. Before shipping a Mac Player, the application maintainer must choose a supported deployment target and supply its Bluetooth Usage Description/authorization configuration. Existing application settings and stimulation configuration, including custom `0x80` targets, are not changed automatically. See [Unity macOS Player settings](https://docs.unity3d.com/2022.3/Documentation/Manual/PlayerSettings-macOS.html).

The separate `Invoke-BleLifecycleConformance.ps1` suite runs the canonical C# scenarios for the verified payload profile through the production BLE lifetime adapter over the Core emulator, plus three cancellation, unchanged byte forwarding and disposal regressions. Modern profiles require sixteen canonical cases and twenty unchanged assertion expressions; the reviewed legacy profile retains ten and eighteen respectively. It uses a fake transport, not a BLE backend or physical device. Native package/default-context/ABI checks remain separate. The GUI's disposable Unity harness additionally checks the real PluginImporter settings and offers load-only native diagnostics. Windows Editor proof does not establish macOS Editor/Player, IL2CPP, Bluetooth authorization or hardware proof. Run actual macOS Mono Editor and intended Player checks before claiming native Unity macOS compatibility.


Source synchronization may retain an exact legacy 18-file committed payload without adopting new Core bytes. The platform consumer reads the facade's declared capability: a declared macOS backend requires both matching managed/native files; an undeclared legacy backend must carry neither and is explicitly unsupported on macOS. Candidate projection stays on the strict 27-file universal / 20-file Unity path. link.xml preserves the reflected Mono bootstrap when the macOS assembly is present; it does not enable IL2CPP or manufacture backend support.

Dev release acceptance uses `release-receipt.yml` with the exact Core producer run
and frozen plan ID. It emits a read-only receipt after the human-reviewed bot
merge, paired preflights, candidate-byte/projection checks and fresh final-merge
CI. GUI acceptance additionally verifies the actual wrapper gitlink and its
post-merge preflight. Main supplies registered trusted tooling; stable releases
remain disabled. Coverage describes the .NET harness, not Unity Editor/Player,
IL2CPP or physical BLE validation.

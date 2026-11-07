# WSS Unity Interface
C# class that has all the methods to communicate with the WSS and software specific classes that implements some of the functionalities necessary for that program.

All documentation about the API and other implementations can be found in [GitHub Pages](https://cwru-non-academic.github.io/WSS_Documentation/).

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

## Unity Requirements
Change NET framework 2.1 to NET Framework within Project settings > player > other settings > config.

## CI checks

Pull requests and pushes to `dev` and `main` expose the same separate contexts as the C# integration:

- `Integration behavioral tests`
- `Integration compatibility (Windows)`
- `Integration compatibility (Ubuntu)`
- `Integration compatibility (macOS)`

Behavioral validation runs the pinned C# canonical fixture through the shared production command/stack source: ten cases and eighteen unchanged assertion expressions. Each platform job additionally publishes a disposable .NET consumer, verifies every projected payload byte in build and publish output, and compiles the unmodified `WssTransportSupport` selector with that host's Unity platform symbol. Serial construction must load the exact OS-specific Ports runtime. Windows BLE checks backend loading and production native exports without scanning, connecting, or stimulating. macOS Mono selects the registered CoreBluetooth backend and verifies disconnected construction/disposal and native ABI loading. Ubuntu verifies the explicit unsupported Unity BLE exception; Linux BLE support in Core does not enable it in the Unity selector.

These checks run on .NET 9, **not the Unity engine**. A throwing shim supplies only the selector's unused Unity logging methods. They do not validate scenes, UI managers, Unity Editor/Player execution, Mono/IL2CPP compatibility, or hardware. The nested `runtimes/` payload is for .NET consumers and has disabled Unity importers; shipping it does not establish Unity Serial support. Licensed Unity EditMode validation remains a distinct explicit path.

Candidate preflight runs the same three platform checks against independently resolved exact producer artifacts. Promotion requires their successful completion in addition to the original canonical evidence, source, fixture, and projection gates. Platform evidence records the host and unsupported transport boundary separately from Unity execution.

## How to add a submodule to exiting project
1. Close other software using the code solution (Unity, Visual Studio, etc)
2. If using git desktop, open the command prompt by going to `Repository>Open in Command Prompt`
3. Use command `git submodule add <submoduleURL> <pathInProject>` 
	- if using a submodule inside of Unity make sure the path is inside the Assests folder
	- Ex HTTPS: `git submodule add https://github.com/cwru-non-academic/WSSInterfacingCode Assets\SubModules\WSSInterfacingModule`
 	- Ex SSH: `git submodule add git@github.com:cwru-non-academic/HFI_WSS_Interface.git Assets\SubModules\WSSInterfacingModule`
4. Click `Current repository>Add>Add existing repository..` and locate the folder where you installed the submodule `<pathInProject>` 
5. Remove old scripts from the project that are now part of the submodule
6. Open solution dependent software and let it refactor.
7. (Unity Only) Make sure all you scripts in the scene are still available and linked correctly.
8. (Unity only) Add `"com.unity.nuget.newtonsoft-json": "3.2.1",` to your package manager manifest under dependencies found in `<project>/Packages/manifest.json`

## How to commit a git project that has submodules (Git Desktop)
1. This only applies if the changes were made to the submodule, otherwise just commit as normal.
2. Inside of the git Desktop a warning will appear that says there are submodule chnages.
3. Changes to submodules must be commited first in the submodules repo.
4. If the submodule repo is already setup, just click open repository shortcut under the submodule changes warning.
5. If it is not setup, click the shortcut to add it to Git Desktop.
6. Once in the submodule repo, commit the changes as normal.
7. Return to the main repo and commit the changes there (The chnage in commit ID will be not be selected by default. select it and then commit). 

## How to commit a git project that has submodules (Git CMD)
`git clone --recursive git@github.com:cwru-non-academic/HFI_WSS_Interface.git`

## How to pull a submodule change (Git Desktop)
1. Make sure the git submodule repo is already part of your repos in git desktop
2. If not add it by following `How to add a submodule to exiting project`
3. Go to the submodule repo and pull changes as normal. 
4. Pulling a submodule will add a change in commit ID to the main repo. 
	- Multiple changes in commit ID can be commited to the main repo as a single commit and together with other changes to the main repo.

## How to update the DLLs
1. Download the desired release version of the DLLs from [Releases](https://github.com/cwru-non-academic/WSSCoreInterface/releases).  
2. Clear the old DLLs in `SubModules\WSSInterfacingModule\Plugins\WSS_Core_Interface`.  
3. Extract the ZIP file downloaded from the GitHub release page.  
4. Paste the entire contents of the `WSS_Core_Interface` folder into `SubModules\WSSInterfacingModule\Plugins\WSS_Core_Interface`.

## API and other Documentation
All documentation reagarding hardware, API, and communication protocols can be found here [WSS Docs](https://cwru-non-academic.github.io/WSS_Documentation/).

## Desktop BLE and validation boundaries

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

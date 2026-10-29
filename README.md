# WSS Unity Interface
C# class that has all the methods to communicate with the WSS and software specific classes that implements some of the functionalities necessary for that program.

All documentation about the API and other implementations can be found in [GitHub Pages](https://cwru-non-academic.github.io/WSS_Documentation/).

## Unity Requirements
Change NET framework 2.1 to NET Framework within Project settings > player > other settings > config.

## CI checks

Pull requests and pushes to `dev` and `main` expose the same separate contexts as the C# integration:

- `Integration behavioral tests`
- `Integration compatibility (Windows)`
- `Integration compatibility (Ubuntu)`
- `Integration compatibility (macOS)`

Behavioral validation runs the pinned C# canonical fixture through the shared production command/stack source: ten cases and eighteen unchanged assertion expressions. Each platform job additionally publishes a disposable .NET consumer, verifies every projected payload byte in build and publish output, and compiles the unmodified `WssTransportSupport` selector with that host's Unity platform symbol. Serial construction must load the exact OS-specific Ports runtime. Windows BLE checks backend loading and production native exports without scanning, connecting, or stimulating. Ubuntu/macOS verify the selector's explicit unsupported BLE exception; Linux BLE support in Core does not enable it in the Unity selector.

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

The macOS receiver accepts the exact 27-file universal archive, projects the macOS DLL/dylib pair with disabled Unity importers, and verifies their exact bytes, default load context and native ABI exports in hosted .NET. The Unity selector still rejects non-Windows BLE. This is package compatibility evidence, not physical BLE or Unity Editor/Player support. Canonical producer tuple: run 40794719291, commit 25ee25e519e77be96a918b9b63f3a402c550d631, artifact 12863706436, ZIP SHA256 b88d70c12b67445adb092bea8f5beebf72f89e605e2d531b52d14e6a72c501f3.

# WSS Unity Integration Library

Use WSS from a Unity application through the `Stimulation` component. It composes the shared Core, stimulation-parameter and model layers and advances them from Unity's update loop.

For a complete application, start with the [Unity GUI README](https://github.com/cwru-non-academic/GUI_Unity_WSS_Application#readme). Shared architecture, configuration and API references are in the [WSS documentation](https://cwru-non-academic.github.io/WSS_Documentation/).

## Add to a Unity project

Use Unity **2022.3.62f3**, the version used by the bundled GUI, and Git. Close Unity while adding the submodule. From your application's repository root:

```bash
git submodule add https://github.com/cwru-non-academic/Unity_WSS_Integration_Lib.git Assets/SubModules/WSSInterfacingModule
git submodule update --init --recursive
```

When cloning an application that already includes the library, use `git clone --recurse-submodules <application-url>` instead. Keep the application's recorded submodule commit so its scripts and bundled DLLs stay together.

1. Open the project in Unity. Set **Project Settings > Player > Other Settings > Api Compatibility Level** to **.NET Framework** for the desktop target.
2. Add `"com.unity.nuget.newtonsoft-json": "3.2.1"` to the `dependencies` object in `Packages/manifest.json`. The library's bundled Newtonsoft DLL is excluded by its plugin import settings; keep those `.meta` files.
3. Create `Assets/StreamingAssets` and copy `stimConfig.json`, `stimParams.json` and `modelConfig.json` from the [GUI's example configuration](https://github.com/cwru-non-academic/GUI_Unity_WSS_Application/tree/main/Assets/StreamingAssets). These files configure the Core, channel parameters and model respectively.
4. Add a `Stimulation` component to a GameObject. Before entering Play mode, set **Transport Type** to **Test** for an in-memory startup without device I/O. Auto selection and Device Name are ignored in this mode.

The library includes the managed Core and transport DLLs under `Plugins/WSS_Core_Interface`. Do not add another copy of those assemblies to the project.

## Minimal simulator status example

Save this as `Assets/Scripts/WssStatus.cs`, attach it to a GameObject, and assign the Test-configured `Stimulation` component in the Inspector:

```csharp
using UnityEngine;

public sealed class WssStatus : MonoBehaviour
{
    [SerializeField] private Stimulation stimulation;
    private bool reported;

    private void Update()
    {
        if (!reported && (stimulation.Ready() || stimulation.Started()))
        {
            reported = true;
            Debug.Log("WSS simulator initialized");
        }
    }
}
```

Enter Play mode and check the Unity Console. `Stimulation` initializes on enable, ticks in `Update`, and shuts down when disabled or when Play mode ends. Call its methods on Unity's main thread. The example only reports status; it sends no application stimulation commands.

## Select a device

Stop Play mode before changing the transport. Select **Serial** or **BLE** and choose automatic selection or disable **Auto** and enter a specific **Device Name**. Serial expects a port name; BLE accepts an advertised name, `name:<name>`, or `id:<identifier>` understood by the host backend. Keep the component disabled until configuration and device selection are ready: enabling it begins connection and device setup.

Use [shared platform and configuration guidance](https://cwru-non-academic.github.io/WSS_Documentation/) when preparing a device session. `resetRadio()` rebuilds the selected connection; `releaseRadio()` shuts it down. Wait for `Ready()` or `Started()` before issuing application commands.

## Dependencies and reference

Update the entire compatible Core artifact set together with its plugin metadata; avoid mixing DLLs from different releases. Core releases are published from [WSSCore](https://github.com/cwru-non-academic/WSSCore/releases). The application records the library version through its submodule commit.

- [Unity GUI setup and controls](https://github.com/cwru-non-academic/GUI_Unity_WSS_Application#readme)
- [WSS documentation and API reference](https://cwru-non-academic.github.io/WSS_Documentation/)
- [Core source](https://github.com/cwru-non-academic/WSSCore)

param([Parameter(Mandatory)][string]$ConfigPath)
. "$PSScriptRoot/UnityContract.ps1"
$config=Read-UnityConfig $ConfigPath
$missing=@()
if (!$config.baseline_ready) { $missing+='Review the preserved dev baseline/default-branch definitions; verify the app gitlink and accepted harness pin.' }
if ($config.gui_harness_sha -cnotmatch '^[0-9a-f]{40}$') { $missing+='Pin the published passing GUI harness SHA in .github/unity-ci.json.' }
# Personal activation is through Hub; no supported unattended hosted route was verified.
# Keep this failing until a supported route is established and reviewed in code.
$missing+='Unity Personal hosted execution is blocked: no documented unattended hosted activation/provisioning route is implemented. Use the already verified Hub-activated local EditMode path; do not export activation material or substitute a Pro serial.'
if (!$env:WSS_UNITY_EDITOR_PATH -or !(Test-Path -LiteralPath $env:WSS_UNITY_EDITOR_PATH -PathType Leaf)) { $missing+='Provision the licensed exact Editor on the Windows hosted job and set WSS_UNITY_EDITOR_PATH.' }
if ($missing.Count -gt 0) { throw ($missing -join "`n") }
if ((Get-Item -LiteralPath $env:WSS_UNITY_EDITOR_PATH).VersionInfo.ProductVersion -notlike '2022.3.62f3*') { throw 'Provisioned Editor is not the pinned version.' }

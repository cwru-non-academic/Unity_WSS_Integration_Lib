param([Parameter(Mandatory)][string]$ConfigPath, [string]$UnityExe=$env:WSS_UNITY_EDITOR_PATH)
. "$PSScriptRoot/UnityContract.ps1"
$config=Read-UnityConfig $ConfigPath
# This guard belongs only to the retained, explicitly invoked manual Editor path.
# Ordinary .NET CI never invokes Unity or treats its results as Editor evidence.
if ($env:GITHUB_ACTIONS -ceq 'true') { throw 'Hosted Unity activation remains unverified. Use ordinary .NET CI; run the licensed Editor check manually.' }
if (!$UnityExe -or !(Test-Path -LiteralPath $UnityExe -PathType Leaf)) { throw 'Supply the exact locally licensed Editor with -UnityExe or WSS_UNITY_EDITOR_PATH.' }
if ((Get-Item -LiteralPath $UnityExe).VersionInfo.ProductVersion -notlike "$($config.editor)*") { throw 'Local Editor is not the pinned version.' }

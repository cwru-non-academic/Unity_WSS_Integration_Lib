param([Parameter(Mandatory)][string]$ProjectionRoot,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Scratch)
. "$PSScriptRoot/UnityContract.ps1"
if (Test-Path $Scratch) { throw 'Negative-test scratch must be new.' }
New-Item -ItemType Directory -Path $Scratch | Out-Null
Copy-Item -Path (Join-Path $ProjectionRoot '*') -Destination $Scratch -Recurse
Assert-UnityProjection $Scratch $Record
if ('backends/macos/WSS.Transport.BLE.MacOS.dll' -cnotin @(Get-UnityCommittedProjectionFiles $Record)) {
    Write-Output 'Legacy 18-file projection verified. Declared-backend presence is independently enforced by the platform consumer; no macOS support is inferred.'
    return
}
function Require-Rejection {
    $rejected=$false
    try { Assert-UnityProjection $Scratch $Record } catch { $rejected=$true }
    if (!$rejected) { throw 'Invalid projection was accepted.' }
}
$native=Join-Path $Scratch 'backends/macos/libwss_macos_ble.dylib'
$bytes=[IO.File]::ReadAllBytes($native)
Remove-Item -LiteralPath $native
Require-Rejection
[IO.File]::WriteAllBytes($native,$bytes)
[IO.File]::WriteAllBytes($native,([byte[]]@(0)))
Require-Rejection
[IO.File]::WriteAllBytes($native,$bytes)
$extra=Join-Path $Scratch 'stale.dylib'
[IO.File]::WriteAllBytes($extra,([byte[]]@(0)))
Require-Rejection
Remove-Item -LiteralPath $extra
$meta=$native+'.meta'; $original=[IO.File]::ReadAllText($meta)
[IO.File]::WriteAllText($meta,$original.Replace('enabled: 0','enabled: 1'))
Require-Rejection
[IO.File]::WriteAllText($meta,$original)
foreach ($invalid in @($original.Replace('enabled: 0','enabled: 1'),$original.Replace('OS: OSX','OS: Windows'),$original.Replace("  - '!ENABLE_IL2CPP'",'  - ENABLE_IL2CPP'),$original.Replace('CPU: AnyCPU','CPU: x86_64'))) {
    # Exercise semantic importer policy independently of the metadata hash gate.
    $rejected=$false
    try { Assert-UnityMacImporter $invalid } catch { $rejected=$true }
    if (!$rejected) { throw 'Unsupported importer policy was accepted.' }
    [IO.File]::WriteAllText($meta,$invalid)
    Require-Rejection
}
[IO.File]::WriteAllText($meta,$original)
Assert-UnityProjection $Scratch $Record
Write-Output 'PASS: missing/corrupt macOS native payload, stale dylib and unsupported importer targets/IL2CPP/architecture rejected.'

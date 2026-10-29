param([Parameter(Mandatory)][string]$ProjectionRoot,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Scratch)
. "$PSScriptRoot/UnityContract.ps1"
if (Test-Path $Scratch) { throw 'Negative-test scratch must be new.' }
New-Item -ItemType Directory -Path $Scratch | Out-Null
Copy-Item -Path (Join-Path $ProjectionRoot '*') -Destination $Scratch -Recurse
Assert-UnityProjection $Scratch $Record
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
Assert-UnityProjection $Scratch $Record
Write-Output 'PASS: missing/corrupt macOS native payload, stale dylib and enabled importer rejected.'

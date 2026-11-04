param([Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$MatrixResult,[switch]$RequireBackend)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/MacOSConsumerContract.ps1"
$failures=@()
foreach ($entry in @(@('Intel x64','x64','X64'),@('Apple Silicon arm64','arm64','Arm64'))) {
    try {
        $p=Assert-MacOSConsumerProbe (Join-Path $EvidenceRoot "$($entry[1])/platform-result.json") $entry[2] -RequireBackend:$RequireBackend
        $line="macOS $($entry[0]): PASS — $($p.ble). .NET host; Unity engine and physical BLE not executed."
    } catch { $line="macOS $($entry[0]): FAIL — $($_.Exception.Message)"; $failures+=$line }
    Write-Output $line
    $line >> $env:GITHUB_STEP_SUMMARY
}
if ($MatrixResult -cne 'success') { $failures+='One or more native architecture consumer jobs failed or were skipped.' }
if ($failures.Count) { throw ($failures -join "`n") }

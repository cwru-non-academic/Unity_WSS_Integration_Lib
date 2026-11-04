$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/../MacOSConsumerContract.ps1"
$temp=Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
$null=New-Item -ItemType Directory -Path $temp
$path=Join-Path $temp 'platform-result.json'
$count=0
function Reject([scriptblock]$Action) {
    $failed=$false
    try { & $Action } catch { $failed=$true }
    if (!$failed) { throw 'Invalid Mac coverage evidence was accepted.' }
    $script:count++
}
function Probe([string]$Arch='Arm64') {
    [pscustomobject]@{schema='wss-dotnet-platform-probe/v1';execution='dotnet';unity_executed=$false;hardware_access=$false;
        architecture=$Arch;os='macOS synthetic metadata fixture';ble='macOS native ABI fixture';macos_backend_declared=$true;macos_native_abi_verified=$true}
}
try {
    foreach ($arch in @('X64','Arm64')) {
        Probe $arch | ConvertTo-Json | Set-Content $path
        $null=Assert-MacOSConsumerProbe $path $arch -RequireBackend;$count++
        $other=if ($arch -ceq 'X64') { 'Arm64' } else { 'X64' }
        Reject { Assert-MacOSConsumerProbe $path $other -RequireBackend }
    }
    foreach ($field in @('schema','execution','unity_executed','hardware_access','os','macos_native_abi_verified')) {
        $p=Probe
        $p.$field=if ($field -in @('unity_executed','hardware_access')) { $true } elseif ($field -ceq 'macos_native_abi_verified') { $false } else { 'wrong' }
        $p | ConvertTo-Json | Set-Content $path
        Reject { Assert-MacOSConsumerProbe $path 'Arm64' -RequireBackend }
    }
    $p=Probe;$p.PSObject.Properties.Remove('macos_native_abi_verified');$p|ConvertTo-Json|Set-Content $path
    Reject { Assert-MacOSConsumerProbe $path 'Arm64' -RequireBackend }
    $p=Probe;$p.macos_backend_declared=$false;$p.ble='unsupported platform/payload';$p|ConvertTo-Json|Set-Content $path
    $null=Assert-MacOSConsumerProbe $path 'Arm64';$count++
    Reject { Assert-MacOSConsumerProbe $path 'Arm64' -RequireBackend }
    Reject { Assert-MacOSConsumerProbe (Join-Path $temp 'missing.json') 'X64' }
    Write-Output "PASS: $count Mac architecture/coverage contract checks; synthetic metadata only, not native execution proof."
} finally { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $temp }

. "$PSScriptRoot/wss-ci/Evidence.ps1"
function Assert-MacOSConsumerProbe([string]$Path,[string]$Architecture,[switch]$RequireBackend) {
    if (!(Test-Path -LiteralPath $Path)) { throw "Missing macOS $Architecture consumer evidence." }
    $p=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Assert-WssCiEvidenceFields $p @{schema='wss-dotnet-platform-probe/v1';execution='dotnet';unity_executed=$false;hardware_access=$false;architecture=$Architecture}
    if ($p.os -notmatch 'Darwin|macOS') {throw "Invalid native macOS $Architecture OS identity."}
    $declared=$p.PSObject.Properties['macos_backend_declared']
    $abi=$p.PSObject.Properties['macos_native_abi_verified']
    if ($declared -and $declared.Value -ceq $true) {
        if (!$abi -or $abi.Value -cne $true) { throw "Missing native ABI proof for declared macOS $Architecture backend." }
    } elseif ($RequireBackend -or $p.ble -notmatch 'unsupported') {
        throw "macOS $Architecture backend support was not verified."
    }
    $p
}

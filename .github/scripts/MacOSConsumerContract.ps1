. "$PSScriptRoot/wss-ci/Evidence.ps1"
function Assert-MacOSConsumerProbe([string]$Path,[string]$Architecture,[switch]$RequireBackend,[string]$Repository=$env:GITHUB_REPOSITORY,[string]$RunId=$env:GITHUB_RUN_ID,[string]$Attempt=$env:GITHUB_RUN_ATTEMPT,[string]$SourceSha=$env:GITHUB_SHA) {
    if (!(Test-Path -LiteralPath $Path)) { throw "Missing macOS $Architecture consumer evidence." }
    $p=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    # Old committed payload diagnostics may precede the identity contract.
    # Every candidate backend proof must carry the current versioned identity.
    if($RequireBackend -or $p.PSObject.Properties['ci']) {
        Assert-WssCiEvidenceIdentity $p.ci $Repository $RunId $Attempt $SourceSha $Architecture
    }
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

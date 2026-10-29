param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('wrapper','gui')][string]$Role='wrapper',
    [string]$GuiRoot='',
    [string]$GuiSha='',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',
    [string]$CandidatePath=''
)
. "$PSScriptRoot/UnityContract.ps1"
if (Test-Path -LiteralPath $OutputRoot) { throw 'Platform output root must be new.' }
# This preserves all canonical cases/assertions, exact-source and projection gates
# while proving that the same production commands run on this host platform.
& "$PSScriptRoot/Invoke-DotNetConformance.ps1" -WrapperRoot $WrapperRoot -FixtureRoot $FixtureRoot -WrapperSha $WrapperSha -ConfigPath $ConfigPath -OutputRoot (Join-Path $OutputRoot 'conformance') -Role $Role -GuiRoot $GuiRoot -GuiSha $GuiSha -Mode $Mode -ArtifactRoot $ArtifactRoot -CandidatePath $CandidatePath
if (!$?) { throw 'Platform command conformance failed.' }
$record=Get-Content -LiteralPath (Join-Path $OutputRoot 'conformance/projection.json') -Raw | ConvertFrom-Json
$projection=if ($Mode -ceq 'candidate') { Join-Path $OutputRoot 'conformance/projection' } else { Join-Path $WrapperRoot $UnityPluginPath }
& "$PSScriptRoot/Test-UnityReceiver.ps1" -ProjectionRoot $projection -Record $record -Scratch (Join-Path $OutputRoot 'inventory-negative')
$probe=Join-Path $OutputRoot 'probe'
& (Join-Path $WrapperRoot 'Conformance~/Prepare-PlatformHarness.ps1') -Destination $probe -ProjectionRoot $projection
$publish=Join-Path $OutputRoot 'publish'
Push-Location $probe
try {
    & dotnet publish Wss.PlatformCompatibility.csproj -c Release -o $publish *> (Join-Path $OutputRoot 'publish.log')
    if ($LASTEXITCODE -ne 0) { throw 'Platform probe publish failed. Inspect publish.log.' }
} finally { Pop-Location }
foreach ($source in $UnityProjectionFiles) {
    $relative=Get-UnityProjectionPath $source
    foreach ($directory in @((Join-Path $probe 'bin/Release/net9.0'),$publish)) {
        if ((Get-FileHash -LiteralPath (Join-Path $directory $relative)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $projection $relative)).Hash) {
            throw "Build/publish lost or replaced a payload file: $relative"
        }
    }
}
$result=Join-Path $OutputRoot 'platform-result.json'
& dotnet (Join-Path $publish 'Wss.PlatformCompatibility.dll') $projection $result *> (Join-Path $OutputRoot 'platform.log')
Get-Content -LiteralPath (Join-Path $OutputRoot 'platform.log') | Write-Output
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $result)) { throw 'Production transport selection/load probe failed.' }
Assert-UnityProjection $projection $record
Assert-UnitySource $WrapperRoot $WrapperSha
Assert-UnitySource $FixtureRoot (Read-UnityConfig $ConfigPath).fixture_commit
if ($GuiRoot) { Assert-UnitySource $GuiRoot $GuiSha -IgnoreSubmodule }
$evidence=Get-Content -LiteralPath (Join-Path $OutputRoot 'conformance/evidence.json') -Raw | ConvertFrom-Json
$evidence.schema='wss-dotnet-platform-evidence/v1'
$evidence | Add-Member -NotePropertyName platform_result_sha256 -NotePropertyValue ((Get-FileHash -LiteralPath $result).Hash.ToLowerInvariant())
$evidence | Add-Member -NotePropertyName platform_log_sha256 -NotePropertyValue ((Get-FileHash -LiteralPath (Join-Path $OutputRoot 'platform.log')).Hash.ToLowerInvariant())
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'platform-evidence.json')
Write-Output 'PASS: exact package build/publish propagation, host runtime selection, production BLE support boundary and canonical command conformance. Unity was not executed.'

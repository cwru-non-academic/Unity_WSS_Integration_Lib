# Inactive until selection-adoption workflow templates and the coordinated Core lock land.
param(
    [string]$ToolRoot='',
    [string]$ToolSha='',
    [Parameter(Mandatory)][ValidateSet('unity-wrapper','unity-gui')][string]$TargetId,
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$CoreToolsRoot,
    [Parameter(Mandatory)][string]$TestRoot,
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$BindingOutputRoot,
    [string]$GuiRoot='',
    [string]$GuiSha='',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',
    [string]$CandidatePath='',
    [switch]$ConformanceOnly
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SelectedProcessIsolation.ps1"
. "$PSScriptRoot/UnityContract.ps1"
. "$PSScriptRoot/UnityTooling.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:WSS_TEST_SELECTION_ID -cnotmatch '^[a-f0-9]{64}$') { throw 'Require actual GitHub identity and trusted prerequisite selection output.' }
$role=if ($TargetId -ceq 'unity-gui') { 'gui' } else { 'wrapper' }
$ownSha=if ($role -ceq 'gui') { $GuiSha } else { $WrapperSha }
$ownRepository=if ($role -ceq 'gui') { $UnityGuiRepository } else { $UnityWrapperRepository }
if ($env:GITHUB_SHA -cne $ownSha -or $env:GITHUB_REPOSITORY -cne $ownRepository) { throw 'Product source differs from actual target run.' }
$tooling=Resolve-UnityTooling $ToolRoot $ToolSha $WrapperRoot $WrapperSha $ConfigPath $TestRoot
$lock=Get-Content (Join-Path $tooling.root '.github/scripts/wss-ci.lock.json') -Raw | ConvertFrom-Json
if ($lock.source_repository -cne 'cwru-non-academic/WSSCore' -or $lock.source_commit -cnotmatch '^[a-f0-9]{40}$' -or $lock.source_ref -cne "refs/heads/ci/tooling/$($lock.source_commit)") { throw 'Invalid immutable Core bootstrap lock.' }
Assert-UnitySource $CoreToolsRoot $lock.source_commit
$bootstrap=Join-Path $CoreToolsRoot 'tools/ci/ci-test-selection.mjs'
if (!(Test-Path -LiteralPath $bootstrap -PathType Leaf)) { throw 'Locked Core does not support test selection; adoption is not enabled.' }
if ((Test-Path -LiteralPath $BindingOutputRoot) -or (Test-Path -LiteralPath $OutputRoot)) { throw 'Suite and binding outputs must be new.' }
$config=Read-UnityConfig $ConfigPath
$products=@(
    @{repository=$UnityWrapperRepository;commit=$WrapperSha;path=[IO.Path]::GetFullPath($WrapperRoot)},
    @{repository='cwru-non-academic/CSharp_WSS_Integration_Lib';commit=$config.fixture_commit;path=[IO.Path]::GetFullPath($FixtureRoot)},
    @{repository='cwru-non-academic/WSSCore';commit=$lock.source_commit;path=[IO.Path]::GetFullPath($CoreToolsRoot)}
)
if ($GuiRoot) { $products+=@{repository=$UnityGuiRepository;commit=$GuiSha;path=[IO.Path]::GetFullPath($GuiRoot)} }
$null=New-Item -ItemType Directory -Path $BindingOutputRoot
$rootsPath=Join-Path $BindingOutputRoot 'roots.json'
@{selection_id=$env:WSS_TEST_SELECTION_ID;test_root=[IO.Path]::GetFullPath($TestRoot);products=$products} | ConvertTo-Json -Depth 8 | Set-Content $rootsPath
$inspection=& node $bootstrap inspect $TargetId $ContextPath $rootsPath
if ($LASTEXITCODE) { throw 'Frozen selected-test checkout inspection failed.' }
$binding=$inspection | ConvertFrom-Json
if ($binding.selection_id -cne $env:WSS_TEST_SELECTION_ID -or $binding.target_id -cne $TargetId) { throw 'Unexpected bootstrap binding.' }
$options=@{ToolRoot=$tooling.root;ToolSha=$tooling.sha;WrapperRoot=$WrapperRoot;WrapperSha=$WrapperSha;GuiRoot=$GuiRoot;GuiSha=$GuiSha;FixtureRoot=$FixtureRoot;ConfigPath=$ConfigPath;OutputRoot=$OutputRoot;Role=$role;Mode=$Mode;ArtifactRoot=$ArtifactRoot;CandidatePath=$CandidatePath;TestRoot=$TestRoot;TestSha=$binding.test_commit;TestRepository=$binding.test_repository;TestSelectionId=$env:WSS_TEST_SELECTION_ID}
# Never obtain a runner or validator from selected source.
$runner=if ($ConformanceOnly) { 'Invoke-DotNetConformance.ps1' } else { 'Invoke-DotNetPlatformCompatibility.ps1' }
# Freeze executable bootstrap and its inputs in parent memory before selected code.
$frozen=New-UnityFrozenSelectionState $CoreToolsRoot $lock.source_commit (Join-Path $tooling.root '.github/scripts/wss-ci.lock.json') $ContextPath $rootsPath
Invoke-UnitySelectedWithMandatoryBaseline (Join-Path $PSScriptRoot $runner) $options (Join-Path $BindingOutputRoot 'mandatory-baseline') -ConformanceOnly:$ConformanceOnly
if (!$?) { throw 'Selected and mandatory suite gates failed.' }
Assert-UnityTooling $tooling $WrapperRoot $WrapperSha $TestRoot
# Never execute a bootstrap or consume frozen inputs changed by selected code.
Assert-UnityFrozenSelectionState $frozen
Assert-UnitySource $frozen.core_root $frozen.core_sha
# Emission rechecks all source identities only after every trusted runner gate passed.
& node $bootstrap evidence $TargetId $ContextPath $rootsPath (Join-Path $BindingOutputRoot 'evidence.json')
if ($LASTEXITCODE) { throw 'Post-test immutable source/evidence validation failed.' }

# Target policy remains independent from the executable tooling's canonical inventory.
. "$PSScriptRoot/UnityTooling.ps1"
function Resolve-UnityPromotionConfig([string]$RepositoryRoot,[ValidateSet('wrapper','gui')][string]$Role,[string]$ToolSha='') {
    $source=(Invoke-UnityGit $RepositoryRoot @('rev-parse','HEAD')).Trim()
    Assert-UnitySource $RepositoryRoot $source -IgnoreSubmodule
    if ($source -cne $env:GITHUB_SHA) { throw 'Promotion checkout differs from trusted workflow source.' }
    $targetRoot=[IO.Path]::GetFullPath($RepositoryRoot)
    if ([IO.Path]::GetFullPath((Invoke-UnityGit $targetRoot @('rev-parse','--show-toplevel')).Trim()) -cne $targetRoot) { throw 'Target must be its exact repository root.' }
    foreach ($path in @($targetRoot,(Join-Path $targetRoot '.github'),(Join-Path $targetRoot '.github/unity-ci.json'),(Join-Path $PSScriptRoot '../unity-ci.json'))) {
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Promotion policy cannot use filesystem links.' }
    }
    $policyEntries=@(Invoke-UnityGit $targetRoot @('ls-files','-v','--','.github/unity-ci.json'))
    if ($policyEntries.Count -ne 1 -or $policyEntries[0] -cne 'H .github/unity-ci.json') { throw 'Target promotion policy cannot hide index modifications or be untracked.' }
    $target=Get-Content -LiteralPath (Join-Path $targetRoot '.github/unity-ci.json') -Raw | ConvertFrom-Json
    $channel=Get-WssCiChannel
    if ($channel -ceq 'main') {
        $workflow=if($Role -ceq 'wrapper'){'promote-wss.yml'}else{'promote-integration.yml'}
        if($env:GITHUB_WORKFLOW_SHA -cne $source -or $env:GITHUB_WORKFLOW_REF -cne "$env:GITHUB_REPOSITORY/.github/workflows/$workflow@refs/heads/main") { throw 'Main promotion must execute its exact registered receiver workflow.' }
    }
    if ($target.schema -cne 'wss-unity-ci/v1' -or $target.branch -cne 'dev' -or
        $target.baseline_ready -isnot [bool] -or !$target.baseline_ready -or
        $target.automated_execution -cne 'dotnet') { throw 'Approved .NET target promotion baseline required.' }
    if (!$target.PSObject.Properties['channels'] -or $channel -cnotin @($target.channels)) { throw 'Target does not authorize this promotion channel.' }
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    if ($Role -ceq 'wrapper') {
        if ($root -cne [IO.Path]::GetFullPath($RepositoryRoot) -or ($ToolSha -and $ToolSha -cne $source)) { throw 'Wrapper promotion must execute its exact target tooling.' }
        $ToolSha=$source
    } elseif (!$ToolSha) { throw 'GUI promotion requires the workflow-pinned executable tooling SHA.' }
    # ToolSha comes only from the reviewed workflow literal, never a dispatch input.
    $tooling=Resolve-UnityTooling $root $ToolSha '' '' (Join-Path $root '.github/unity-ci.json')
    $config=Read-UnityConfig $tooling.config 'layered-v1'
    if ($config.baseline_ready -isnot [bool] -or !$config.baseline_ready -or $config.automated_execution -cne 'dotnet') { throw 'Approved .NET tooling promotion baseline required.' }
    if (!$config.PSObject.Properties['channels'] -or $channel -cnotin @($config.channels)) { throw 'Tooling does not authorize this promotion channel.' }
    if ($config.dotnet_sdk -cne '9.0.316' -or $target.dotnet_sdk -cne $config.dotnet_sdk) { throw 'Target and tooling promotion SDK must match the reviewed runtime.' }
    if ($config.expected_cases.Count -ne 16 -or $config.dotnet_expected_cases.Count -ne 16 -or $config.multidevice_expected_cases.Count -ne 6) { throw 'Promotion requires the complete modern single/multi inventory.' }
    [pscustomobject]@{config=$config;tooling=$tooling}
}

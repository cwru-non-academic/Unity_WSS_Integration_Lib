param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$WorkRoot)
. "$PSScriptRoot/UnityPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne (Get-WssCiChannelContext).ref -or !$env:UNITY_PUSH_TOKEN) { throw 'Publication requires the trusted dev workflow and delayed scoped token.' }
$prepared=Get-Content -LiteralPath (Join-Path $WorkRoot 'prepared.json') -Raw | ConvertFrom-Json
if ($prepared.no_op) { throw 'No-op preparation must not mint a write token or publish.' }
$role=$prepared.role
$repo=if ($role -ceq 'wrapper') { $UnityWrapperRepository } elseif ($role -ceq 'gui') { $UnityGuiRepository } else { throw 'Unexpected promotion role.' }
if ($repo -cne $env:GITHUB_REPOSITORY) { throw 'Wrong publication repository.' }
$config=Read-UnityConfig (Join-Path $RepositoryRoot '.github/unity-ci.json')
if (!$config.baseline_ready -or $config.automated_execution -cne 'dotnet') { throw 'Approved .NET promotion baseline required.' }
$approval=Read-UnityApproval (Join-Path $WorkRoot 'approval.json')
Assert-UnityApproval $approval (Join-Path $WorkRoot 'publication-evidence') $config
Assert-UnitySource $RepositoryRoot $prepared.source_sha -IgnoreSubmodule
if ((Get-UnityHead $repo) -cne $prepared.source_sha) { throw 'Target dev advanced; no stale PR.' }
$branch="automation/unity-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)"
$marker=Get-UnityApprovalMarker $approval
if ($role -ceq 'wrapper') {
    if ($prepared.source_sha -cne $approval.wrapper.source_sha) { throw 'Untested wrapper source.' }
    $projection=Get-Content -LiteralPath (Join-Path $WorkRoot 'projection.json') -Raw | ConvertFrom-Json
    Assert-UnitySameCandidate $projection.candidate $approval.candidate
    Assert-UnityProjection (Join-Path $WorkRoot 'projection') $projection
    if ($projection.projection_sha256 -cne $approval.projection_sha256) { throw 'Staged projection differs from preflight.' }
    foreach ($source in $UnityProjectionFiles) {
        $name=Get-UnityProjectionPath $source
        Copy-Item -LiteralPath (Join-Path $WorkRoot "projection/$name") -Destination (Join-Path $RepositoryRoot "$UnityPluginPath/$name")
        # Importer metadata is part of the proof, but remains the accepted baseline byte-for-byte.
    }
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RepositoryRoot '.github/unity-candidate.json')
    $allowed=Get-UnityAllowedWrapperPaths
    $null=Invoke-UnityGit $RepositoryRoot (@('add','--')+$allowed)
    Assert-UnityProjection (Join-Path $RepositoryRoot $UnityPluginPath) $projection
} else {
    Assert-UnityMergedWrapper $prepared.wrapper_merge_sha $prepared.wrapper_pr $approval
    Assert-UnityMergedGuiPreflight $approval $prepared.wrapper_merge_sha $prepared.source_sha $prepared.gui_preflight_run_id (Join-Path $WorkRoot 'publication-merged-gui-evidence') $config
    $guiMarker=Get-UnityGuiPreflightMarker $prepared.wrapper_merge_sha $prepared.source_sha $prepared.gui_preflight_run_id
    $allowed=@($UnityGitlink)
    $null=Invoke-UnityGit $RepositoryRoot @('update-index','--cacheinfo',"160000,$($prepared.wrapper_merge_sha),$UnityGitlink")
    $entry=(Invoke-UnityGit $RepositoryRoot @('ls-files','--stage','--',$UnityGitlink)) -join ''
    if ($entry -cne "160000 $($prepared.wrapper_merge_sha) 0`t$UnityGitlink") { throw 'Staged GUI entry is not the accepted gitlink.' }
}
# The adapter has verified/staged exact payload or gitlink bytes. One engine publishes.
$bodyPath=Join-Path $WorkRoot 'pr-body.md'
$body="Promotes the exact candidate accepted by reviewed Unity evidence. Manual review/merge required.`n`n$marker`n"
$markers=@($marker)
$parents=@{}; $gitlinks=@{}
if($role -cne 'wrapper') {
    $body+="`n$guiMarker`n"
    $markers+=$guiMarker
    $parents['cwru-non-academic/Unity_WSS_Integration_Lib']=$prepared.wrapper_merge_sha
    $gitlinks[$allowed[0]]=$prepared.wrapper_merge_sha
}
if($role -ceq 'wrapper' -and 'unity' -ceq 'unity'){$body="<!-- wss-unity-promotion:v1 -->`n"+$body}
[IO.File]::WriteAllText($bodyPath,$body)
$descriptor=@{channel=(Get-WssCiChannel);target_id="unity-$role";repository_root=[IO.Path]::GetFullPath($RepositoryRoot);source_sha=$prepared.source_sha;candidate=$approval.candidate;branch=$branch;allowed_paths=@($allowed);markers=$markers;gitlinks=$gitlinks;parent_heads=$parents;body_path=[IO.Path]::GetFullPath($bodyPath);title="Promote verified Unity WSS $($approval.candidate.run_id)";commit_message="Promote verified Unity WSS $($approval.candidate.run_id)"}
$descriptorPath=Join-Path $WorkRoot 'publication.json'
$descriptor|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $descriptorPath
$saved=$env:WSS_PUSH_TOKEN
try {
    $env:WSS_PUSH_TOKEN=$env:UNITY_PUSH_TOKEN
    & node (Join-Path $PSScriptRoot 'wss-ci/promotion.mjs') $descriptorPath
    if($LASTEXITCODE -ne 0){throw 'Common promotion publication failed or is uncertain; inspect before retry.'}
} finally {$env:WSS_PUSH_TOKEN=$saved}

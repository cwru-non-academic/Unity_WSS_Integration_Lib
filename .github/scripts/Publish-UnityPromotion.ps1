param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$WorkRoot)
. "$PSScriptRoot/UnityPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/dev' -or !$env:UNITY_PUSH_TOKEN) { throw 'Publication requires the trusted dev workflow and delayed scoped token.' }
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
        $name=[IO.Path]::GetFileName($source)
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
$changed=@(Invoke-UnityGit $RepositoryRoot @('diff','--cached','--name-only'))
Assert-UnityDiff $changed $allowed
if (@(Invoke-UnityGit $RepositoryRoot @('diff','--name-only','--ignore-submodules=all')).Count -ne 0) { throw 'Unstaged changes outside the intended promotion.' }
$tree=(Invoke-UnityGit $RepositoryRoot @('write-tree')).Trim()
$pulls=@(Invoke-UnityGh @('pr','list','--repo',$repo,'--state','all','--base','dev','--head',$branch,'--limit','2','--json','number,url,state,body,headRefOid') | ConvertFrom-Json)
if ($pulls.Count -gt 1 -or ($pulls.Count -eq 1 -and $pulls[0].state -cne 'OPEN')) { throw 'Ambiguous or already closed/merged candidate PR; no replacement or rollback.' }
$refs=@(Invoke-UnityGh @('api',"repos/$repo/git/matching-refs/heads/$branch") | ConvertFrom-Json | Where-Object { $_.ref -ceq "refs/heads/$branch" })
if ($pulls.Count -eq 1) {
    if ($refs.Count -ne 1 -or $pulls[0].headRefOid -cne $refs[0].object.sha -or !(($pulls[0].body -split "`r?`n") -ccontains $marker)) { throw 'Existing PR branch/metadata conflict.' }
    if ($role -ceq 'gui' -and !(($pulls[0].body -split "`r?`n") -ccontains $guiMarker)) { throw 'Existing GUI PR does not carry the exact merged-wrapper preflight.' }
    $remoteCommit=Invoke-UnityGh @('api',"repos/$repo/git/commits/$($refs[0].object.sha)") | ConvertFrom-Json
    if ($remoteCommit.tree.sha -cne $tree -or @($remoteCommit.parents).Count -ne 1 -or $remoteCommit.parents[0].sha -cne $prepared.source_sha) { throw 'Existing PR is not the exact intended tree/source.' }
    Write-Output "Reusing exact existing PR: $($pulls[0].url)"
    exit 0
}
if ($refs.Count -ne 0) { throw 'Orphan candidate branch exists; inspect rather than overwriting.' }
$null=Invoke-UnityGit $RepositoryRoot @('switch','-c',$branch)
$null=Invoke-UnityGit $RepositoryRoot @('-c','user.name=WSS Unity automation','-c','user.email=wss-unity-automation@users.noreply.github.com','commit','-m',"Promote verified Unity WSS $($approval.candidate.run_id)")
# Per-command credentials only; never alter Git global/system trust or credential configuration.
$header=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('x-access-token:'+$env:UNITY_PUSH_TOKEN))
Write-Output "::add-mask::$header"
$null=Invoke-UnityGit $RepositoryRoot @('-c',"http.https://github.com/.extraheader=AUTHORIZATION: basic $header",'push','origin',"HEAD:refs/heads/$branch")
$bodyPath=Join-Path $WorkRoot 'pr-body.md'
$body="Promotes the exact candidate accepted by both .NET preflights in the Unity repositories. Manual review/merge required; no player release.`n`n<!-- wss-unity-promotion:v1 -->`n$marker`n"
if ($role -ceq 'gui') { $body+="`nActual merged-wrapper GUI preflight: https://github.com/$UnityGuiRepository/actions/runs/$($prepared.gui_preflight_run_id)`n$guiMarker`n" }
[IO.File]::WriteAllText($bodyPath,$body)
$readToken=$env:GH_TOKEN
try {
    $env:GH_TOKEN=$env:UNITY_PUSH_TOKEN
    $null=Invoke-UnityGh @('pr','create','--repo',$repo,'--base','dev','--head',$branch,'--title',"Promote Unity WSS $($approval.candidate.run_id)",'--body-file',$bodyPath)
} finally { $env:GH_TOKEN=$readToken }

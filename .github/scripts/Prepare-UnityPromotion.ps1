param(
    [Parameter(Mandatory)][ValidateSet('wrapper','gui')][string]$Role,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string]$CandidateJson='',
    [string]$ApprovalJson='',
    [string]$WrapperMergeSha='',
    [string]$WrapperPr=''
)
. "$PSScriptRoot/UnityPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REF -cne 'refs/heads/dev') { throw 'Promotion preparation runs only in the trusted dev workflow.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'WorkRoot must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$config=Read-UnityConfig (Join-Path $RepositoryRoot '.github/unity-ci.json')
$source=(Invoke-UnityGit $RepositoryRoot @('rev-parse','HEAD')).Trim()
Assert-UnitySource $RepositoryRoot $source -IgnoreSubmodule
if ($source -cne $env:GITHUB_SHA) { throw 'Promotion checkout differs from trusted workflow source.' }
if ($Role -ceq 'wrapper') {
    if ($env:GITHUB_REPOSITORY -cne $UnityWrapperRepository -or !$CandidateJson -or $ApprovalJson) { throw 'Invalid wrapper promotion inputs/repository.' }
    $candidate=$CandidateJson | ConvertFrom-Json
    Assert-UnityProducer $candidate
    & "$PSScriptRoot/Resolve-WssRelease.ps1" -RunId $candidate.run_id -ExpectedArtifactId $candidate.artifact_id -ExpectedCommit $candidate.commit -ArchiveName $candidate.archive -ExpectedSha256 $candidate.sha256 -OutputRoot (Join-Path $WorkRoot 'resolved')
    $resolved=Get-Content -LiteralPath (Join-Path $WorkRoot 'resolved/candidate.json') -Raw | ConvertFrom-Json
    Assert-UnitySameCandidate $resolved $candidate
    $projection=New-UnityProjection (Join-Path $WorkRoot 'resolved/extracted/WSS-Universal') $RepositoryRoot (Join-Path $WorkRoot 'projection') $candidate
    $current=Get-Content -LiteralPath (Join-Path $RepositoryRoot '.github/unity-candidate.json') -Raw | ConvertFrom-Json
    Assert-UnityProjection (Join-Path $RepositoryRoot $UnityPluginPath) $current
    if ($current.projection_sha256 -ceq $projection.projection_sha256) {
        @{no_op=$true;role=$Role;source_sha=$source} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
        'no_op=true' >> $env:GITHUB_OUTPUT
        Write-Output 'Verified identical payload: preserve committed provenance; no artificial PR.'
        exit 0
    }
    $guiSha=Get-UnityHead $UnityGuiRepository
    if ((Get-UnityHead $UnityWrapperRepository) -cne $source) { throw 'Wrapper dev advanced before preflight.' }
    $wrapperRun=Start-UnityPreflight $UnityWrapperRepository $candidate $source $guiSha
    $guiRun=Start-UnityPreflight $UnityGuiRepository $candidate $source $guiSha
    $approval=[ordered]@{
        schema='wss-unity-promotion/v1'; candidate=$candidate
        wrapper=@{source_sha=$source;preflight_run_id=[string]$wrapperRun.id}
        gui=@{source_sha=$guiSha;preflight_run_id=[string]$guiRun.id}
        fixture=@{commit=$config.fixture_commit;sha256=$config.fixture_sha256}
        projection_sha256=$projection.projection_sha256
    }
    $approval | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $WorkRoot 'approval.json')
    $approval=Read-UnityApproval (Join-Path $WorkRoot 'approval.json')
    Assert-UnityApproval $approval (Join-Path $WorkRoot 'evidence') $config
    $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $WorkRoot 'projection.json')
} else {
    if ($env:GITHUB_REPOSITORY -cne $UnityGuiRepository -or !$ApprovalJson -or $CandidateJson) { throw 'Invalid GUI promotion inputs/repository.' }
    [IO.File]::WriteAllText((Join-Path $WorkRoot 'approval.json'),$ApprovalJson)
    $approval=Read-UnityApproval (Join-Path $WorkRoot 'approval.json')
    $candidate=$approval.candidate
    Assert-UnityApproval $approval (Join-Path $WorkRoot 'evidence') $config
    Assert-UnityMergedWrapper $WrapperMergeSha $WrapperPr $approval
    $entry=(Invoke-UnityGit $RepositoryRoot @('ls-tree','HEAD','--',$UnityGitlink)) -join ''
    if ($entry -ceq "160000 commit $WrapperMergeSha`t$UnityGitlink") {
        @{no_op=$true;role=$Role;source_sha=$source} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
        'no_op=true' >> $env:GITHUB_OUTPUT
        Write-Output 'Verified existing accepted gitlink; no PR.'
        exit 0
    }
    if ($source -cne $approval.gui.source_sha) { throw 'GUI source advanced since preflight; revalidation is required.' }
}
@{no_op=$false;role=$Role;source_sha=$source;wrapper_merge_sha=$WrapperMergeSha;wrapper_pr=$WrapperPr} | ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'prepared.json')
'no_op=false' >> $env:GITHUB_OUTPUT

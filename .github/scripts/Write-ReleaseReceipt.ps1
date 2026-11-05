param(
    [Parameter(Mandatory)][ValidateSet('unity-wrapper','unity-gui')][string] $TargetId,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]*$')][string] $ProducerRunId,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string] $PlanId,
    [string] $ToolsRoot = '.tools',
    [string] $ValidatorRoot = '.validation-tools',
    [string] $AcceptedRoot = '.accepted',
    [string] $IntegrationRoot = '.integration',
    [string] $OutputRoot = 'receipt-output'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-ReceiptGh([string[]] $Arguments) {
    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub evidence request failed: $($Arguments[0])" }
    $result
}
function Api([string] $Path) { Invoke-ReceiptGh -Arguments @('api',$Path) | ConvertFrom-Json }
function Pages([string] $Path, [string] $Key = '') {
    $pages = Invoke-ReceiptGh -Arguments @('api','--paginate','--slurp',$Path) | ConvertFrom-Json
    if ($Key) { @($pages | ForEach-Object { $_.$Key }) } else { @($pages | ForEach-Object { $_ }) }
}
function Invoke-ReceiptGit([string] $Root,[string[]] $Arguments) {
    $result = & git -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Git evidence request failed.' }
    $result
}
function Download([string] $Repository,[string] $Run,[string] $Name,[string] $Directory,[string] $File) {
    $a = @(Pages "repos/$Repository/actions/runs/$Run/artifacts?per_page=100" 'artifacts' | Where-Object name -CEQ $Name)
    if ($a.Count -ne 1 -or $a[0].expired -or [string]$a[0].workflow_run.id -cne $Run) { throw 'Missing/ambiguous/expired evidence artifact.' }
    $null = Invoke-ReceiptGh -Arguments @('run','download',$Run,'--repo',$Repository,'--name',$Name,'--dir',$Directory)
    $files = @(Get-ChildItem -LiteralPath $Directory -Force)
    if ($files.Count -ne 1 -or $files[0].PSIsContainer -or $files[0].Name -cne $File) { throw 'Unexpected evidence artifact inventory.' }
    Get-Content -LiteralPath (Join-Path $Directory $File) -Raw | ConvertFrom-Json
}
function MergedPr([string] $Repository,[string] $Sha) {
    $matches = @(Pages "repos/$Repository/commits/$Sha/pulls?per_page=100" | Where-Object {
        $_.merged_at -and $_.merge_commit_sha -ceq $Sha -and $_.base.ref -ceq 'dev' -and
        $_.base.repo.full_name -ceq $Repository -and $_.head.repo.full_name -ceq $Repository
    })
    if ($matches.Count -ne 1) { throw 'Current dev must be the actual unique merged dependency PR.' }
    $pr = Api "repos/$Repository/pulls/$($matches[0].number)"
    Assert-WssReceiptPr $pr $Repository $Sha
    $pr
}

$core='cwru-non-academic/WSSCore'
$wrapper='cwru-non-academic/Unity_WSS_Integration_Lib'
$gui='cwru-non-academic/GUI_Unity_WSS_Application'
$repository=if ($TargetId -ceq 'unity-wrapper') { $wrapper } else { $gui }
if ($env:GITHUB_REPOSITORY -cne $repository -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/dev') { throw 'Receipt emitter is restricted to its canonical dev dispatch.' }
$work=Join-Path $env:RUNNER_TEMP ('unity-receipt-'+[IO.Path]::GetRandomFileName())
$null=New-Item -ItemType Directory -Path $work
$producer=Api "repos/$core/actions/runs/$ProducerRunId"
if ($producer.repository.full_name -cne $core -or $producer.head_repository.full_name -cne $core -or $producer.path -cne '.github/workflows/artifacts.yml' -or $producer.event -cne 'push' -or $producer.head_branch -cne 'dev' -or $producer.status -cne 'completed' -or $producer.conclusion -cne 'success') { throw 'Plan is not from a successful canonical dev push.' }
$plan=Download $core $ProducerRunId 'wss-propagation-plan' (Join-Path $work 'plan') 'plan.json'
if ($plan.schema -cne 'wss-propagation-plan/v1' -or $plan.channel -cne 'dev' -or $plan.plan_id -cne $PlanId -or $plan.candidate.run_id -cne $ProducerRunId -or $plan.candidate.commit -cne $producer.head_sha) { throw 'Plan/input/producer mismatch.' }
& node (Join-Path $ToolsRoot '.github/scripts/wss-ci/verify-plan.mjs') (Join-Path $work 'plan/plan.json')
if ($LASTEXITCODE -ne 0) { throw 'Frozen plan/schema/manifest validation failed.' }
$target=@($plan.manifest.targets | Where-Object id -CEQ $TargetId)
if ($target.Count -ne 1 -or $target[0].repository -cne $repository -or $target[0].branch -cne 'dev') { throw 'Required target policy mismatch.' }
$target=$target[0]
foreach ($path in $target.trusted_paths) {
    if ((Invoke-ReceiptGit $AcceptedRoot -Arguments @('rev-parse',"HEAD:$path")) -cne $plan.target_snapshots.$TargetId.trusted.$path) { throw "Accepted receiver tooling differs: $path" }
}
foreach ($path in @('.github/scripts','.github/workflows/release-receipt.yml')) {
    if ((Invoke-ReceiptGit $ToolsRoot -Arguments @('rev-parse',"HEAD:$path")) -cne $plan.target_snapshots.$TargetId.trusted.$path) { throw "Trusted main receipt tooling differs: $path" }
}
if ((Invoke-ReceiptGit $ValidatorRoot -Arguments @('rev-parse','HEAD:.github/scripts')) -cne $plan.target_snapshots.'unity-wrapper'.trusted.'.github/scripts') { throw 'Unity validators differ from frozen tooling.' }
if ((Invoke-ReceiptGit $ValidatorRoot -Arguments @('rev-parse','HEAD:.github/unity-ci.json')) -cne $plan.target_snapshots.'unity-wrapper'.trusted.'.github/unity-ci.json') { throw 'Unity execution configuration differs from frozen tooling.' }
. (Join-Path $ValidatorRoot '.github/scripts/UnityPromotion.ps1')
. (Join-Path $ToolsRoot '.github/scripts/WssReleaseReceipt.ps1')
$acceptedSha=(Invoke-ReceiptGit $AcceptedRoot -Arguments @('rev-parse','HEAD')).Trim()
if ($acceptedSha -cne (Api "repos/$repository/git/ref/heads/dev").object.sha -or $acceptedSha -cne $env:GITHUB_SHA) { throw 'Accepted checkout/emitter/current dev differ.' }
$pr=MergedPr $repository $acceptedSha
$approval=Read-UnityApprovalMarker ([string]$pr.body) (Join-Path $work 'approval.json')
Assert-UnitySameCandidate $plan.candidate $approval.candidate
$files=@(Pages "repos/$repository/pulls/$($pr.number)/files?per_page=100")
Assert-WssReceiptChangedFiles $TargetId $files
if ($pr.head.ref -cne "automation/unity-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)") { throw 'Receipt PR is not the canonical candidate branch.' }
$commit=Api "repos/$repository/git/commits/$($pr.head.sha)"
$expectedSource=if ($TargetId -ceq 'unity-wrapper') { $approval.wrapper.source_sha } else { $approval.gui.source_sha }
if (@($commit.parents).Count -ne 1 -or $commit.parents[0].sha -cne $expectedSource) { throw 'Dependency PR did not originate at the exact preflight source.' }
$config=Read-UnityConfig (Join-Path $ValidatorRoot '.github/unity-ci.json')
if (!$config.baseline_ready -or $config.automated_execution -cne 'dotnet') { throw 'Approved .NET receiver baseline required.' }
Assert-UnityApproval $approval (Join-Path $work 'paired-preflights') $config
$parents=@{}
$preflights=@(
    @{repository=$wrapper;run_id=$approval.wrapper.preflight_run_id;source_sha=$approval.wrapper.source_sha;workflow='.github/workflows/wss-preflight.yml'},
    @{repository=$gui;run_id=$approval.gui.preflight_run_id;source_sha=$approval.gui.source_sha;workflow='.github/workflows/wss-preflight.yml'}
)
if ($TargetId -ceq 'unity-wrapper') {
    $IntegrationRoot=$AcceptedRoot
    $wrapperSha=$acceptedSha
    $wrapperPr=$pr
} else {
    $wrapperSha=(Invoke-ReceiptGit $IntegrationRoot -Arguments @('rev-parse','HEAD')).Trim()
    if ($wrapperSha -cne (Api "repos/$wrapper/git/ref/heads/dev").object.sha -or (Invoke-ReceiptGit $AcceptedRoot -Arguments @('rev-parse',"HEAD:$UnityGitlink")).Trim() -cne $wrapperSha) { throw 'GUI pin differs from actual current wrapper.' }
    $wrapperPr=MergedPr $wrapper $wrapperSha
    # The GUI proof must use the same canonical approval as the reviewed wrapper.
    if (!(($wrapperPr.body -split "`r?`n") -ccontains (Get-UnityApprovalMarker $approval))) { throw 'GUI/wrapper candidate approvals differ.' }
    $matches=[regex]::Matches([string]$pr.body,'(?m)^<!-- wss-unity-gui-preflight:v1 ([A-Za-z0-9+/=]+) -->\r?$')
    if ($matches.Count -ne 1 -or [regex]::Matches([string]$pr.body,'<!-- wss-unity-gui-preflight:').Count -ne 1) { throw 'Unique merged-wrapper GUI preflight marker required.' }
    $proof=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($matches[0].Groups[1].Value)) | ConvertFrom-Json
    if ($proof.gui_sha -cne $approval.gui.source_sha -or $proof.wrapper_sha -cne $wrapperSha -or
        (Get-UnityGuiPreflightMarker $wrapperSha $proof.gui_sha ([string]$proof.preflight_run_id)) -cne $matches[0].Value.TrimEnd("`r")) { throw 'Merged GUI preflight identity/marker mismatch.' }
    Assert-UnityMergedGuiPreflight $approval $wrapperSha $proof.gui_sha ([string]$proof.preflight_run_id) (Join-Path $work 'merged-gui-preflight') $config
    $preflights+=@{repository=$gui;run_id=[string]$proof.preflight_run_id;source_sha=$proof.gui_sha;workflow='.github/workflows/wss-preflight.yml'}
    $parents['unity-wrapper']=$wrapperSha
}
Assert-UnityMergedWrapper $wrapperSha ([string]$wrapperPr.number) $approval
Assert-UnityDiff @($files.filename) $(if ($TargetId -ceq 'unity-wrapper') { Get-UnityAllowedWrapperPaths } else { @($UnityGitlink) })
$workflow=Split-Path $target.workflow -Leaf
$runs=@(Pages "repos/$repository/actions/workflows/$workflow/runs?head_sha=$acceptedSha&per_page=100" 'workflow_runs' | Where-Object { $_.event -cin @('push','workflow_dispatch') } | Sort-Object { [long]$_.id } -Descending)
if ($runs.Count -eq 0) { throw 'Fresh exact-merge normal CI has not run yet.' }
@{runs=@($runs);target=$target;head=$acceptedSha;merged_at=$pr.merged_at} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $work 'normal-ci.json')
$normalJson = & node (Join-Path $ToolsRoot '.github/scripts/wss-ci/normal-ci-select.mjs') (Join-Path $work 'normal-ci.json')
if ($LASTEXITCODE -ne 0) { throw 'Normal CI identity/ambiguity validation failed.' }
$normal = $normalJson | ConvertFrom-Json
$jobs=@(Pages "repos/$repository/actions/runs/$($normal.id)/attempts/$($normal.run_attempt)/jobs?per_page=100" 'jobs')
Assert-WssReceiptNormalRun $normal $repository $target $acceptedSha $jobs
if ([DateTimeOffset]::Parse($normal.created_at) -lt [DateTimeOffset]::Parse($pr.merged_at)) { throw 'Normal CI predates the accepted merge.' }
foreach ($proof in $preflights) {
    $candidate=Download $proof.repository $proof.run_id 'wss-candidate-provenance' (Join-Path $work ('normalized-'+$proof.run_id)) 'candidate.json'
    Assert-UnitySameCandidate $candidate $plan.candidate
}
if ($acceptedSha -cne (Api "repos/$repository/git/ref/heads/dev").object.sha -or $wrapperSha -cne (Api "repos/$wrapper/git/ref/heads/dev").object.sha) { throw 'Accepted source moved during receipt validation.' }
if (@($target.coverage | Where-Object { $_ -cin @('canonical-conformance','packaged-macos-ble-load','dotnet-harness-not-unity-editor') }).Count -ne 3 -or @($target.coverage).Count -ne 3) { throw 'Unexpected Unity coverage claims.' }
$receipt=[ordered]@{
    schema='wss-acceptance-receipt/v1';plan_id=$PlanId;channel='dev';target_id=$TargetId;candidate=$plan.candidate;mode='merged-pr'
    merge=@{pr_number=[string]$pr.number;head_sha=$pr.head.sha;sha=$acceptedSha}
    normal_ci=@{run_id=[string]$normal.id;attempt=[int]$normal.run_attempt}
    preflights=$preflights;parents=$parents
    emitter=@{run_id=$env:GITHUB_RUN_ID;attempt=[int]$env:GITHUB_RUN_ATTEMPT;source_sha=$acceptedSha;workflow='.github/workflows/release-receipt.yml'}
    coverage=@($target.coverage)
}
$null=New-Item -ItemType Directory -Path $OutputRoot
$receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputRoot 'receipt.json') -Encoding utf8
"artifact_name=wss-acceptance-$TargetId-$PlanId-a$env:GITHUB_RUN_ATTEMPT" >> $env:GITHUB_OUTPUT


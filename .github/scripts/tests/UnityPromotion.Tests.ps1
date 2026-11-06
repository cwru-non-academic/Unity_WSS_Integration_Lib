$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/../UnityPromotion.ps1"
$count=0
function Copy-Value($Value) { $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json }
function Reject([scriptblock]$Action,[string]$Message) {
    try { & $Action; throw "Expected rejection: $Message" }
    catch { if ($_.Exception.Message -notlike $Message) { throw }; $script:count++ }
}
$pr=[pscustomobject]@{head=@{sha='1'*40;ref='automation/unity-wss-test'}}
$normal=[pscustomobject]@{id=10;repository=@{full_name=$UnityWrapperRepository};head_repository=@{full_name=$UnityWrapperRepository};
    path='.github/workflows/unity-compatibility.yml';event='pull_request';head_sha=$pr.head.sha;head_branch=$pr.head.ref;
    pull_requests=@();status='completed';conclusion='success'}
foreach ($associations in @(@(),@(@{number=7}))) {
    $run=Copy-Value $normal; $run.pull_requests=@($associations)
    if ((Get-UnityReviewedPrRun @($run) $pr '7').id -ne 10) { throw 'Exact reviewed run not selected.' }; $count++
}
foreach ($field in @('repository','head_repository','path','event','head_sha','head_branch','pull_requests')) {
    $run=Copy-Value $normal
    if ($field -in @('repository','head_repository')) { $run.$field.full_name='other/repo' }
    elseif ($field -ceq 'pull_requests') { $run.pull_requests=@(@{number=8}) }
    else { $run.$field='wrong' }
    Reject { Get-UnityReviewedPrRun @($run) $pr '7' } 'Latest final-head*'
}
$run=Copy-Value $normal;$run.pull_requests=@(@{number=7},@{number=8})
Reject { Get-UnityReviewedPrRun @($run) $pr '7' } 'Latest final-head*'
foreach ($result in @('failure','cancelled','timed_out','skipped','neutral','action_required')) {
    $run=Copy-Value $normal;$run.id=11;$run.conclusion=$result
    Reject { Get-UnityReviewedPrRun @($normal,$run) $pr '7' } 'Latest final-head*'
}
$run=Copy-Value $normal;$run.id=11;$run.status='in_progress'
Reject { Get-UnityReviewedPrRun @($normal,$run) $pr '7' } 'Latest final-head*'
$jobs=@('Integration behavioral tests','Integration compatibility (Windows)','Integration compatibility (Ubuntu)','Integration compatibility (macOS)') | ForEach-Object { [pscustomobject]@{name=$_;conclusion='success'} }
Assert-UnityRequiredWrapperJobs $jobs;$count++
for ($i=0;$i -lt $jobs.Count;$i++) {
    $bad=@(Copy-Value $jobs);$bad[$i].conclusion='skipped'
    Reject { Assert-UnityRequiredWrapperJobs $bad } 'Normal committed-state*'
    $missing=@($jobs | Where-Object name -CNE $jobs[$i].name)
    Reject { Assert-UnityRequiredWrapperJobs $missing } 'Normal committed-state*'
}
Reject { Assert-UnityRequiredWrapperJobs @($jobs+$jobs[0]) } 'Normal committed-state*'

# Mock only the GitHub boundary; production selectors/source checks/send guard run unchanged.
$approval=[pscustomobject]@{candidate=@{run_id='100';artifact_id='200'};gui=@{source_sha='2'*40}}
$wrapper='3'*40
$prior=[pscustomobject]@{id=50;repository=@{full_name=$UnityGuiRepository};head_repository=@{full_name=$UnityGuiRepository};
    path='.github/workflows/promote-integration.yml';event='workflow_dispatch';head_sha=$approval.gui.source_sha;head_branch='dev';
    display_title="Promote Integration $wrapper / wss-100-200";status='completed';conclusion='success'}
$script:listed=@();$script:detail=$prior;$script:wrapperHead=$wrapper;$script:guiHead=$approval.gui.source_sha
$script:posts=0;$script:uncertain=$false
$script:intents=@()
function Invoke-UnityGh([string[]]$Arguments) {
    if ($Arguments -contains 'POST') {
        if ($env:GH_TOKEN -cne 'write-test') { throw 'POST used wrong token.' }
        $script:posts++;if ($script:uncertain) { throw 'Simulated uncertain POST outcome.' };return '{}'
    }
    if ($env:GH_TOKEN -cne 'read-test') { throw 'Read used wrong token.' }
    $path=$Arguments[-1]
    if ($path -like '*/git/ref/heads/dev') {
        $sha=if ($path -clike "repos/$UnityWrapperRepository/*") { $script:wrapperHead } else { $script:guiHead }
        return (@{object=@{sha=$sha}} | ConvertTo-Json)
    }
    if ($path -like '*/workflows/promote-integration.yml/runs?*') { return (ConvertTo-Json -InputObject @(@{workflow_runs=@($script:listed)}) -Depth 20) }
    if ($path -like '*/actions/runs/*') { return ($script:detail | ConvertTo-Json -Depth 20) }
    if ($path -like '*/actions/artifacts?*') { return (ConvertTo-Json -InputObject @(@{artifacts=@($script:intents)}) -Depth 20) }
    throw "Unexpected test API path: $path"
}
$original=$env:GH_TOKEN
$originalRun=$env:GITHUB_RUN_ID;$originalAttempt=$env:GITHUB_RUN_ATTEMPT;$originalSha=$env:GITHUB_SHA
$temp=Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
try {
    $env:GH_TOKEN='read-test'
    $env:GITHUB_RUN_ID='900';$env:GITHUB_RUN_ATTEMPT='1';$env:GITHUB_SHA='5'*40
    Assert-UnityUnchangedFanoutBarrier $wrapper $wrapper;$count++
    Reject { Assert-UnityUnchangedFanoutBarrier $wrapper ('4'*40) } 'Shared barrier integration changed*'
    Reject { Assert-UnityUnchangedFanoutBarrier $wrapper 'invalid' } 'A full lowercase source SHA is required*'
    $intent=[pscustomobject]@{name="unity-gui-dispatch-$wrapper";expired=$false;workflow_run=@{id=900;head_sha=$env:GITHUB_SHA}}
    Assert-UnityFanoutSources $wrapper $approval.gui.source_sha;$count++
    $script:wrapperHead='4'*40;Reject { Assert-UnityFanoutSources $wrapper $approval.gui.source_sha } 'Fanout source moved*';$script:wrapperHead=$wrapper
    $script:guiHead='4'*40;Reject { Assert-UnityFanoutSources $wrapper $approval.gui.source_sha } 'Fanout source moved*';$script:guiHead=$approval.gui.source_sha
    if (Get-UnityGuiDispatchReuse $approval $wrapper) { throw 'Absent dispatch was reused.' };$count++
    $script:listed=@($prior)
    if (!(Get-UnityGuiDispatchReuse $approval $wrapper)) { throw 'Exact successful run was not reused.' };$count++
    foreach ($field in @('id','repository','head_repository','path','event','head_sha','head_branch','display_title')) {
        $script:detail=Copy-Value $prior
        if ($field -in @('repository','head_repository')) { $script:detail.$field.full_name='other/repo' }
        elseif ($field -ceq 'id') { $script:detail.id=51 }
        else { $script:detail.$field='wrong' }
        Reject { Get-UnityGuiDispatchReuse $approval $wrapper } 'Common application dispatch proof failed*'
    }
    foreach ($result in @('failure','cancelled','timed_out','skipped','neutral','action_required')) {
        $script:detail=Copy-Value $prior;$script:detail.conclusion=$result
        Reject { Get-UnityGuiDispatchReuse $approval $wrapper } 'Common application dispatch proof failed*'
    }
    $script:detail=Copy-Value $prior;$script:detail.status='in_progress'
    Reject { Get-UnityGuiDispatchReuse $approval $wrapper } 'Common application dispatch proof failed*'
    $script:listed=@($prior,$prior)
    Reject { Get-UnityGuiDispatchReuse $approval $wrapper } 'Common application dispatch proof failed*'
    $script:listed=@();$script:detail=$prior
    Assert-UnityGuiDispatchIntent $wrapper;$count++
    Reject { Assert-UnityGuiDispatchIntent $wrapper -RequireCurrent } 'Common application dispatch proof failed*'
    $script:intents=@($intent)
    Assert-UnityGuiDispatchIntent $wrapper -RequireCurrent;$count++
    foreach ($kind in @('prior','expired','wrong-head','duplicate','rerun')) {
        $bad=Copy-Value $intent
        if ($kind -ceq 'prior') { $bad.workflow_run.id=899 }
        if ($kind -ceq 'expired') { $bad.expired=$true }
        if ($kind -ceq 'wrong-head') { $bad.workflow_run.head_sha='6'*40 }
        $script:intents=@($bad)
        if ($kind -ceq 'duplicate') { $script:intents=@($intent,$intent) }
        if ($kind -ceq 'rerun') { $env:GITHUB_RUN_ATTEMPT='2' }
        Reject { Assert-UnityGuiDispatchIntent $wrapper -RequireCurrent } '*inspect*'
        $env:GITHUB_RUN_ATTEMPT='1'
    }
    $script:intents=@($intent)
    @{ref='dev';inputs=@{wrapper_sha=$wrapper;approval_json=($approval | ConvertTo-Json -Depth 10 -Compress)}} | ConvertTo-Json -Depth 15 | Set-Content $temp
    # A source change after initial validation must prevent the eventual write.
    Assert-UnityFanoutSources $wrapper $approval.gui.source_sha
    $script:guiHead='4'*40
    Reject { Send-UnityGuiDispatch $temp 'read-test' 'write-test' } 'Fanout source moved*'
    if ($script:posts -ne 0) { throw 'Source race caused POST.' }
    $script:guiHead=$approval.gui.source_sha;$script:listed=@($prior)
    Send-UnityGuiDispatch $temp 'read-test' 'write-test'
    if ($script:posts -ne 0) { throw 'Successful prior dispatch was duplicated.' };$count++
    $script:detail=Copy-Value $prior;$script:detail.conclusion='failure'
    Reject { Send-UnityGuiDispatch $temp 'read-test' 'write-test' } 'Common application dispatch proof failed*'
    if ($script:posts -ne 0) { throw 'Failed prior dispatch was duplicated.' }
    $script:listed=@();$script:uncertain=$true
    Reject { Send-UnityGuiDispatch $temp 'read-test' 'write-test' } 'GUI dispatch failed or uncertain*'
    if ($script:posts -ne 1 -or $env:GH_TOKEN -cne 'read-test') { throw 'Uncertain dispatch retried or leaked write token.' };$count++
    # A new run cannot replay an uncertain POST even when no application run is visible.
    $env:GITHUB_RUN_ID='901'
    Reject { Send-UnityGuiDispatch $temp 'read-test' 'write-test' } 'Common application dispatch proof failed*'
    if ($script:posts -ne 1) { throw 'Uncertain cross-run dispatch duplicated.' };$count++
    # Independent fresh successful-send fixture.
    $script:uncertain=$false;$script:intents[0].workflow_run.id=901
    Send-UnityGuiDispatch $temp 'read-test' 'write-test'
    if ($script:posts -ne 2 -or $env:GH_TOKEN -cne 'read-test') { throw 'Single dispatch/token restoration failed.' };$count++
    Write-Output "PASS: $count Unity promotion contract checks; metadata-only GitHub fakes, no real dispatch or hardware."
} finally {
    $env:GH_TOKEN=$original
    $env:GITHUB_RUN_ID=$originalRun;$env:GITHUB_RUN_ATTEMPT=$originalAttempt;$env:GITHUB_SHA=$originalSha
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
}

$global:LASTEXITCODE=0 # Expected common recovery rejection fixtures completed.

param([Parameter(Mandatory)][string]$EventPath,[Parameter(Mandatory)][string]$WorkRoot,[switch]$ValidateOnly)
. "$PSScriptRoot/UnityPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $UnityWrapperRepository) { throw 'Trusted wrapper dispatcher required.' }
$event=Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
$pr=$event.pull_request
if (!$pr.merged -or $pr.base.ref -cne 'dev' -or $pr.head.repo.full_name -cne $UnityWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/unity-wss-*') { throw 'Not a reviewed Unity dependency promotion.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Dispatcher workspace must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
$approval=Read-UnityApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
if ($pr.head.ref -cne "automation/unity-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)") { throw 'Promotion branch/candidate mismatch.' }
$config=Read-UnityConfig "$PSScriptRoot/../unity-ci.json"
Assert-UnityApproval $approval (Join-Path $WorkRoot 'evidence') $config
Assert-UnityMergedWrapper $pr.merge_commit_sha ([string]$pr.number) $approval
$body=@{ref='dev';inputs=@{wrapper_sha=$pr.merge_commit_sha;wrapper_pr=[string]$pr.number;approval_json=($approval | ConvertTo-Json -Depth 8 -Compress)}} | ConvertTo-Json -Depth 6 -Compress
$pages=Invoke-UnityGh @('api','--paginate','--slurp',"repos/$UnityGuiRepository/actions/workflows/promote-integration.yml/runs?event=workflow_dispatch&per_page=100") | ConvertFrom-Json
$existing=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { $_.display_title -ceq "Promote Integration $($pr.merge_commit_sha) / wss-$($approval.candidate.run_id)-$($approval.candidate.artifact_id)" })
if ($existing.Count -gt 1) { throw 'Ambiguous prior GUI dispatch; inspect manually.' }
if ($existing.Count -eq 1) { 'dispatch_needed=false' >> $env:GITHUB_OUTPUT; Write-Output 'Prior correlated GUI promotion exists; no redispatch.'; exit 0 }
[IO.File]::WriteAllText((Join-Path $WorkRoot 'gui-dispatch.json'),$body)
'dispatch_needed=true' >> $env:GITHUB_OUTPUT
if ($ValidateOnly) { exit 0 }
if (!$env:UNITY_DISPATCH_TOKEN) { throw 'Scoped GUI Actions-write token required after validation.' }
$readToken=$env:GH_TOKEN
try {
    $env:GH_TOKEN=$env:UNITY_DISPATCH_TOKEN
    $body | & gh api --method POST "repos/$UnityGuiRepository/actions/workflows/promote-integration.yml/dispatches" --input -
    if ($LASTEXITCODE -ne 0) { throw 'GUI dispatch failed/uncertain; inspect before retrying.' }
} finally { $env:GH_TOKEN=$readToken }

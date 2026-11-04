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
if (!$config.baseline_ready -or $config.automated_execution -cne 'dotnet') { throw 'Approved .NET promotion baseline required.' }
Assert-UnityApproval $approval (Join-Path $WorkRoot 'evidence') $config
Assert-UnityMergedWrapper $pr.merge_commit_sha ([string]$pr.number) $approval
$body=@{ref='dev';inputs=@{wrapper_sha=$pr.merge_commit_sha;wrapper_pr=[string]$pr.number;approval_json=($approval | ConvertTo-Json -Depth 8 -Compress)}} | ConvertTo-Json -Depth 6 -Compress
Assert-UnityFanoutSources $pr.merge_commit_sha $approval.gui.source_sha
if (Get-UnityGuiDispatchReuse $approval $pr.merge_commit_sha) { 'dispatch_needed=false' >> $env:GITHUB_OUTPUT; Write-Output 'Exact successful GUI promotion verified; no redispatch.'; exit 0 }
Assert-UnityGuiDispatchIntent $pr.merge_commit_sha
[IO.File]::WriteAllText((Join-Path $WorkRoot 'gui-dispatch.json'),$body)
'dispatch_needed=true' >> $env:GITHUB_OUTPUT
if ($ValidateOnly) { exit 0 }
if (!$env:UNITY_DISPATCH_TOKEN) { throw 'Scoped GUI Actions-write token required after validation.' }
Send-UnityGuiDispatch (Join-Path $WorkRoot 'gui-dispatch.json') $env:GH_TOKEN $env:UNITY_DISPATCH_TOKEN

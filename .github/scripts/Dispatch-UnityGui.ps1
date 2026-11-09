param([Parameter(Mandatory)][string]$EventPath,[Parameter(Mandatory)][string]$WorkRoot,[switch]$ValidateOnly)
. "$PSScriptRoot/UnityPromotion.ps1"
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $UnityWrapperRepository) { throw 'Trusted wrapper dispatcher required.' }
$event=Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
$pr=$event.pull_request
if (!$pr.merged -or $pr.base.ref -cne (Get-WssCiChannel) -or $pr.head.repo.full_name -cne $UnityWrapperRepository -or $pr.user.type -cne 'Bot' -or $pr.head.ref -cnotlike 'automation/unity-wss-*') { throw 'Not a reviewed Unity dependency promotion.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Dispatcher workspace must be new.' }
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-approval' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
$approval=Read-UnityApprovalMarker $pr.body (Join-Path $WorkRoot 'approval.json')
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-approval' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
if ($pr.head.ref -cne "automation/unity-wss-$($approval.candidate.run_id)-$($approval.candidate.sha256)") { throw 'Promotion branch/candidate mismatch.' }
$config=Read-UnityConfig "$PSScriptRoot/../unity-ci.json"
if (!$config.baseline_ready -or $config.automated_execution -cne 'dotnet') { throw 'Approved .NET promotion baseline required.' }
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-family-evidence' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-UnityApproval $approval (Join-Path $WorkRoot 'evidence') $config
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-family-evidence' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-reviewed-merge' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-UnityMergedWrapper $pr.merge_commit_sha ([string]$pr.number) $approval
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-reviewed-merge' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
$body=@{ref=(Get-WssCiChannel);inputs=@{wrapper_sha=$pr.merge_commit_sha;wrapper_pr=[string]$pr.number;approval_json=($approval | ConvertTo-Json -Depth 8 -Compress)}} | ConvertTo-Json -Depth 6 -Compress
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'recheck-source' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-UnityFanoutSources $pr.merge_commit_sha $approval.gui.source_sha
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'recheck-source' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'inspect-reuse' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
if (Get-UnityGuiDispatchReuse $approval $pr.merge_commit_sha) { 'dispatch_needed=false' >> $env:GITHUB_OUTPUT; Write-Output 'Exact successful GUI promotion verified; no redispatch.'; exit 0 }
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'inspect-reuse' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-intent' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
Assert-UnityGuiDispatchIntent $pr.merge_commit_sha
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'validate-intent' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'write-intent' -Status 'started' -ErrorCode 'none' } catch { } # wss-diag
[IO.File]::WriteAllText((Join-Path $WorkRoot 'gui-dispatch.json'),$body)
'dispatch_needed=true' >> $env:GITHUB_OUTPUT
try { Write-WssCiPhaseDiagnostic -Family 'unity' -Role 'gui' -Operation 'write-intent' -Status 'completed' -ErrorCode 'none' } catch { } # wss-diag
if ($ValidateOnly) { exit 0 }
if (!$env:UNITY_DISPATCH_TOKEN) { throw 'Scoped GUI Actions-write token required after validation.' }
Send-UnityGuiDispatch (Join-Path $WorkRoot 'gui-dispatch.json') $env:GH_TOKEN $env:UNITY_DISPATCH_TOKEN

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/../UnityPromotion.ps1"
$script:mode='valid';$script:events=[Collections.Generic.List[string]]::new()
$script:candidate=@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='10';artifact_id='20';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$script:wrapperSha='c'*40;$script:guiSha='d'*40
$approval=[pscustomobject]@{candidate=$script:candidate;wrapper=@{preflight_run_id='11';source_sha=$script:wrapperSha};gui=@{preflight_run_id='12';source_sha=$script:guiSha};projection_sha256=('e'*64);fixture=@{commit=('f'*40);sha256=('a'*64)}}
$config=@{fixture_commit=('f'*40);fixture_sha256=('a'*64)}
function Assert-UnityProducer($Candidate) {}
function Wait-UnityRun($Repository,$RunId,$Sha,$Workflow,$Event){[pscustomobject]@{id=$RunId;run_attempt=3;head_sha=$Sha}}
function Invoke-UnityGh { throw 'Receipt used legacy rich-evidence transport.' }
function Start-WssCiPreflightProof($Repository,$RunId,$SourceSha,$Root,$ExpectedAttempt){
 if($ExpectedAttempt -ne 3 -or !$Root.EndsWith('-proof')){throw 'Observed attempt/proof root changed.'}
 if($script:mode -ceq 'capture-drift'){throw 'capture drift'}
 $role=if($Repository -ceq $UnityWrapperRepository){'wrapper'}else{'gui'}
 $required=if($role -ceq 'wrapper'){'Preflight behavioral tests'}else{'GUI general conformance'}
 $names=@($required,'Preflight platform compatibility (Windows)','Preflight platform compatibility (Ubuntu)','Preflight platform compatibility (macOS)')
 $jobs=@();$id=100;foreach($name in $names){$id++;$jobs+=@{id=[string]$id;name=$name;status='completed';conclusion='success'}}
 if($script:mode -ceq 'required-job-failure'){$jobs[0].conclusion='skipped'}
 $script:events.Add("capture:$RunId")
 [pscustomobject]@{Run=@{id=$RunId;run_attempt=3};Jobs=$jobs;repository=$Repository;run_id=$RunId;source_sha=$SourceSha;role=$role}
}
function New-TestEvidence($Proof){
 [pscustomobject]@{candidate=$script:candidate;schema='wss-dotnet-platform-evidence/v1';execution='dotnet';unity_executed=$false;mode='candidate';role=$Proof.role;run_repository=$Proof.repository;run_id=$Proof.run_id;run_sha=$Proof.source_sha;wrapper_sha=$script:wrapperSha;gui_sha=$script:guiSha;projection_sha256=('e'*64);fixture_sha=('f'*40);fixture_sha256=('a'*64)}
}
function Read-WssCiPreflightArtifact($Proof,$Name,$Destination){
 if($script:mode -ceq 'artifact-failure'){throw 'artifact failure'}
 $script:events.Add("artifact:$($Proof.run_id):$Name")
 $null=New-Item -ItemType Directory -Path $Destination
 $e=New-TestEvidence $Proof
 if($Name -ceq 'unity-preflight-evidence'){
  $e|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Destination 'evidence.json')
 }elseif($Name -cmatch '^unity-preflight-platform-(wrapper|gui)-macOS-(x64|arm64)$'){
  [IO.File]::WriteAllText((Join-Path $Destination 'platform-result.json'),'{}')
  $e|Add-Member -NotePropertyName platform_result_sha256 -NotePropertyValue (Get-FileHash (Join-Path $Destination 'platform-result.json')).Hash.ToLowerInvariant()
  if($script:mode -ceq 'native-source-mismatch'){$e.run_sha='0'*40}
  if($script:mode -ceq 'projection-mismatch'){$e.projection_sha256='0'*64}
  $e|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Destination 'platform-evidence.json')
 }else{throw 'Unexpected native artifact name.'}
}
function Assert-MacOSConsumerProbe($Path,$Architecture,[switch]$RequireBackend,$Repository,$RunId,$Attempt,$SourceSha){if($Attempt -cne '3' -or !$RequireBackend){throw 'macOS probe lost captured attempt/native requirement.'}}
# The existing evidence-file suite owns the complete runtime/XML/projection semantics.
# This boundary fixture mocks that one checker, while actual Get/Approval/Merged checks run.
function Assert-UnityEvidenceFiles($Root,$Repository,$RunId,$SourceSha,$Role,$Candidate,$Config){
 $script:events.Add("native:$RunId")
 if($script:mode -ceq 'native-files-failure'){throw 'native files failure'}
 Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw|ConvertFrom-Json
}
function Complete-WssCiPreflightProof($Proof){
 if(!$script:events.Contains("native:$($Proof.run_id)")){throw 'Proof completed before native checks.'}
 if($script:mode -ceq 'complete-drift'){throw 'complete drift'}
 $script:events.Add("complete:$($Proof.run_id)")
 [pscustomobject]@{repository=$Proof.repository;run_id=$Proof.run_id;source_sha=$Proof.source_sha;workflow='.github/workflows/wss-preflight.yml';attempt=3;jobs=$Proof.Jobs;artifacts=@(@{id='77';name='unity-preflight-evidence';digest=('sha256:'+('f'*64))});logs=@()}
}
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$root=Join-Path $tempRoot ('wss unity snapshots '+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $root
try {
 $list=[Collections.Generic.List[object]]::new()
 $output=@(Assert-UnityApproval $approval (Join-Path $root 'paired') $config -ReceiptSnapshots $list)
 if($output.Count -or $list.Count -ne 2 -or @($list|Where-Object attempt -ne 3).Count){throw 'Paired Unity snapshots/stdout contract changed.'}
 $script:wrapperSha='9'*40
 $output=@(Assert-UnityMergedGuiPreflight $approval $script:wrapperSha $script:guiSha '13' (Join-Path $root 'actual-wrapper') $config -ReceiptSnapshots $list)
 if($output.Count -or $list.Count -ne 3 -or $list[2].run_id -cne '13'){throw 'Actual-wrapper GUI snapshot missing.'}
 $script:wrapperSha=$approval.wrapper.source_sha
 $snapshot=$null
 $e=Get-UnityEvidence $UnityWrapperRepository '11' $script:wrapperSha 'wrapper' $script:candidate (Join-Path $root 'return-contract') $config -ReceiptSnapshot ([ref]$snapshot)
 if($e.wrapper_sha -cne $script:wrapperSha -or $snapshot.attempt -ne 3){throw 'Existing Get-UnityEvidence return contract changed.'}
 $rejects=0
 foreach($case in @('capture-drift','required-job-failure','artifact-failure','native-source-mismatch','projection-mismatch','native-files-failure','complete-drift')){
  $script:mode=$case;$script:events.Clear();$snapshot=$null;$failed=$false
  try{Get-UnityEvidence $UnityWrapperRepository '11' $script:wrapperSha 'wrapper' $script:candidate (Join-Path $root $case) $config -ReceiptSnapshot ([ref]$snapshot)|Out-Null}catch{$failed=$true}
  if(!$failed -or $null -ne $snapshot){throw "Native proof failure produced an accepted descriptor: $case"};$rejects++
 }
 "Unity receipt snapshot contracts passed (paired and actual-wrapper snapshots, unchanged Get return value; $rejects fail-closed cases)."
}finally{
 $resolved=[IO.Path]::GetFullPath($root);$prefix=$tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
 if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^wss unity snapshots [0-9a-f]{32}$'){throw 'Unsafe fixture cleanup path.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
$global:LASTEXITCODE=0
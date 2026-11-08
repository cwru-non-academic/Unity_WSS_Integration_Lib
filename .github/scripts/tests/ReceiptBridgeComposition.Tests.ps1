param([string]$CommonRoot=(Join-Path $PSScriptRoot '../wss-ci'))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../UnityPromotion.ps1"
. (Join-Path $CommonRoot 'Evidence.ps1')
$preload=Join-Path $CommonRoot 'tests/receipt-gh-preload.mjs'
if(!(Test-Path $preload)){throw 'Real receipt bridge transport fixture is required.'}
$oldOptions=$env:NODE_OPTIONS;$oldResponses=$env:WSS_TEST_GH_RESPONSES;$oldChannel=$env:WSS_CI_CHANNEL
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$root=Join-Path $tempRoot ('wss unity composition '+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $root
$config=Get-Content (Join-Path $PSScriptRoot '../../unity-ci.json') -Raw|ConvertFrom-Json
$candidate=@{repository='cwru-non-academic/WSSCore';commit=('a'*40);run_id='10';artifact_id='20';archive='WSS-Universal-ci.zip';sha256=('b'*64)}
$wrapperSha='c'*40;$guiSha='d'*40;$mergedSha='9'*40
$files=@($UnityProjectionFiles|ForEach-Object {@{source=$_;sha256=('1'*64);meta_sha256=('2'*64)}})
$projection=@{schema='wss-unity-projection/v1';candidate=$candidate;files=$files;projection_sha256=(Get-UnityProjectionDigest $files)}
$approval=[pscustomobject]@{candidate=$candidate;wrapper=@{preflight_run_id='11';source_sha=$wrapperSha};gui=@{preflight_run_id='12';source_sha=$guiSha};projection_sha256=$projection.projection_sha256;fixture=@{commit=$config.fixture_commit;sha256=$config.fixture_sha256}}
function Add-Route($Arguments,$Value){$script:routes.Add(@{args=@($Arguments);json=$Value})}
function Write-Json($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
function Invoke-UnityGh([string[]]$Arguments){
 $key=ConvertTo-Json -InputObject $Arguments -Compress
 $matches=@($script:routes|Where-Object {(ConvertTo-Json -InputObject $_.args -Compress) -ceq $key})
 if($matches.Count -ne 1 -or !$matches[0].ContainsKey('json')){throw "Unexpected native GitHub fixture request: $key"}
 ConvertTo-Json -InputObject $matches[0].json -Depth 30
}
function Add-Archive($Repository,$RunId,$SourceSha,$Name,$Directory){
 $zip="$Directory.zip";[IO.Compression.ZipFile]::CreateFromDirectory($Directory,$zip)
 $script:artifactId++;$artifact=@{id=$script:artifactId;name=$Name;expired=$false;digest=('sha256:'+(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant());workflow_run=@{id=[int]$RunId;head_sha=$SourceSha}}
 Add-Route @('api',"repos/$Repository/actions/artifacts/$($artifact.id)") $artifact
 $script:routes.Add(@{args=@('api',"repos/$Repository/actions/artifacts/$($artifact.id)/zip");file=$(if($script:case -ceq 'wrong-zip'){$script:wrongZip}else{$zip})})
 $artifact
}
function Build-Evidence($Repository,$RunId,$SourceSha,$Role,$Wrapper){
 $dir=Join-Path $root "$script:case-$RunId-rich";$null=New-Item -ItemType Directory -Path (Join-Path $dir 'multi')
 $base=@{schema='wss-dotnet-evidence/v1';candidate=$candidate;execution='dotnet';unity_executed=$false;role=$Role;mode='candidate';run_repository=$Repository;run_id=$RunId;run_sha=$SourceSha;wrapper_sha=$Wrapper;gui_sha=$guiSha;fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256;sdk=$config.dotnet_sdk;target_framework='net9.0';test_framework='NUnit 3.14.0';discovered=16;executed=16;passed=16;failed=0;skipped=0;assertion_expressions=20;projection_sha256=$projection.projection_sha256}
 foreach($stage in @('single','multi')){
  $target=if($stage -ceq 'single'){$dir}else{Join-Path $dir 'multi'}
  $names=if($stage -ceq 'single'){@($config.dotnet_expected_cases)}else{@($config.dotnet_expected_cases|Select-Object -First 10)+@($config.multidevice_expected_cases)}
  $cases=($names|ForEach-Object {'<test-case name="'+[Security.SecurityElement]::Escape($_)+'" result="Passed" />'}) -join ''
  [IO.File]::WriteAllText((Join-Path $target 'results.xml'),('<test-run result="Passed" testcasecount="16" total="16" passed="16" failed="0" skipped="0" inconclusive="0">'+$cases+'</test-run>'))
  [IO.File]::WriteAllText((Join-Path $target 'dotnet.log'),'Synthetic transport contract fixture; no runtime execution.')
  Write-Json (Join-Path $target 'projection.json') $projection
  $e=$base.Clone();$e.stage=$stage;$e.results_sha256=(Get-FileHash (Join-Path $target 'results.xml')).Hash.ToLowerInvariant();$e.log_sha256=(Get-FileHash (Join-Path $target 'dotnet.log')).Hash.ToLowerInvariant()
  if($script:case -ceq 'invalid-native-count'){$e.passed=15}
  Write-Json (Join-Path $target 'evidence.json') $e
 }
 $artifacts=@(Add-Archive $Repository $RunId $SourceSha 'unity-preflight-evidence' $dir)
 foreach($arch in @(@('x64','X64'),@('arm64','Arm64'))){
  $mac=Join-Path $root "$script:case-$RunId-$($arch[0])";$null=New-Item -ItemType Directory -Path $mac
  $identity=New-WssCiEvidenceIdentity $Repository $RunId '3' $SourceSha $arch[1]
  if($script:case -ceq 'wrong-mac-attempt'){$identity.attempt='4'}
  $probe=@{schema='wss-dotnet-platform-probe/v1';execution='dotnet';unity_executed=$false;hardware_access=$false;ci=$identity;architecture=$arch[1];os='macOS synthetic metadata fixture';ble='synthetic metadata only';macos_backend_declared=$true;macos_native_abi_verified=$true}
  Write-Json (Join-Path $mac 'platform-result.json') $probe
  $e=$base.Clone();$e.schema='wss-dotnet-platform-evidence/v1';$e.platform_result_sha256=(Get-FileHash (Join-Path $mac 'platform-result.json')).Hash.ToLowerInvariant()
  Write-Json (Join-Path $mac 'platform-evidence.json') $e
  $artifacts+=Add-Archive $Repository $RunId $SourceSha "unity-preflight-platform-$Role-macOS-$($arch[0])" $mac
 }
 Add-Route @('api',"repos/$Repository/actions/runs/$RunId/artifacts?per_page=100&page=1") @{artifacts=$artifacts;total_count=$artifacts.Count}
}
try{
 $env:WSS_CI_CHANNEL='dev';$env:NODE_OPTIONS=($oldOptions+' --import="'+([Uri]::new([IO.Path]::GetFullPath($preload))).AbsoluteUri+'"').Trim()
 $producerModule=Join-Path $CommonRoot 'producer-jobs.mjs'
 $producerNames=& node --input-type=module --eval 'import {pathToFileURL} from "node:url";const m=await import(pathToFileURL(process.argv[2]).href);console.log(JSON.stringify(m.requiredProducerJobs("macos-ble-v1")));' -- 'receipt-composition-fixture' $producerModule|ConvertFrom-Json
 if($LASTEXITCODE -ne 0){throw 'Producer fixture could not load canonical required jobs.'}
 $script:wrongZip=Join-Path $root 'wrong.zip';[IO.File]::WriteAllText($script:wrongZip,'wrong ZIP bytes')
 $passed=0;$rejected=0
 foreach($case in @('valid','invalid-native-count','wrong-zip','wrong-mac-attempt')){
  $script:case=$case;$script:routes=[Collections.Generic.List[object]]::new();$script:artifactId=1000
  $env:WSS_TEST_GH_RESPONSES=Join-Path $root "$case-routes.json"
  $producer=@{id=10;run_attempt=3;repository=@{full_name=$candidate.repository};head_repository=@{full_name=$candidate.repository};head_branch='dev';head_sha=$candidate.commit;path='.github/workflows/artifacts.yml';event='push';status='completed';conclusion='success'}
  Add-Route @('api','repos/cwru-non-academic/WSSCore/actions/runs/10') $producer
  Add-Route @('api',"repos/cwru-non-academic/WSSCore/compare/$($candidate.commit)...dev") @{status='identical'}
  $jobs=@($producerNames|ForEach-Object {@{name=$_;status='completed';conclusion='success'}})
  Add-Route @('api','--paginate','--slurp','repos/cwru-non-academic/WSSCore/actions/runs/10/attempts/3/jobs?per_page=100') @(@{jobs=$jobs})
  Add-Route @('api','repos/cwru-non-academic/WSSCore/actions/artifacts/20') @{name='universal-release-assets';expired=$false;workflow_run=@{id=10;head_sha=$candidate.commit}}
  foreach($entry in @(@('11',$UnityWrapperRepository,$wrapperSha,'wrapper',$wrapperSha),@('12',$UnityGuiRepository,$guiSha,'gui',$wrapperSha),@('13',$UnityGuiRepository,$guiSha,'gui',$mergedSha))){
   $id,$repo,$sha,$role,$wrapper=$entry
   $run=@{id=[int]$id;run_attempt=3;repository=@{full_name=$repo};head_repository=@{full_name=$repo};head_branch='dev';head_sha=$sha;path='.github/workflows/wss-preflight.yml';event='workflow_dispatch';status='completed';conclusion='success'}
   Add-Route @('api',"repos/$repo/actions/runs/$id") $run
   $required=if($role -ceq 'wrapper'){'Preflight behavioral tests'}else{'GUI general conformance'}
   $jobs=@();$job=100;foreach($name in @($required,'Preflight platform compatibility (Windows)','Preflight platform compatibility (Ubuntu)','Preflight platform compatibility (macOS)')){$job++;$jobs+=@{id=$job;name=$name;status='completed';conclusion='success'}}
   Add-Route @('api',"repos/$repo/actions/runs/$id/attempts/3/jobs?per_page=100&page=1") @{jobs=$jobs;total_count=$jobs.Count}
   Build-Evidence $repo $id $sha $role $wrapper
  }
  Write-Json $env:WSS_TEST_GH_RESPONSES @{routes=$script:routes.ToArray();calls_file=(Join-Path $root "$case-calls.jsonl")}
  $list=[Collections.Generic.List[object]]::new();$failure=$null
  try{
   $output=@(Assert-UnityApproval $approval (Join-Path $root "$case-proof") $config -ReceiptSnapshots $list)
   $output+=@(Assert-UnityMergedGuiPreflight $approval $mergedSha $guiSha '13' (Join-Path $root "$case-merged-proof") $config -ReceiptSnapshots $list)
  }catch{$failure=$_}
  if($case -ceq 'valid'){
   if($failure){throw $failure}
   if($output.Count -or $list.Count -ne 3 -or $list[2].run_id -cne '13' -or @($list|Where-Object {$_.attempt -ne 3 -or $_.artifacts.Count -ne 3}).Count){throw 'Real bridge lost paired/actual-wrapper rich snapshots.'}
   $passed++
  }else{if(!$failure){throw "Real rich bridge accepted $case"};$rejected++}
 }
 "Unity real receipt bridge composition passed ($passed paired+actual-wrapper positive, $rejected rich semantic/ZIP/attempt negatives; unchanged native validators, real Node capture/extraction; only GitHub transport stubbed)."
}finally{
 $env:NODE_OPTIONS=$oldOptions;$env:WSS_TEST_GH_RESPONSES=$oldResponses;$env:WSS_CI_CHANNEL=$oldChannel
 $resolved=[IO.Path]::GetFullPath($root);$prefix=$tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
 if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^wss unity composition [0-9a-f]{32}$'){throw 'Unsafe composition fixture cleanup path.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
$global:LASTEXITCODE=0
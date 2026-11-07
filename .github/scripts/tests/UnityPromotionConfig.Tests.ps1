# Executes both production entrypoints. Invalid approval is an intentional boundary
# sentinel: no network, dispatch, credential minting or publication is performed.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('unity-promotion-config-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$tools=Join-Path $temp 'tools';$target=Join-Path $temp 'target'
$null=New-Item -ItemType Directory -Path $tools,$target
Copy-Item -LiteralPath (Join-Path $root '.github') -Destination $tools -Recurse
$null=New-Item -ItemType Directory -Path (Join-Path $target '.github')
function FixtureGit([string]$Path,[string[]]$Arguments) {
 $out=& git -C $Path @Arguments 2>&1
 if($LASTEXITCODE){throw "Fixture git failed: $out"}
 $out
}
function Commit([string]$Path) {
 $null=FixtureGit $Path @('add','-A');$null=FixtureGit $Path @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','Local regression fixture')
 (FixtureGit $Path @('rev-parse','HEAD')).Trim()
}
foreach($path in @($tools,$target)){$null=FixtureGit $path @('init','-q')}
$modern=Get-Content (Join-Path $tools '.github/unity-ci.json') -Raw|ConvertFrom-Json
$legacy=$modern|ConvertTo-Json -Depth 20|ConvertFrom-Json
foreach($field in @('fixture_repository','fixture_commit','fixture_sha256','expected_cases','dotnet_expected_cases','multidevice_expected_cases')){$legacy.$field=$modern.profiles.'legacy-v1'.$field}
$legacy.PSObject.Properties.Remove('profiles')
$targetConfig=Join-Path $target '.github/unity-ci.json';$toolConfig=Join-Path $tools '.github/unity-ci.json'
function Save($Value,[string]$Path){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 20))}
Save $legacy $targetConfig
$toolSha=Commit $tools;$targetSha=Commit $target
$count=0
$names=@('GITHUB_ACTIONS','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_SHA','GITHUB_REPOSITORY','GITHUB_WORKFLOW_SHA','GITHUB_WORKFLOW_REF','WSS_CI_CHANNEL','UNITY_PUSH_TOKEN','GITHUB_OUTPUT')
$saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
function Check([string]$Expected,[string]$Role='gui',[string]$Sha=$toolSha,[switch]$WrongBinding,[switch]$WrongSource,[switch]$WrongWorkflow) {
 foreach($entry in @('Prepare','Publish')) {
  $work=Join-Path $temp ([guid]::NewGuid().ToString('N'))
  $repo=if($Role -ceq 'gui'){$target}else{$tools}
  $env:GITHUB_SHA=(FixtureGit $repo @('rev-parse','HEAD')).Trim()
  $env:GITHUB_REPOSITORY=if($Role -ceq 'gui'){'cwru-non-academic/GUI_Unity_WSS_Application'}else{'cwru-non-academic/Unity_WSS_Integration_Lib'}
  $env:GITHUB_WORKFLOW_SHA=$env:GITHUB_SHA
  $workflow=if($Role -ceq 'gui'){'promote-integration.yml'}else{'promote-wss.yml'}
  $env:GITHUB_WORKFLOW_REF="$env:GITHUB_REPOSITORY/.github/workflows/$workflow@$env:GITHUB_REF"
  if ($WrongSource) { $env:GITHUB_SHA='0'*40 }
  if ($WrongWorkflow) { $env:GITHUB_WORKFLOW_SHA='0'*40 }
  $args=@{RepositoryRoot=$repo;WorkRoot=$work;ToolSha=$Sha}
  if($entry -ceq 'Publish') {
   $null=New-Item -ItemType Directory -Path $work
   Save @{role=$Role;no_op=$false;tooling_sha=$(if($WrongBinding){'0'*40}else{$Sha});tooling_config_sha256=(Get-FileHash $toolConfig).Hash.ToLowerInvariant()} (Join-Path $work 'prepared.json')
   Save @{schema='invalid-boundary-sentinel'} (Join-Path $work 'approval.json')
  } else {
   $args.Role=$Role;$args.ValidateOnly=$true
   if($Role -ceq 'gui'){$args.ApprovalJson='{"schema":"invalid-boundary-sentinel"}'}else{$args.CandidateJson='{"repository":"invalid-boundary-sentinel"}'}
  }
  $wanted=if($WrongBinding -and $entry -ceq 'Prepare'){'Unity-specific approval schema required.*'}elseif($Expected -ceq 'boundary' -and $Role -ceq 'wrapper' -and $entry -ceq 'Prepare'){'Unexpected producer.*'}elseif($Expected -ceq 'boundary'){'Unity-specific approval schema required.*'}else{$Expected}
  try { & (Join-Path $tools ".github/scripts/$entry-UnityPromotion.ps1") @args;throw 'Unexpected entrypoint success.' }
  catch {if($_.Exception.Message -notlike $wanted){throw "$entry/$Role expected $wanted but got $($_.Exception.Message)"}}
  $script:count++
 }
}
try {
 $env:GITHUB_ACTIONS='true';$env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REF='refs/heads/dev';$env:WSS_CI_CHANNEL='dev';$env:UNITY_PUSH_TOKEN='inert-test-sentinel';$env:GITHUB_OUTPUT=Join-Path $temp 'outputs'
 Check 'boundary';Check 'boundary' 'wrapper'
 $env:GITHUB_REF='refs/heads/main';$env:WSS_CI_CHANNEL='main';Check 'boundary';Check 'boundary' 'wrapper'
 Check 'Main promotion must execute*' -WrongWorkflow
 Check 'Main promotion must execute*' 'wrapper' -WrongWorkflow
 $env:GITHUB_REF='refs/heads/dev';$env:WSS_CI_CHANNEL='dev'
 foreach($case in @('opt-out','runtime','sdk','channel')) {
  $bad=$legacy|ConvertTo-Json -Depth 20|ConvertFrom-Json
  switch($case){'opt-out'{$bad.baseline_ready=$false;$expected='Approved .NET target*'}'runtime'{$bad.automated_execution='unity';$expected='Approved .NET target*'}'sdk'{$bad.dotnet_sdk='wrong';$expected='Target and tooling promotion SDK*'}'channel'{$bad.channels=@('main');$expected='Target does not authorize*'}}
  Save $bad $targetConfig;$null=Commit $target;Check $expected
 }
 Save $legacy $targetConfig;$null=Commit $target
 foreach($flag in @('--assume-unchanged','--skip-worktree')) {
  $null=FixtureGit $target @('update-index',$flag,'--','.github/unity-ci.json')
  Check 'Target promotion policy cannot hide*'
  $clear=if($flag -ceq '--assume-unchanged'){'--no-assume-unchanged'}else{'--no-skip-worktree'}
  $null=FixtureGit $target @('update-index',$clear,'--','.github/unity-ci.json')
 }
 Check 'Promotion checkout differs*' -WrongSource
 Check 'Promotion checkout differs*' 'wrapper' -WrongSource
 $null=FixtureGit $target @('rm','--cached','--','.github/unity-ci.json')
 [IO.File]::WriteAllText((Join-Path $target '.gitignore'),".github/unity-ci.json`n")
 $null=Commit $target;Check 'Target promotion policy cannot hide*'
 $null=FixtureGit $target @('add','-f','--','.github/unity-ci.json');$null=Commit $target
 Check 'GUI promotion requires*' 'gui' ''
 Check 'Checked-out source differs*' 'gui' ('0'*40)
 Check 'Prepared and publication tooling*' -WrongBinding
 # An uncommitted config change cannot ride along with the reviewed ToolSha.
 Add-Content -LiteralPath $toolConfig ' ';Check 'Source checkout must be clean*'
 $null=FixtureGit $tools @('restore','--','.github/unity-ci.json')
 foreach($case in @('opt-out','runtime','sdk','channel','fixture','profiles')) {
  $bad=$modern|ConvertTo-Json -Depth 20|ConvertFrom-Json
  switch($case){'opt-out'{$bad.baseline_ready=$false;$expected='Approved .NET tooling*'}'runtime'{$bad.automated_execution='unity';$expected='Approved .NET tooling*'}'sdk'{$bad.dotnet_sdk='wrong';$expected='Target and tooling promotion SDK*'}'channel'{$bad.channels=@('main');$expected='Tooling does not authorize*'}'fixture'{$bad.profiles.'layered-v1'.fixture_commit='0'*40;$expected='Unreviewed canonical profile*'}'profiles'{$bad.PSObject.Properties.Remove('profiles');$expected='The complete reviewed dual-profile*'}}
  Save $bad $toolConfig;$toolSha=Commit $tools;Check $expected
  $wrapperExpected=switch($case){'opt-out'{'Approved .NET target*'}'runtime'{'Approved .NET target*'}'channel'{'Target does not authorize*'}default{$expected}}
  Check $wrapperExpected 'wrapper'
 }
 Save $modern $toolConfig;$toolSha=Commit $tools
 . (Join-Path $tools '.github/scripts/UnityPromotion.ps1')
 . (Join-Path $tools '.github/scripts/UnityPromotionConfig.ps1')
 foreach($redirect in @('root','config')) {
  try {if($redirect -ceq 'root'){Resolve-UnityTooling $target $toolSha '' '' $toolConfig}else{Resolve-UnityTooling $tools $toolSha '' '' $targetConfig};throw 'Redirect accepted'}catch{if($_.Exception.Message -notlike 'ToolRoot must be*' -and $_.Exception.Message -notlike 'ConfigPath must be*'){throw}};$count++
 }
 if((Read-UnityConfig $toolConfig 'legacy-v1').expected_cases.Count -ne 10 -or (Read-UnityConfig $toolConfig 'layered-v1').expected_cases.Count -ne 16){throw 'Profiles changed.'};$count++
 if((Get-Content $targetConfig -Raw|ConvertFrom-Json).PSObject.Properties['profiles']){throw 'Legacy target was modernized.'};$count++
 Write-Output "PASS: $count promotion configuration entrypoint and binding checks. No network, runtime, Editor or hardware execution."
} finally {foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name])}}

$ErrorActionPreference='Stop'
. "$PSScriptRoot/../SelectedProcessIsolation.ps1"
$directory=Join-Path ([IO.Path]::GetTempPath()) ('wss-isolation-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$child=Join-Path $directory 'child.ps1'
$code=@'
param([string]$Marker,[int]$ExitCode)
$forbidden=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN','WSS_EVIDENCE_READ_TOKEN','GITHUB_OUTPUT','GITHUB_ENV')
foreach($name in $forbidden){if([Environment]::GetEnvironmentVariable($name)){throw "Credential leaked: $name"}}
if(Get-Variable -Name privateParentCredential -ErrorAction SilentlyContinue){throw 'Parent dynamic scope leaked'}
[IO.File]::WriteAllText($Marker,'isolated')
exit $ExitCode
'@
[IO.File]::WriteAllText($child,$code,[Text.UTF8Encoding]::new($false))
$names=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN','WSS_EVIDENCE_READ_TOKEN','GITHUB_OUTPUT','GITHUB_ENV')
$prior=@{}
$privateParentCredential='dummy-parent-variable'
try{
    foreach($name in $names){$prior[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,'dummy-isolation-value')}
    $marker=Join-Path $directory 'success.txt'
    Invoke-CredentialFreeSelectedPowerShell $child @{Marker=$marker;ExitCode=0}
    if([IO.File]::ReadAllText($marker) -cne 'isolated'){throw 'Child did not run'}
    $failed=$false
    try{Invoke-CredentialFreeSelectedPowerShell $child @{Marker=(Join-Path $directory 'failure.txt');ExitCode=23}}catch{$failed=$true}
    if(!$failed){throw 'Failed child was accepted'}
    foreach($name in $names){if([Environment]::GetEnvironmentVariable($name) -cne 'dummy-isolation-value'){throw 'Parent credential was altered'}}
    Write-Output 'Credential-free child, isolated variable scope, failure rejection and parent preservation passed.'
}finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$prior[$name])}}

$evidence=Join-Path $directory 'mandatory'
$null=New-Item -ItemType Directory -Path $evidence
[IO.File]::WriteAllText((Join-Path $evidence 'evidence.json'),'trusted')
$inventory=Get-UnityEvidenceInventory $evidence
Assert-UnityEvidenceInventory $evidence $inventory
foreach($mutation in @('modify','add','delete','directory')){
    $file=Join-Path $evidence 'evidence.json'
    switch($mutation){
        modify {[IO.File]::WriteAllText($file,'changed')}
        add {[IO.File]::WriteAllText((Join-Path $evidence 'extra.json'),'extra')}
        delete {Remove-Item -LiteralPath $file}
        directory {$null=New-Item -ItemType Directory -Path (Join-Path $evidence 'extra-dir')}
    }
    $rejected=$false
    try{Assert-UnityEvidenceInventory $evidence $inventory}catch{$rejected=$true}
    if(!$rejected){throw "Mandatory inventory accepted $mutation"}
    if($mutation -ceq 'add'){Remove-Item -LiteralPath (Join-Path $evidence 'extra.json')}
    if($mutation -ceq 'directory'){Remove-Item -LiteralPath (Join-Path $evidence 'extra-dir')}
    [IO.File]::WriteAllText($file,'trusted')
}
$bridge=Get-Content "$PSScriptRoot/../Invoke-SelectedUnityTests.ps1" -Raw
$helper=Get-Content "$PSScriptRoot/../SelectedProcessIsolation.ps1" -Raw
$first=$helper.IndexOf('Invoke-CredentialFreeSelectedPowerShell $Runner $baselineOptions')
$second=$helper.IndexOf('Invoke-CredentialFreeSelectedPowerShell $Runner $Options')
$recheck=$helper.IndexOf('Assert-UnityEvidenceInventory $BaselineRoot $mandatoryInventory')
$gate=$bridge.IndexOf('Invoke-UnitySelectedWithMandatoryBaseline')
$emission=$bridge.IndexOf('& node $bootstrap evidence')
if($first -lt 0 -or $second -le $first -or $recheck -le $second -or $gate -lt 0 -or $emission -le $gate){throw 'Trusted baseline/selected/recheck/evidence ordering changed.'}
Write-Output 'Complete baseline inventory mutations rejected; separate-child ordering verified.'

$fakeRunner=Join-Path $directory 'fake-runner.ps1'
$fakeCode=@(
'param([string]$OutputRoot,[string]$TestRoot="",[string]$BaselineRoot,[string]$Mode)',
'if(!$TestRoot){',
' $null=New-Item -ItemType Directory -Path $OutputRoot',
' [IO.File]::WriteAllText((Join-Path $OutputRoot "evidence.json"),"trusted-baseline")',
' if($Mode -ceq "baseline-failure"){exit 41}',
'}else{',
' if(!(Test-Path (Join-Path $BaselineRoot "evidence.json"))){throw "Selected code ran before baseline."}',
' function global:Assert-UnityEvidenceInventory { }',
' if($Mode -ceq "tamper"){[IO.File]::WriteAllText((Join-Path $BaselineRoot "evidence.json"),"forged")}',
' [IO.File]::WriteAllText($OutputRoot,"selected-ran")',
'}'
)
$fakeCode | Set-Content -LiteralPath $fakeRunner
foreach($mode in @('scope-override','tamper','baseline-failure')){
    $baseline=Join-Path $directory "baseline-$mode"
    $marker=Join-Path $directory "selected-$mode"
    $failed=$false
    try{Invoke-UnitySelectedWithMandatoryBaseline $fakeRunner @{OutputRoot=$marker;TestRoot='untrusted';BaselineRoot=$baseline;Mode=$mode} $baseline -ConformanceOnly}catch{$failed=$true}
    if($mode -ceq 'scope-override' -and $failed){throw 'Selected scope override affected trusted parent.'}
    if($mode -cne 'scope-override' -and !$failed){throw "Accepted $mode"}
    if($mode -ceq 'baseline-failure' -and (Test-Path $marker)){throw 'Selected code ran after failed baseline.'}
}
Write-Output 'Selected global override isolated; evidence tampering and failed baseline rejected across real child processes.'

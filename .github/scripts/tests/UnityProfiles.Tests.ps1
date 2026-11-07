param([Parameter(Mandatory)][string]$MainRoot,[Parameter(Mandatory)][string]$DevRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../UnityContract.ps1"
. "$PSScriptRoot/../UnityProfiles.ps1"
. "$PSScriptRoot/../UnityHarness.ps1"
$count=0
function Reject([scriptblock]$Action,[string]$Name){try{& $Action | Out-Null}catch{$script:count++;return};throw "Unexpected acceptance: $Name"}
$legacy=[WssProfileMetadata]::Read((Join-Path $MainRoot 'Plugins/WSS_Core_Interface/WSS_Core_Interface.dll'))
$modern=[WssProfileMetadata]::Read((Join-Path $DevRoot 'Plugins/WSS_Core_Interface/WSS_Core_Interface.dll'))
if((Get-WssCapabilityProfile $legacy) -cne 'legacy-v1' -or (Get-WssCapabilityProfile $modern) -cne 'layered-v1'){throw 'Actual baseline profile mismatch.'};$count+=2
foreach($type in @('Wss.Testing.WssStimulationSequence','Wss.Testing.WssStimulationStep','Wss.Testing.WssStimulationSequences','Wss.Testing.WssStimulationWindow','Wss.Testing.WssStimulationWindowResult','Wss.CoreModule.WssConfigurationSnapshot')){
 $broken=[Collections.Generic.Dictionary[string,string[]]]::new($modern,[StringComparer]::Ordinal)
 $null=$broken.Remove($type)
 Reject {Get-WssCapabilityProfile $broken} "missing $type"
 foreach($member in $modern[$type] | Where-Object {$_ -ne '.ctor'}) {
  $broken=[Collections.Generic.Dictionary[string,string[]]]::new($modern,[StringComparer]::Ordinal)
  $broken[$type]=@($modern[$type] | Where-Object {$_ -cne $member})
  Reject {Get-WssCapabilityProfile $broken} "missing $type.$member"
 }
 $partial=[Collections.Generic.Dictionary[string,string[]]]::new($legacy,[StringComparer]::Ordinal)
 $partial.Add($type,$modern[$type]);Reject {Get-WssCapabilityProfile $partial} "legacy plus $type"
}
foreach($type in @('Wss.Testing.WssBehaviorScenarios','Wss.Testing.IWssConformance')){
 foreach($member in $legacy[$type]){
  $broken=[Collections.Generic.Dictionary[string,string[]]]::new($legacy,[StringComparer]::Ordinal)
  $broken[$type]=@($legacy[$type] | Where-Object {$_ -cne $member})
  Reject {Get-WssCapabilityProfile $broken} "missing baseline $type.$member"
 }
}
$old=(Get-Content (Join-Path $MainRoot '.github/unity-candidate.json') -Raw | ConvertFrom-Json).candidate
$new=(Get-Content (Join-Path $DevRoot '.github/unity-candidate.json') -Raw | ConvertFrom-Json).candidate
$null=Resolve-WssReviewedProfile (Join-Path $MainRoot 'Plugins/WSS_Core_Interface') $old
$null=Resolve-WssReviewedProfile (Join-Path $DevRoot 'Plugins/WSS_Core_Interface') $new -SelectionEnabledCampaign
$count+=2
$tagged=$new | ConvertTo-Json | ConvertFrom-Json
$tagged.archive='WSS-Universal-v1.2.3.zip'
# Classification retains the existing resolver's tagged diagnostic format.
# This synthetic metadata check is not producer authentication or acceptance.
$null=Resolve-WssReviewedProfile (Join-Path $DevRoot 'Plugins/WSS_Core_Interface') $tagged -SelectionEnabledCampaign
$count++
$taggedLegacy=$old | ConvertTo-Json | ConvertFrom-Json
$taggedLegacy.archive='WSS-Universal-v1.2.3.zip'
Reject {Resolve-WssReviewedProfile (Join-Path $MainRoot 'Plugins/WSS_Core_Interface') $taggedLegacy} 'legacy archive identity remains exact'
Reject {Resolve-WssReviewedProfile (Join-Path $MainRoot 'Plugins/WSS_Core_Interface') $old -SelectionEnabledCampaign} 'campaign cannot downgrade to legacy'
Reject {Resolve-WssReviewedProfile (Join-Path $MainRoot 'Plugins/WSS_Core_Interface') $new} 'legacy DLL modern producer'
Reject {Resolve-WssReviewedProfile (Join-Path $DevRoot 'Plugins/WSS_Core_Interface') $old} 'modern DLL legacy producer'
foreach($key in @('repository','commit','archive','sha256','run_id','artifact_id')){
 $changed=$old | ConvertTo-Json | ConvertFrom-Json
 $changed.$key=if($key -ceq 'commit'){'f'*40}else{'wrong'}
 Reject {Resolve-WssReviewedProfile (Join-Path $MainRoot 'Plugins/WSS_Core_Interface') $changed} "wrong producer $key"
}
$legacyProfile=[pscustomobject]@{profile='legacy-v1'}
$modernProfile=[pscustomobject]@{profile='layered-v1'}
$legacyConfig=Get-Content (Join-Path $MainRoot '.github/unity-ci.json') -Raw | ConvertFrom-Json
$modernConfig=Get-Content (Join-Path $DevRoot '.github/unity-ci.json') -Raw | ConvertFrom-Json
Assert-UnityProfileContract $legacyProfile $legacyConfig
Assert-UnityProfileContract $modernProfile $modernConfig
Reject {Assert-UnityProfileContract $legacyProfile $modernConfig} 'legacy cannot use modern fixture'
Reject {Assert-UnityProfileContract $modernProfile $legacyConfig} 'modern cannot downgrade baseline'
$currentRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$common=Join-Path $currentRoot '.github/unity-ci.json'
$fromLegacy=Read-UnityExecutionConfig $common $MainRoot
$fromModern=Read-UnityExecutionConfig $common $DevRoot
if($fromLegacy.expected_cases.Count -ne 10 -or $fromModern.expected_cases.Count -ne 16 -or $fromLegacy.fixture_commit -ceq $fromModern.fixture_commit){throw 'Common config did not follow actual payload profiles.'}
$current=Read-UnityExecutionConfig $common $currentRoot
if($current.expected_cases.Count -notin @(10,16)){throw 'Current product profile is unsupported.'}
$count+=3
$temp=Join-Path ([IO.Path]::GetTempPath()) ('unity-profile-config-'+[guid]::NewGuid().ToString('N')+'.json')
foreach($mutation in @('inventory','missing','unknown','hash','commit','count','compatibility')) {
 $broken=Get-Content $common -Raw | ConvertFrom-Json
 switch($mutation) {
  'inventory' {$broken.PSObject.Properties.Remove('profiles')}
  'missing' {$broken.profiles.PSObject.Properties.Remove('legacy-v1')}
  'unknown' {$broken.profiles | Add-Member -NotePropertyName future -NotePropertyValue $broken.profiles.'legacy-v1'}
  'hash' {$broken.profiles.'legacy-v1'.fixture_sha256='a'*64}
  'commit' {$broken.profiles.'legacy-v1'.fixture_commit='a'*40}
  'count' {$broken.profiles.'layered-v1'.expected_cases=@($broken.profiles.'layered-v1'.expected_cases | Select-Object -First 10)}
  'compatibility' {$broken.fixture_sha256=$broken.profiles.'legacy-v1'.fixture_sha256}
 }
 $broken | ConvertTo-Json -Depth 12 | Set-Content $temp
 Reject {Read-UnityConfig $temp 'legacy-v1'} "common config $mutation"
}
Reject {Read-UnityConfig $common 'unknown'} 'unknown requested profile'
Assert-UnityHarnessBuilders $MainRoot 'legacy-v1'
# The reviewed pre-profile modern reference has the old modern-only builder;
# current branch supplies the reviewed dual-profile builder independently.
Assert-UnityHarnessBuilders $currentRoot (Resolve-UnityExecutionProfile $currentRoot committed '' '').profile
Reject {Assert-UnityHarnessBuilders $MainRoot 'layered-v1'} 'historical builder cannot replace modern builder'
$count+=2
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('unity-helper-proof-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $scratch 'Conformance~')
foreach($name in @('Prepare-Harness.ps1','Prepare-PlatformHarness.ps1')){Copy-Item (Join-Path $currentRoot "Conformance~/$name") (Join-Path $scratch "Conformance~/$name")}
$branchProfile=(Resolve-UnityExecutionProfile $currentRoot committed '' '').profile
Assert-UnityHarnessBuilders $scratch $branchProfile
foreach($name in @('Prepare-Harness.ps1','Prepare-PlatformHarness.ps1')) {
 $path=Join-Path $scratch "Conformance~/$name"
 $original=[IO.File]::ReadAllText($path)
 [IO.File]::WriteAllText($path,$original+"`n# changed helper")
 Reject {Assert-UnityHarnessBuilders $scratch $branchProfile} "mutated $name"
 [IO.File]::WriteAllText($path,$original)
}
$count++
"$count profile rejection/classification checks passed."

$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('unity-tooling-boundary-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $temp 'tools';$null=New-Item -ItemType Directory -Path (Join-Path $root '.github') -Force
Copy-Item (Join-Path $source '.github/scripts') (Join-Path $root '.github/scripts') -Recurse
Copy-Item (Join-Path $source '.github/unity-ci.json') (Join-Path $root '.github/unity-ci.json')
'ignored-input' | Set-Content (Join-Path $root '.gitignore')
'original' | Set-Content (Join-Path $root 'sentinel.txt')
& git -C $root init --quiet
& git -C $root add .
& git -C $root -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m 'Synthetic tooling identity only'
if($LASTEXITCODE){throw 'Cannot prepare metadata fixture.'}
$root=[IO.Path]::GetFullPath((git -C $root rev-parse --show-toplevel).Trim())
$sha=(git -C $root rev-parse HEAD).Trim();$config=Join-Path $root '.github/unity-ci.json'
. (Join-Path $root '.github/scripts/UnityContract.ps1')
. (Join-Path $root '.github/scripts/UnityTooling.ps1')
$script:count=0
function Reject([scriptblock]$Action,[string]$Name){try{& $Action|Out-Null}catch{$script:count++;return};throw "Unexpected tooling acceptance: $Name"}
$binding=Resolve-UnityTooling $root $sha $source ('a'*40) $config
Assert-UnityTooling $binding $source ('a'*40)
Reject {Resolve-UnityTooling $source $sha $source ('a'*40) $config} 'different executing root'
Reject {Resolve-UnityTooling $root ('a'*40) $source ('a'*40) $config} 'wrong SHA'
Reject {Resolve-UnityTooling $root 'dev' $source ('a'*40) $config} 'mutable ref'
Reject {Resolve-UnityTooling $root '' $source ('a'*40) $config} 'partial tooling tuple'
Reject {Resolve-UnityTooling $root $sha $source ('a'*40) (Join-Path $source '.github/unity-ci.json')} 'mixed product config'
Reject {Resolve-UnityTooling $root $sha $source ('a'*40) $config $root} 'selected tests as tooling'
'blocked' | Set-Content (Join-Path $root 'ignored-input')
Reject {Resolve-UnityTooling $root $sha $source ('a'*40) $config} 'ignored execution input'
Remove-Item -LiteralPath (Join-Path $root 'ignored-input')
& git -C $root update-index --assume-unchanged sentinel.txt
'changed' | Set-Content (Join-Path $root 'sentinel.txt')
Reject {Resolve-UnityTooling $root $sha $source ('a'*40) $config} 'hidden index mutation'
& git -C $root update-index --no-assume-unchanged sentinel.txt
& git -C $root restore -- sentinel.txt
Add-Content $config ' '
Reject {Assert-UnityTooling $binding $source ('a'*40)} 'config mutation'
& git -C $root restore -- .github/unity-ci.json
Assert-UnityTooling $binding $source ('a'*40)
# Exercise the actual pre-checkout caller binding, without downloading/executing tools.
$lines=Get-Content (Join-Path $source '.github/workflows/_unity-validation.yml');$seen=$false;$collect=$false;$body=@()
foreach($line in $lines){if($line.Trim() -ceq 'id: tooling'){$seen=$true;continue};if($seen -and $line.Trim() -ceq 'run: |'){$collect=$true;continue};if(!$collect){continue};if($line.StartsWith('          ')){$body+=$line.Substring(10)}elseif(!$line.Trim()){$body+=''}else{break}}
$check=[scriptblock]::Create($body -join "`n")
$caller=Join-Path $temp 'caller';$null=New-Item -ItemType Directory -Path (Join-Path $caller '.github/workflows') -Force
$workflow=Join-Path $caller '.github/workflows/unity-ci.yml'
"    uses: cwru-non-academic/Unity_WSS_Integration_Lib/.github/workflows/_unity-validation.yml@$sha" | Set-Content $workflow
& git -C $caller init --quiet;& git -C $caller add .;& git -C $caller -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m 'Synthetic caller only'
$callerSha=(git -C $caller rev-parse HEAD).Trim()
$keys=@('ROLE','WRAPPER_SHA','GITHUB_SHA','GITHUB_REPOSITORY','GITHUB_WORKFLOW_REF','GITHUB_OUTPUT');$old=@{};foreach($k in $keys){$old[$k]=[Environment]::GetEnvironmentVariable($k)}
Push-Location $caller
try {
 $env:ROLE='gui';$env:WRAPPER_SHA='a'*40;$env:GITHUB_SHA=$callerSha;$env:GITHUB_REPOSITORY='cwru-non-academic/GUI_Unity_WSS_Application';$env:GITHUB_WORKFLOW_REF='cwru-non-academic/GUI_Unity_WSS_Application/.github/workflows/unity-ci.yml@refs/heads/dev';$env:GITHUB_OUTPUT=Join-Path $temp 'output'
 & $check
 if(!(Select-String -LiteralPath $env:GITHUB_OUTPUT -SimpleMatch -Pattern "sha=$sha" -Quiet)){throw 'Tooling did not follow literal caller pin.'}
 $candidateLines=Get-Content (Join-Path $source '.github/workflows/_unity-platform-validation.yml');$seen=$false;$collect=$false;$candidateBody=@()
 foreach($line in $candidateLines){if($line.Trim() -ceq 'id: tooling_binding'){$seen=$true;continue};if($seen -and $line.Trim() -ceq 'run: |'){$collect=$true;continue};if(!$collect){continue};if($line.StartsWith('          ')){$candidateBody+=$line.Substring(10)}elseif(!$line.Trim()){$candidateBody+=''}else{break}}
 $candidateCheck=[scriptblock]::Create($candidateBody -join "`n")
 $priorTooling=$env:TOOLING_SHA
 try {$env:TOOLING_SHA=$sha;& $candidateCheck;$env:TOOLING_SHA='b'*40;Reject {& $candidateCheck} 'arbitrary candidate tooling SHA'} finally {$env:TOOLING_SHA=$priorTooling}
 $env:GITHUB_WORKFLOW_REF='cwru-non-academic/GUI_Unity_WSS_Application/.github/workflows/arbitrary.yml@refs/heads/dev'
 Reject {& $check} 'arbitrary caller'
 $env:GITHUB_WORKFLOW_REF='cwru-non-academic/GUI_Unity_WSS_Application/.github/workflows/unity-ci.yml@refs/heads/dev'
 (Get-Content $workflow -Raw).Replace($sha,'dev') | Set-Content $workflow
 Reject {& $check} 'mutable caller pin'
} finally {Pop-Location;foreach($k in $keys){[Environment]::SetEnvironmentVariable($k,$old[$k])}}
"PASS: $count tooling/caller boundary rejections; no application payload executed."

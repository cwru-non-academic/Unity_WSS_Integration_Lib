param([Parameter(Mandatory)][string]$ResultsRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../UnityContract.ps1"
$config=Read-UnityConfig (Join-Path $PSScriptRoot '../../unity-ci.json')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('unity-baseline-evidence-'+[guid]::NewGuid().ToString('N'))
# Synthetic metadata fixtures copied from real results; never acceptance evidence.
$null=New-Item -ItemType Directory -Path $temp
foreach ($sub in @('selected','selected/mandatory-baseline')) {
    $dst=Join-Path $temp $sub
    $null=New-Item -ItemType Directory -Path (Join-Path $dst 'multi') -Force
    foreach ($stage in @('','multi')) {
        foreach ($name in @('evidence.json','results.xml','dotnet.log','projection.json')) {
            Copy-Item -LiteralPath (Join-Path (Join-Path $ResultsRoot $stage) $name) -Destination (Join-Path (Join-Path $dst $stage) $name)
        }
    }
}
$root=Join-Path $temp 'selected'
$single=Get-Content (Join-Path $root 'evidence.json') -Raw | ConvertFrom-Json
foreach ($stage in @('','multi')) {
    $file=Join-Path (Join-Path $root "mandatory-baseline/$stage") 'evidence.json'
    $proof=Get-Content $file -Raw | ConvertFrom-Json
    $proof.test_selection_id='';$proof.test_sha=$proof.wrapper_sha;$proof.test_contract_sha256=''
    $proof | ConvertTo-Json -Depth 12 | Set-Content $file
}
Assert-UnityMultiStageEvidence $root $single $config
$path=Join-Path $root 'mandatory-baseline/evidence.json'
$proof=Get-Content $path -Raw | ConvertFrom-Json
$proof.test_selection_id=('c'*64);$proof | ConvertTo-Json -Depth 12 | Set-Content $path
$rejected=$false;try { Assert-UnityMultiStageEvidence $root $single $config } catch { $rejected=$true }
if (!$rejected) { throw 'Selected tests replaced mandatory baseline.' }
$proof.test_selection_id='';$proof.wrapper_sha=('d'*40);$proof | ConvertTo-Json -Depth 12 | Set-Content $path
$rejected=$false;try { Assert-UnityMultiStageEvidence $root $single $config } catch { $rejected=$true }
if (!$rejected) { throw 'Changed baseline product accepted.' }
Remove-Item -LiteralPath $path
$rejected=$false;try { Assert-UnityMultiStageEvidence $root $single $config } catch { $rejected=$true }
if (!$rejected) { throw 'Missing baseline accepted.' }
Write-Output 'PASS: mandatory baseline binding and three rejection cases (synthetic metadata only).'

param([Parameter(Mandatory)][string]$ResultsRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../UnityContract.ps1"
$config=Read-UnityConfig (Join-Path $PSScriptRoot '../../unity-ci.json')
$single=Get-Content (Join-Path $ResultsRoot 'evidence.json') -Raw | ConvertFrom-Json
Assert-UnityMultiStageEvidence $ResultsRoot $single $config
# Corrupt copies of real local results only; never alter uploaded acceptance files.
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wss-layer-evidence-'+[guid]::NewGuid().ToString('N'))
foreach ($case in @('missing','stage','source','candidate','counts','hash','inventory','projection')) {
    $copy=Join-Path $temporary $case
    $null=New-Item -ItemType Directory -Path (Join-Path $copy 'multi') -Force
    foreach ($name in @('evidence.json','results.xml','dotnet.log','projection.json')) {
        Copy-Item -LiteralPath (Join-Path $ResultsRoot $name) -Destination (Join-Path $copy $name)
        Copy-Item -LiteralPath (Join-Path $ResultsRoot "multi/$name") -Destination (Join-Path $copy "multi/$name")
    }
    $proofPath=Join-Path $copy 'multi/evidence.json'
    $proof=Get-Content $proofPath -Raw | ConvertFrom-Json
    switch ($case) {
        'missing' { Remove-Item -LiteralPath (Join-Path $copy 'multi/dotnet.log') }
        'stage' { $proof.stage='single' }
        'source' { $proof.wrapper_sha=('f'*40) }
        'candidate' { $proof.candidate.artifact_id='999999' }
        'counts' { $proof.skipped=1 }
        'hash' { $proof.results_sha256=('0'*64) }
        'inventory' {
            $xmlPath=Join-Path $copy 'multi/results.xml'
            [xml]$xml=Get-Content $xmlPath -Raw
            $cases=@($xml.SelectNodes('//test-case'))
            $cases[-1].SetAttribute('name',$cases[0].GetAttribute('name'))
            $xml.Save($xmlPath)
            $proof.results_sha256=(Get-FileHash $xmlPath).Hash.ToLowerInvariant()
        }
        'projection' { Add-Content (Join-Path $copy 'multi/projection.json') ' ' }
    }
    $proof | ConvertTo-Json -Depth 12 | Set-Content $proofPath
    $rejected=$false
    try { Assert-UnityMultiStageEvidence $copy $single $config } catch { $rejected=$true }
    if (!$rejected) { throw "Invalid layered evidence accepted: $case" }
}
Write-Output 'PASS: both-stage evidence and eight independent rejection checks; copied metadata only.'

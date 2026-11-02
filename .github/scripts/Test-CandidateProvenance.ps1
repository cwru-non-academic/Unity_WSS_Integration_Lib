param([Parameter(Mandatory)][string]$ProofRoot,[Parameter(Mandatory)][string]$Scratch)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $Scratch) { throw 'Test scratch must be new.' }
New-Item -ItemType Directory -Path $Scratch | Out-Null
$copy=Join-Path $Scratch 'proof'
Copy-Item -LiteralPath $ProofRoot -Destination $copy -Recurse
$e=Get-Content (Join-Path $copy 'evidence.json') -Raw | ConvertFrom-Json
$options=@{ProofRoot=$copy;CandidateJson=($e.candidate|ConvertTo-Json -Depth 8 -Compress);Role=$e.role;WrapperSha=$e.wrapper_sha;GuiSha=$e.gui_sha;RunRepository=$e.run_repository;RunId=[string]$e.run_id;RunSha=$e.run_sha;Destination=(Join-Path $Scratch 'valid')}
& "$PSScriptRoot/Write-CandidateProvenance.ps1" @options
$normalized=Get-Content (Join-Path $options.Destination 'candidate.json') -Raw | ConvertFrom-Json
$keys=@('repository','commit','run_id','artifact_id','archive','sha256')
if (@(Compare-Object $keys @($normalized.PSObject.Properties.Name) -CaseSensitive).Count -ne 0) { throw 'Normalized binding must contain exactly six keys.' }
function Require-Rejection($arguments) {
    $rejected=$false
    try { & "$PSScriptRoot/Write-CandidateProvenance.ps1" @arguments } catch { $rejected=$true }
    if (!$rejected) { throw 'Invalid proof was accepted.' }
    if (Test-Path -LiteralPath $arguments.Destination) { throw 'Rejected proof emitted output.' }
}
$bad=$options.Clone();$bad.Destination=Join-Path $Scratch 'wrong-candidate'
$candidate=$options.CandidateJson | ConvertFrom-Json
$candidate.sha256='0'*64
$bad.CandidateJson=$candidate | ConvertTo-Json -Compress
Require-Rejection $bad
$bad=$options.Clone();$bad.Destination=Join-Path $Scratch 'wrong-source';$bad.GuiSha='0'*40
Require-Rejection $bad
$result=Join-Path $copy 'results.xml';$bytes=[IO.File]::ReadAllBytes($result)
[IO.File]::AppendAllText($result,'<!-- tampered -->')
$bad=$options.Clone();$bad.Destination=Join-Path $Scratch 'corrupt-results'
Require-Rejection $bad
[IO.File]::WriteAllBytes($result,$bytes)
$path=Join-Path $copy 'evidence.json';$original=[IO.File]::ReadAllText($path)
$failed=$original | ConvertFrom-Json;$failed.failed=1
$failed|ConvertTo-Json -Depth 8|Set-Content $path
$bad=$options.Clone();$bad.Destination=Join-Path $Scratch 'failed-suite'
Require-Rejection $bad
[IO.File]::WriteAllText($path,$original)
Write-Output 'PASS: exact six-field binding; wrong candidate/source, corrupted XML and failed suite rejected without output.'

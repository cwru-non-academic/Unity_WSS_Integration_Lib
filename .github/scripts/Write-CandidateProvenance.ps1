param(
    [Parameter(Mandatory)][string]$ProofRoot,
    [Parameter(Mandatory)][string]$CandidateJson,
    [Parameter(Mandatory)][ValidateSet('wrapper','gui')][string]$Role,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$GuiSha,
    [Parameter(Mandatory)][string]$RunRepository,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$RunSha,
    [Parameter(Mandatory)][string]$Destination
)
. "$PSScriptRoot/UnityPromotion.ps1"
if (Test-Path -LiteralPath $Destination) { throw 'Provenance destination must be new.' }
Assert-UnitySha $WrapperSha
Assert-UnitySha $GuiSha
$expectedRepository=if ($Role -ceq 'wrapper') { $UnityWrapperRepository } else { $UnityGuiRepository }
$expectedSha=if ($Role -ceq 'wrapper') { $WrapperSha } else { $GuiSha }
if ($RunRepository -cne $expectedRepository -or $RunSha -cne $expectedSha -or $RunId -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid emitter context.' }
$candidate=$CandidateJson | ConvertFrom-Json
$config=Read-UnityConfig "$PSScriptRoot/../unity-ci.json"
# Reuse the richer proof validator; the caller job additionally depends on the
# entire successful reusable workflow, including all candidate platform jobs.
$e=Assert-UnityEvidenceFiles $ProofRoot $RunRepository $RunId $RunSha $Role $candidate $config
if ($e.wrapper_sha -cne $WrapperSha -or $e.gui_sha -cne $GuiSha) { throw 'Wrong paired source proof.' }
$projection=Get-Content -LiteralPath (Join-Path $ProofRoot 'projection.json') -Raw | ConvertFrom-Json
if (@(Compare-Object $UnityProjectionFiles @($projection.files.source) -CaseSensitive).Count -ne 0) { throw 'Wrong projection inventory.' }
$normalized=[ordered]@{
    repository=[string]$candidate.repository; commit=[string]$candidate.commit
    run_id=[string]$candidate.run_id; artifact_id=[string]$candidate.artifact_id
    archive=[string]$candidate.archive; sha256=[string]$candidate.sha256
}
New-Item -ItemType Directory -Path $Destination | Out-Null
[IO.File]::WriteAllText((Join-Path $Destination 'candidate.json'),($normalized | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output 'PASS: normalized six-field candidate emitted only after richer proof validation.'

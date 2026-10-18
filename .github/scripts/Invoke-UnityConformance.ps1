param(
    [Parameter(Mandatory)][string]$GuiRoot,
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$GuiSha,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$UnityExe,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [ValidateSet('wrapper','gui')][string]$Role='gui',
    [string]$ArtifactRoot='',
    [string]$CandidatePath='',
    [ValidateRange(30,1800)][int]$TimeoutSeconds=240
)
. "$PSScriptRoot/UnityContract.ps1"
$config=Read-UnityConfig $ConfigPath
& "$PSScriptRoot/Assert-UnityPrerequisites.ps1" -ConfigPath $ConfigPath -UnityExe $UnityExe
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new.' }
Assert-UnitySource $GuiRoot $GuiSha -IgnoreSubmodule
Assert-UnitySource $WrapperRoot $WrapperSha
Assert-UnitySource $FixtureRoot $config.fixture_commit
$fixturePath=Join-Path $FixtureRoot 'tests/Wss.CSharpImplementation.Tests/StimulationControllerConformanceTests.cs'
if ((Get-FileHash -LiteralPath $fixturePath).Hash.ToLowerInvariant() -cne $config.fixture_sha256) { throw 'Canonical fixture hash mismatch.' }
if ((Get-Item -LiteralPath $UnityExe).VersionInfo.ProductVersion -notlike "$($config.editor)*") { throw 'Wrong Unity Editor version.' }
if (@(Get-Process Unity -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Another Unity Editor is running; no shared process/project is reused.' }
if (!(Get-Content -LiteralPath (Join-Path $GuiRoot 'ProjectSettings/ProjectVersion.txt') -Raw).Contains("m_EditorVersionWithRevision: $($config.editor) ($($config.revision))")) { throw 'Project Editor/revision mismatch.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
if ($Mode -ceq 'candidate') {
    if (!$ArtifactRoot -or !$CandidatePath) { throw 'Candidate mode requires the resolver output; no fallback.' }
    $candidate=Get-Content -LiteralPath $CandidatePath -Raw | ConvertFrom-Json
    $projectionRoot=Join-Path $OutputRoot 'projection'
    $projection=New-UnityProjection $ArtifactRoot $WrapperRoot $projectionRoot $candidate
} else {
    if ($ArtifactRoot -or $CandidatePath) { throw 'Committed mode cannot accept candidate overrides.' }
    $projection=Get-Content -LiteralPath (Join-Path $WrapperRoot '.github/unity-candidate.json') -Raw | ConvertFrom-Json
    $projectionRoot=Join-Path $WrapperRoot $UnityPluginPath
    Assert-UnityProjection $projectionRoot $projection
    $candidate=$projection.candidate
}
$harness=Join-Path $OutputRoot 'harness'
& (Join-Path $GuiRoot 'tools/UnityConformance/Prepare-Harness.ps1') -CSharpIntegrationRoot $FixtureRoot -Destination $harness -WrapperRoot $WrapperRoot -ProjectionRoot $projectionRoot
if (!$?) { throw 'Harness preparation failed.' }
$adapted=[IO.File]::ReadAllText((Join-Path $harness 'Assets/Tests/Editor/StimulationControllerConformanceTests.cs'))
$canonical=[IO.File]::ReadAllText($fixturePath)
$originalAssertions=@([regex]::Matches($canonical,'Assert\.That\(.*?;','Singleline').Value)
$adaptedAssertions=@([regex]::Matches($adapted,'Assert\.That\(.*?;','Singleline').Value)
if ($originalAssertions.Count -ne 18 -or ($originalAssertions -join "`n") -cne ($adaptedAssertions -join "`n")) { throw 'Canonical eighteen assertion expressions changed.' }
$xmlPath=Join-Path $OutputRoot 'results.xml'; $logPath=Join-Path $OutputRoot 'unity.log'
$arguments=@('-batchmode','-nographics','-projectPath',('"'+$harness+'"'),'-runTests','-testPlatform','EditMode','-testResults',('"'+$xmlPath+'"'),'-logFile',('"'+$logPath+'"'))
$process=Start-Process -FilePath $UnityExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
if (!$process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill(); $process.WaitForExit(); throw 'Disposable conformance process timed out; no promotion evidence emitted.' }
if ($process.ExitCode -ne 0) { throw "Unity exit $($process.ExitCode). Inspect retained unity.log." }
Assert-UnityResults $xmlPath $config
Assert-UnityProjection $projectionRoot $projection
Assert-UnitySource $GuiRoot $GuiSha -IgnoreSubmodule
Assert-UnitySource $WrapperRoot $WrapperSha
$evidence=[ordered]@{
    schema='wss-unity-evidence/v1'; role=$Role; mode=$Mode; candidate=$candidate
    wrapper_sha=$WrapperSha; gui_sha=$GuiSha; fixture_sha=$config.fixture_commit; fixture_sha256=$config.fixture_sha256
    editor=$config.editor; revision=$config.revision; test_framework=$config.test_framework
    run_repository=$env:GITHUB_REPOSITORY; run_id=$env:GITHUB_RUN_ID; run_sha=$env:GITHUB_SHA
    discovered=10; executed=10; passed=10; failed=0; skipped=0; assertions=18
    projection_sha256=$projection.projection_sha256
    results_sha256=(Get-FileHash -LiteralPath $xmlPath).Hash.ToLowerInvariant()
    log_sha256=(Get-FileHash -LiteralPath $logPath).Hash.ToLowerInvariant()
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'evidence.json')
$projection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'projection.json')
Write-Output 'PASS: actual Unity EditMode; ten canonical cases and eighteen unchanged assertion expressions.'

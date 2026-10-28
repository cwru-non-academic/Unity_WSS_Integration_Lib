param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$GuiRoot='',
    [string]$GuiSha='',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [ValidateSet('wrapper','gui')][string]$Role='wrapper',
    [string]$ArtifactRoot='',
    [string]$CandidatePath='',
    [ValidateRange(30,1800)][int]$TimeoutSeconds=300
)
. "$PSScriptRoot/UnityContract.ps1"
$config=Read-UnityConfig $ConfigPath
if ($config.automated_execution -cne 'dotnet' -or $config.dotnet_sdk -cne '9.0.316') { throw 'Unexpected automated execution contract.' }
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be new.' }
Assert-UnitySource $WrapperRoot $WrapperSha
Assert-UnitySource $FixtureRoot $config.fixture_commit
if ($Role -ceq 'gui' -or $Mode -ceq 'candidate') {
    if (!$GuiRoot -or !$GuiSha) { throw 'GUI/candidate validation requires the exact GUI source.' }
    Assert-UnitySource $GuiRoot $GuiSha -IgnoreSubmodule
}
$fixturePath=Join-Path $FixtureRoot 'tests/Wss.CSharpImplementation.Tests/StimulationControllerConformanceTests.cs'
if ((Get-UnityFixtureHash $FixtureRoot) -cne $config.fixture_sha256) { throw 'Canonical fixture hash mismatch.' }
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
& (Join-Path $WrapperRoot 'Conformance~/Prepare-Harness.ps1') -CSharpIntegrationRoot $FixtureRoot -Destination $harness -ProjectionRoot $projectionRoot -Role $Role -GuiRoot $GuiRoot
if (!$?) { throw 'Portable harness preparation failed.' }
Push-Location $harness
try { $sdk=(& dotnet --version).Trim(); if ($LASTEXITCODE -ne 0 -or $sdk -cne $config.dotnet_sdk) { throw 'Wrong .NET SDK.' } } finally { Pop-Location }
$logPath=Join-Path $OutputRoot 'dotnet.log'
$errorPath=Join-Path $OutputRoot 'dotnet-stderr.log'
$nunit=Join-Path $OutputRoot 'nunit'
$arguments=@('test','Wss.DotNet.Conformance.Tests.csproj','--logger','"trx;LogFileName=results.trx"','--results-directory',('"'+(Join-Path $OutputRoot 'test-results')+'"'),'--blame-hang-timeout','2m','--',('NUnit.TestOutputXml="'+$nunit+'"'))
$start=@{ FilePath=(Get-Command dotnet).Source; WorkingDirectory=$harness; ArgumentList=$arguments; RedirectStandardOutput=$logPath; RedirectStandardError=$errorPath; PassThru=$true }
if ($IsWindows) { $start.WindowStyle='Hidden' }
$process=Start-Process @start
if (!$process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill($true); $process.WaitForExit(); throw 'Disposable .NET conformance timed out; no acceptance evidence emitted.' }
if ((Get-Item -LiteralPath $errorPath).Length) { [IO.File]::AppendAllText($logPath,[IO.File]::ReadAllText($errorPath)) }
Get-Content -LiteralPath $logPath | Write-Output
if ($process.ExitCode -ne 0) { throw ".NET test exit $($process.ExitCode). Inspect dotnet.log." }
$results=@(Get-ChildItem -LiteralPath $nunit -Filter '*.xml' -File)
if ($results.Count -ne 1) { throw 'Expected exactly one real NUnit result file.' }
$xmlPath=Join-Path $OutputRoot 'results.xml'
Copy-Item -LiteralPath $results[0].FullName -Destination $xmlPath
Assert-UnityResults $xmlPath $config -DotNet
foreach ($name in @('WSS_Core_Interface.dll','Newtonsoft.Json.dll','System.Security.Permissions.dll')) {
    $binary=Join-Path $harness "bin/Debug/net9.0/$name"
    if ((Get-FileHash -LiteralPath $binary).Hash -cne (Get-FileHash -LiteralPath (Join-Path $projectionRoot $name)).Hash) { throw "Test output used a different payload assembly: $name" }
}
Assert-UnityProjection $projectionRoot $projection
Assert-UnitySource $WrapperRoot $WrapperSha
if ($GuiRoot) { Assert-UnitySource $GuiRoot $GuiSha -IgnoreSubmodule }
$inputs=Get-Content -LiteralPath (Join-Path $harness 'conformance-inputs.json') -Raw | ConvertFrom-Json
if ($inputs.assertion_expressions -ne 18 -or $inputs.canonical_fixture_sha256 -cne $config.fixture_sha256) { throw 'Harness provenance mismatch.' }
$evidence=[ordered]@{
    schema='wss-dotnet-evidence/v1'; execution='dotnet'; role=$Role; mode=$Mode; candidate=$candidate
    wrapper_sha=$WrapperSha; gui_sha=$GuiSha; fixture_sha=$config.fixture_commit; fixture_sha256=$config.fixture_sha256
    sdk=$sdk; target_framework='net9.0'; test_framework='NUnit 3.14.0'; unity_executed=$false
    run_repository=$env:GITHUB_REPOSITORY; run_id=$env:GITHUB_RUN_ID; run_sha=$env:GITHUB_SHA
    discovered=10; executed=10; passed=10; failed=0; skipped=0; assertion_expressions=18
    projection_sha256=$projection.projection_sha256
    results_sha256=(Get-FileHash -LiteralPath $xmlPath).Hash.ToLowerInvariant()
    log_sha256=(Get-FileHash -LiteralPath $logPath).Hash.ToLowerInvariant()
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'evidence.json')
$projection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'projection.json')
Write-Output 'PASS: ordinary .NET through shared production commands; ten canonical cases, eighteen unchanged assertion expressions; Unity was not executed.'

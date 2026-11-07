param(
    $Tests=$null,
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$ProjectionRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('wrapper','gui')][string]$Role='wrapper',
    [string]$GuiRoot=''
)
. "$PSScriptRoot/UnityContract.ps1"
if (Test-Path -LiteralPath $OutputRoot) { throw 'BLE regression output must be new.' }
$null=New-Item -ItemType Directory -Path $OutputRoot
$harness=Join-Path $OutputRoot 'harness'
if ($Tests -and $Tests.selected) {
    & (Get-UnitySelectedTestFile $Tests 'Prepare-Harness.ps1') -WrapperRoot $WrapperRoot -CSharpIntegrationRoot $FixtureRoot -Destination $harness -ProjectionRoot $ProjectionRoot -Role $Role -GuiRoot $GuiRoot -BleLifecycle
} else {
    & "$WrapperRoot/Conformance~/Prepare-Harness.ps1" -CSharpIntegrationRoot $FixtureRoot -Destination $harness -ProjectionRoot $ProjectionRoot -Role $Role -GuiRoot $GuiRoot -BleLifecycle
}
. "$PSScriptRoot/UnityProfiles.ps1"
$profile=Get-WssCapabilityProfile ([WssProfileMetadata]::Read((Join-Path $ProjectionRoot 'WSS_Core_Interface.dll')))
$config=Read-UnityConfig (Join-Path $WrapperRoot '.github/unity-ci.json') $profile
$caseCount=$config.expected_cases.Count
$assertionCount=if($caseCount -eq 10){18}else{20}
Push-Location $harness
try {
    $sdk=(& dotnet --version).Trim()
    if ($sdk -cne $config.dotnet_sdk) { throw 'Wrong SDK for BLE lifecycle regression.' }
    & dotnet test Wss.DotNet.Conformance.Tests.csproj --logger 'trx;LogFileName=results.trx' --results-directory (Join-Path $OutputRoot 'results') --blame-hang-timeout 2m -- "NUnit.TestOutputXml=$(Join-Path $OutputRoot 'nunit')" *> (Join-Path $OutputRoot 'dotnet.log')
    if ($LASTEXITCODE) { throw 'BLE lifecycle regression failed; inspect dotnet.log.' }
} finally { Pop-Location }
$results=@(Get-ChildItem -LiteralPath (Join-Path $OutputRoot 'nunit') -Filter '*.xml')
if ($results.Count -ne 1) { throw 'Expected exact NUnit regression result.' }
[xml]$xml=Get-Content -LiteralPath $results[0].FullName -Raw
$cases=@($xml.SelectNodes('//test-case'))
if ($cases.Count -ne ($caseCount+3) -or @($cases | Where-Object { $_.GetAttribute('result') -cne 'Passed' }).Count) { throw 'All canonical profile and three lifetime regression cases must pass.' }
$canonical=@($cases | Where-Object { $_.GetAttribute('name') -cin $config.dotnet_expected_cases })
if ($canonical.Count -ne $caseCount -or @(Compare-Object $config.dotnet_expected_cases @($canonical | ForEach-Object { $_.GetAttribute('name') }) -CaseSensitive).Count) { throw 'Missing canonical BLE lifecycle scenario.' }
$inputs=Get-Content -LiteralPath (Join-Path $harness 'conformance-inputs.json') -Raw | ConvertFrom-Json
if ($inputs.assertion_expressions -ne $assertionCount) { throw 'Canonical assertions changed.' }
@{schema='wss-ble-lifecycle-regression/v1';role=$Role;execution='dotnet-fake-transport';canonical_cases=$caseCount;assertion_expressions=$assertionCount;lifecycle_cases=3;unity_executed=$false;native_ble_executed=$false;hardware_access=$false} | ConvertTo-Json | Set-Content (Join-Path $OutputRoot 'regression.json')
Write-Output "PASS: $caseCount canonical cases through the BLE lifetime adapter, plus three cancellation/bytes/disposal cases; fake transport only."

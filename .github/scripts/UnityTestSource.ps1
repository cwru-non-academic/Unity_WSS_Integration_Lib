# Trusted product boundary; frozen selection authorization belongs to Core bootstrap.
function Read-UnityTestContract([string]$Path) {
    $value=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $canonical=ConvertFrom-Json '{"schema":"wss-unity-tests/v1","fixture_repository":"cwru-non-academic/CSharp_WSS_Integration_Lib","fixture_commit":"fc427c5b8bc6534a7d02f00283830072572aa03a","fixture_sha256":"96812ab33be7ede8840ddb78131a50796fd3f797d9627f958251b3e58796baf8","expected_cases":["AnalogStimulationThroughCSharpImplementationPassesCoreConformance","InitializationThroughCSharpImplementationPassesCoreConformance","NormalizedScenario(\"normalized.minus-0.2\")","NormalizedScenario(\"normalized.0.0\")","NormalizedScenario(\"normalized.0.37\")","NormalizedScenario(\"normalized.0.5\")","NormalizedScenario(\"normalized.1.0\")","NormalizedScenario(\"normalized.1.2\")","RuntimeEventEditThroughCSharpImplementationResumesConformantStreaming","StopStimulationThroughCSharpImplementationDoesNotResumeStreaming","StimulationSequence(\"analog.multichannel-isolation\")","StimulationSequence(\"normalized.multichannel-isolation\")","StimulationSequence(\"modeled.p.pw.single\")","StimulationSequence(\"modeled.p.pa.single\")","StimulationSequence(\"modeled.pd.pw.single\")","StimulationSequence(\"modeled.pd.pa.single\")"],"dotnet_expected_cases":["AnalogStimulationThroughCSharpImplementationPassesCoreConformance","InitializationThroughCSharpImplementationPassesCoreConformance","normalized.minus-0.2","normalized.0.0","normalized.0.37","normalized.0.5","normalized.1.0","normalized.1.2","RuntimeEventEditThroughCSharpImplementationResumesConformantStreaming","StopStimulationThroughCSharpImplementationDoesNotResumeStreaming","analog.multichannel-isolation","normalized.multichannel-isolation","modeled.p.pw.single","modeled.p.pa.single","modeled.pd.pw.single","modeled.pd.pa.single"],"multidevice_expected_cases":["analog.multidevice-isolation","normalized.multidevice-isolation","modeled.p.pw.multi","modeled.p.pa.multi","modeled.pd.pw.multi","modeled.pd.pa.multi"]}'
    if (@(Compare-Object @($canonical.PSObject.Properties.Name) @($value.PSObject.Properties.Name) -CaseSensitive).Count) { throw 'Selected contract contains product or unexpected fields.' }
    Assert-UnitySha $value.fixture_commit
    foreach ($field in @('schema','fixture_repository','fixture_sha256','expected_cases','dotnet_expected_cases','multidevice_expected_cases')) {
        if (($value.$field -join "`n") -cne ($canonical.$field -join "`n")) { throw "Selected tests weaken canonical contract: $field" }
    }
    $value
}
function Assert-UnityTestSource($Tests) {
    Assert-UnitySource $Tests.root $Tests.sha -IgnoreSubmodule
    $top=[IO.Path]::GetFullPath((Invoke-UnityGit $Tests.root @('rev-parse','--show-toplevel')).Trim())
    if ($top -cne $Tests.root) { throw 'TestRoot must be checkout root.' }
    if (@(Invoke-UnityGit $Tests.root @('status','--porcelain','--untracked-files=all','--ignored','--','conformance')).Count) { throw 'Selected bundle must be clean, including ignored files.' }
    if ($Tests.contract_sha256 -and (Get-FileHash -LiteralPath (Join-Path $Tests.root 'conformance/test-contract.json')).Hash.ToLowerInvariant() -cne $Tests.contract_sha256) { throw 'Test contract changed during execution.' }
    if ($Tests.selected) {
        foreach ($item in @(Get-Item -LiteralPath $Tests.root)+@(Get-ChildItem -LiteralPath (Join-Path $Tests.root 'conformance') -Recurse -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Selected bundle cannot contain filesystem links.' }
        }
    }
}
function Resolve-UnityTestSource([string]$WrapperRoot,[string]$WrapperSha,[string]$ConfigPath,[string]$Role='wrapper',[string]$GuiRoot='',[string]$GuiSha='',[string]$TestRoot='',[string]$TestSha='',[string]$TestRepository='',[string]$TestSelectionId='',[ValidateSet('legacy-v1','layered-v1')][string]$Profile='layered-v1',[string]$ToolRoot='') {
    $explicit=[bool]($TestRoot -or $TestSha -or $TestRepository -or $TestSelectionId)
    $product=Read-UnityConfig $ConfigPath $Profile
    if ($explicit) {
        if (!$TestRoot -or !$TestSha -or !$TestRepository -or !$TestSelectionId) { throw 'TestRoot, TestSha, TestRepository and TestSelectionId required together.' }
        Assert-UnitySha $TestSha
        $expected=if ($Role -ceq 'gui') { 'cwru-non-academic/GUI_Unity_WSS_Application' } else { 'cwru-non-academic/Unity_WSS_Integration_Lib' }
        if ($TestRepository -cne $expected -or $TestSelectionId -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid immutable test selection binding.' }
        if ((!$ToolRoot -or [IO.Path]::GetFullPath($ConfigPath) -cne [IO.Path]::GetFullPath((Join-Path $ToolRoot '.github/unity-ci.json'))) -and [IO.Path]::GetFullPath($ConfigPath) -cne [IO.Path]::GetFullPath((Join-Path $WrapperRoot '.github/unity-ci.json')) -and
            (!$GuiRoot -or [IO.Path]::GetFullPath($ConfigPath) -cne [IO.Path]::GetFullPath((Join-Path $GuiRoot '.github/unity-ci.json')))) { throw 'Product config must remain in a product checkout.' }
        if ($product.baseline_ready -cne $true) { throw 'Selected tests cannot override product readiness.' }
    } else {
        $TestRoot=$WrapperRoot; $TestSha=$WrapperSha; $TestRepository='cwru-non-academic/Unity_WSS_Integration_Lib'
    }
    $result=[pscustomobject]@{root=[IO.Path]::GetFullPath($TestRoot);sha=$TestSha;repository=$TestRepository;selection_id=$TestSelectionId;selected=$explicit;contract_sha256='';contract=$product}
    Assert-UnityTestSource $result
    if ($explicit) {
        $path=Join-Path $result.root 'conformance/test-contract.json'
        $result.contract=Read-UnityTestContract $path
        $result.contract_sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    }
    $result
}
function Get-UnitySelectedTestFile($Tests,[string]$Name) {
    if (!$Tests.selected -or $Name -cnotin @('Prepare-Harness.ps1','Prepare-UnityHarness.ps1')) { throw 'Only allowlisted selected test entry points may execute.' }
    $path=Join-Path $Tests.root "conformance/$Name"
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing selected test entry point: $Name" }
    $path
}

param([string]$GuiBundleRoot='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../UnityContract.ps1"
. "$PSScriptRoot/../UnityTestSource.ps1"
$product=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('unity-test-selection-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
function Reject([scriptblock]$Action,[string]$Label) {
    $rejected=$false
    try { & $Action | Out-Null } catch { $rejected=$true }
    if (!$rejected) { throw "Expected rejection: $Label" }
    Write-Output "PASS reject: $Label"
}
function Fixture([string]$From,[string]$Name) {
    $root=Join-Path $scratch $Name
    $null=New-Item -ItemType Directory -Path $root
    Copy-Item -LiteralPath (Join-Path $From 'conformance') -Destination $root -Recurse
    Add-Content (Join-Path $root 'conformance/Stimulation.DotNet.cs') '// independently selected test revision'
    & git -C $root init -q
    & git -C $root add .
    & git -C $root -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    if ($LASTEXITCODE) { throw 'Cannot create fixture commit.' }
    $root
}
$root=Fixture $product 'wrapper-tests'
$sha=(& git -C $root rev-parse HEAD).Trim()
$args=@{WrapperRoot=$product;WrapperSha=('a'*40);ConfigPath=(Join-Path $product '.github/unity-ci.json');TestRoot=$root;TestSha=$sha;TestRepository=$UnityWrapperRepository;TestSelectionId=('b'*64)}
$tests=Resolve-UnityTestSource @args
if ($tests.root -ceq $product -or $tests.sha -ceq $args.WrapperSha) { throw 'Selection did not remain independent.' }
if ((Get-UnitySelectedTestFile $tests 'Prepare-Harness.ps1') -cne (Join-Path $root 'conformance/Prepare-Harness.ps1')) { throw 'Selected entry point not used.' }
Reject { Get-UnitySelectedTestFile $tests '../.github/scripts/Write-ReleaseReceipt.ps1' } 'release validator selection'
$bad=$args.Clone(); $bad.TestSelectionId=''; Reject { Resolve-UnityTestSource @bad } 'partial selection'
$bad=$args.Clone(); $bad.TestSha=('c'*40); Reject { Resolve-UnityTestSource @bad } 'wrong SHA'
$bad=$args.Clone(); $bad.TestRepository=$UnityGuiRepository; Reject { Resolve-UnityTestSource @bad } 'wrong repository role'
$bad=$args.Clone(); $bad.ConfigPath=Join-Path $root 'conformance/test-contract.json'; Reject { Resolve-UnityTestSource @bad } 'selected product config'
$path=Join-Path $root 'conformance/test-contract.json'
$original=Get-Content $path -Raw
$value=$original | ConvertFrom-Json
$value.dotnet_expected_cases=@($value.dotnet_expected_cases | Select-Object -SkipLast 1)
$value | ConvertTo-Json -Depth 8 | Set-Content $path
Reject { Read-UnityTestContract $path } 'missing canonical case'
Set-Content $path $original -NoNewline
$value=$original | ConvertFrom-Json; $value | Add-Member baseline_ready $true
$value | ConvertTo-Json -Depth 8 | Set-Content $path
Reject { Read-UnityTestContract $path } 'product readiness injection'
Set-Content $path $original -NoNewline
Add-Content (Join-Path $root 'conformance/Stimulation.DotNet.cs') '// dirty'
Reject { Resolve-UnityTestSource @args } 'dirty selected test source'
# Verify builders retain explicit production inputs even when located elsewhere.
foreach ($name in @('Prepare-Harness.ps1','Prepare-PlatformHarness.ps1')) {
    $body=Get-Content (Join-Path $root "conformance/$name") -Raw
    if (!$body.Contains('$wrapper=[IO.Path]::GetFullPath($WrapperRoot)') -or $body.Contains("Join-Path `$PSScriptRoot '..'")) { throw 'Selected builder changes product root.' }
}
if ($GuiBundleRoot) {
    $gui=Fixture $GuiBundleRoot 'gui-tests'; $gsha=(& git -C $gui rev-parse HEAD).Trim()
    $ga=$args.Clone(); $ga.TestRoot=$gui; $ga.TestSha=$gsha; $ga.TestRepository=$UnityGuiRepository; $ga.Role='gui'; $ga.GuiRoot=$GuiBundleRoot; $ga.GuiSha=('d'*40)
    $gt=Resolve-UnityTestSource @ga
    $null=Get-UnitySelectedTestFile $gt 'Prepare-UnityHarness.ps1'
    $body=Get-Content (Join-Path $gui 'conformance/Prepare-UnityHarness.ps1') -Raw
    if (!$body.Contains('$appRoot = [IO.Path]::GetFullPath($GuiRoot)')) { throw 'Selected GUI builder changes product root.' }
}
Write-Output "PASS: independent wrapper/GUI source, immutable bindings, canonical inventory, product paths and validator boundary. Fixtures retained at $scratch"

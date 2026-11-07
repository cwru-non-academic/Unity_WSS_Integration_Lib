$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$bridge=Join-Path $root '.github/scripts/Invoke-SelectedUnityTests.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($bridge,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Bridge parse failure.' }
$body=Get-Content $bridge -Raw
foreach ($required in @('inspect $TargetId $ContextPath $rootsPath','evidence $TargetId $ContextPath $rootsPath','Assert-UnitySource $CoreToolsRoot $lock.source_commit','$env:GITHUB_SHA -cne $ownSha','$env:WSS_TEST_SELECTION_ID')) {
    if (!$body.Contains($required)) { throw "Missing selection boundary: $required" }
}
if ($body.IndexOf('inspect $TargetId') -ge $body.IndexOf('Invoke-CredentialFreeSelectedPowerShell (Join-Path $PSScriptRoot $runner)') -or $body.IndexOf('evidence $TargetId') -le $body.IndexOf('Invoke-CredentialFreeSelectedPowerShell (Join-Path $PSScriptRoot $runner)')) { throw 'Inspect/suites/evidence order changed.' }
$old=$env:GITHUB_ACTIONS
try {
    $env:GITHUB_ACTIONS='false';$rejected=$false
    try { & $bridge -TargetId unity-wrapper -ContextPath missing -CoreToolsRoot missing -TestRoot missing -WrapperRoot missing -WrapperSha ('a'*40) -FixtureRoot missing -ConfigPath missing -OutputRoot missing -BindingOutputRoot missing } catch {
        if ($_.Exception.Message -notlike '*actual GitHub identity*') { throw }
        $rejected=$true
    }
    if (!$rejected) { throw 'Non-GitHub bridge invocation accepted.' }
} finally { $env:GITHUB_ACTIONS=$old }
$fragment=Get-Content (Join-Path $root '.github/selection-adoption/unity-selection.fragment.yml') -Raw
foreach ($required in @('WSS_TEST_SELECTION_ID: ${{ needs.prerequisites.outputs.selection_id }}','ref: ${{ needs.prerequisites.outputs.test_commit }}','path: selected-tests','wss-selected-tests-${{ steps.select_tests.outputs.target_id }}-a${{ github.run_attempt }}')) {
    if (!$fragment.Contains($required)) { throw "Missing frozen workflow binding: $required" }
}
Write-Output 'PASS: inactive bridge parse, inspect/suite/evidence order, immutable workflow bindings, and rejection of unauthenticated execution. No suite or external action executed.'

$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$lines=Get-Content (Join-Path $root '.github/workflows/_unity-validation.yml')
$seen=$false; $collect=$false; $body=@()
foreach ($line in $lines) {
    if ($line.Trim() -ceq 'id: sources') { $seen=$true; continue }
    if ($seen -and $line.Trim() -ceq 'run: |') { $collect=$true; continue }
    if (!$collect) { continue }
    if ($line.StartsWith('          ')) { $body+=$line.Substring(10) }
    elseif (!$line.Trim()) { $body+=''; continue }
    else { break }
}
if (!$body.Count) { throw 'Actual candidate readiness workflow block not found.' }
$check=[scriptblock]::Create($body -join "`n")
$temp=Join-Path ([IO.Path]::GetTempPath()) ('wss-candidate-readiness-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $temp '.github'),(Join-Path $temp 'candidate-contract/.github') -Force
$keys=@('MODE','ROLE','WRAPPER_SHA','CLI_SHA','GUI_SHA','GITHUB_SHA','GITHUB_REF','GITHUB_OUTPUT')
$previous=@{}; foreach ($key in $keys) { $previous[$key]=[Environment]::GetEnvironmentVariable($key) }
Push-Location $temp
try {
    foreach ($case in @('valid','own-execution','own-sdk','own-opt-out','wrapper-opt-out','source-mismatch','mutable-wrapper')) {
        $own=Get-Content (Join-Path $root '.github/unity-ci.json') -Raw | ConvertFrom-Json
        $candidate=$own | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $own.baseline_ready=$true; $candidate.baseline_ready=$true
        # Applications may still run their exact legacy ordinary case inventory.
        $own.dotnet_expected_cases=@($own.dotnet_expected_cases | Select-Object -First 10)
        $env:MODE='candidate'; $env:ROLE='gui'; $env:WRAPPER_SHA=('a'*40)
        $env:CLI_SHA=('b'*40); $env:GUI_SHA=('b'*40); $env:GITHUB_SHA=('b'*40)
        $env:GITHUB_REF='refs/heads/dev'; $env:GITHUB_OUTPUT=Join-Path $temp ($case+'.outputs')
        switch ($case) {
            'own-execution' { $own.automated_execution='unsupported' }
            'own-sdk' { $own.dotnet_sdk='9.0.999' }
            'own-opt-out' { $own.baseline_ready=$false }
            'wrapper-opt-out' { $candidate.baseline_ready=$false }
            'source-mismatch' { $env:GITHUB_SHA=('c'*40) }
            'mutable-wrapper' { $env:WRAPPER_SHA='dev' }
            'main-opt-out' { $own.channels=@('dev'); $env:GITHUB_REF='refs/heads/main' }
        }
        $own | ConvertTo-Json -Depth 12 | Set-Content '.github/unity-ci.json'
        $candidate | ConvertTo-Json -Depth 12 | Set-Content 'candidate-contract/.github/unity-ci.json'
        $rejected=$false
        try { & $check | Out-Null } catch { $rejected=$true }
        if ($rejected -eq ($case -ceq 'valid')) { throw "Candidate readiness outcome differs: $case" }
        if ($case -ceq 'valid' -and !(Select-String -LiteralPath $env:GITHUB_OUTPUT -SimpleMatch "fixture=$($candidate.fixture_commit)" -Quiet)) { throw 'Candidate fixture was not selected from the exact wrapper contract.' }
    }
} finally {
    Pop-Location
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key]) }
}
Write-Output 'PASS: actual candidate workflow retains application/wrapper opt-in and immutable source gates; metadata only.'

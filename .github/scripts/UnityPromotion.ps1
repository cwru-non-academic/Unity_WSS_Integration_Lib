. "$PSScriptRoot/UnityContract.ps1"

function Wait-UnityRun([string]$Repository,[string]$RunId,[string]$Sha,[string]$Workflow,[string]$Event,[int]$TimeoutSeconds=2400) {
    Assert-UnitySha $Sha
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $run=Invoke-UnityGh @('api',"repos/$Repository/actions/runs/$RunId") | ConvertFrom-Json
        if ($run.repository.full_name -cne $Repository -or $run.path -cne ".github/workflows/$Workflow" -or $run.head_sha -cne $Sha -or $run.event -cne $Event) { throw 'Workflow run identity mismatch.' }
        if ($run.status -ceq 'completed') {
            if ($run.conclusion -cne 'success') { throw 'Required workflow did not succeed; never substitute another green run.' }
            return $run
        }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for exact workflow.' }
        Start-Sleep -Seconds 15
    } while ($true)
}
function Assert-UnityProducer($Candidate) {
    Assert-UnityCandidate $Candidate
    $run=Wait-UnityRun $Candidate.repository $Candidate.run_id $Candidate.commit 'artifacts.yml' 'push'
    if ($run.head_branch -cne 'dev' -or $run.head_repository.full_name -cne $Candidate.repository -or $Candidate.archive -cne 'WSS-Universal-ci.zip') { throw 'Automatic Unity propagation requires the canonical Core dev push archive.' }
    $compare=Invoke-UnityGh @('api',"repos/$($Candidate.repository)/compare/$($Candidate.commit)...dev") | ConvertFrom-Json
    if ($compare.status -cnotin @('ahead','identical')) { throw 'Producer commit is not contained in Core dev.' }
    $pages=Invoke-UnityGh @('api','--paginate','--slurp',"repos/$($Candidate.repository)/actions/runs/$($Candidate.run_id)/jobs?per_page=100&filter=latest") | ConvertFrom-Json
    $jobs=@($pages | ForEach-Object { $_.jobs })
    foreach ($name in @('Build and validate artifacts','Core conformance','Serial consumer (Windows)','Serial consumer (macOS)','Serial consumer (Linux)','BLE consumer (Windows)','BLE consumer (Linux)','Build macOS universal BLE bridge','BLE consumer (macOS x86_64)','BLE consumer (macOS arm64)','Core consumer (Windows)','Core consumer (macOS)','Core consumer (Linux)','Start routine downstream validation')) {
        $matching=@($jobs | Where-Object { $_.name -ceq $name })
        if ($matching.Count -ne 1 -or $matching[0].conclusion -cne 'success') { throw "Required Core producer job missing/skipped/failed: $name" }
    }
    $artifact=Invoke-UnityGh @('api',"repos/$($Candidate.repository)/actions/artifacts/$($Candidate.artifact_id)") | ConvertFrom-Json
    if ($artifact.expired -or $artifact.name -cne 'universal-release-assets' -or [string]$artifact.workflow_run.id -cne [string]$Candidate.run_id -or $artifact.workflow_run.head_sha -cne $Candidate.commit) { throw 'Wrong/expired producer artifact.' }
}
function Get-UnityHead([string]$Repository) {
    $branch=Invoke-UnityGh @('api',"repos/$Repository/branches/dev") | ConvertFrom-Json
    Assert-UnitySha $branch.commit.sha
    $branch.commit.sha
}
function Start-UnityPreflight([string]$Repository,$Candidate,[string]$WrapperSha,[string]$GuiSha) {
    Assert-UnitySha $WrapperSha
    Assert-UnitySha $GuiSha
    $correlation="wss-$($Candidate.run_id)-$($Candidate.artifact_id)-$WrapperSha-$GuiSha"
    $title="WSS preflight $($Candidate.run_id) / $correlation"
    function Find-Run {
        $pages=Invoke-UnityGh @('api','--paginate','--slurp',"repos/$Repository/actions/workflows/wss-preflight.yml/runs?event=workflow_dispatch&per_page=100") | ConvertFrom-Json
        $runs=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { $_.display_title -ceq $title })
        if ($runs.Count -gt 1) { throw 'Ambiguous correlated preflight; no run selection or redispatch.' }
        if ($runs.Count -eq 1) { return $runs[0] }
    }
    $found=Find-Run
    if (!$found) {
        $body=@{ ref='dev'; inputs=@{ candidate_json=($Candidate | ConvertTo-Json -Depth 5 -Compress); wrapper_sha=$WrapperSha; gui_sha=$GuiSha; correlation_id=$correlation } } | ConvertTo-Json -Depth 5 -Compress
        if (!$env:UNITY_PREFLIGHT_TOKEN) { throw 'Scoped downstream Actions-write token required.' }
        $readToken=$env:GH_TOKEN
        try {
            $env:GH_TOKEN=$env:UNITY_PREFLIGHT_TOKEN
            $body | & gh api --method POST "repos/$Repository/actions/workflows/wss-preflight.yml/dispatches" --input -
            if ($LASTEXITCODE -ne 0) { throw 'Preflight dispatch failed/uncertain. Inspect before any retry.' }
        } finally { $env:GH_TOKEN=$readToken }
        $deadline=[DateTime]::UtcNow.AddSeconds(180)
        do {
            $found=Find-Run
            if ($found) { break }
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Dispatched preflight not discovered; inspect before retrying.' }
            Start-Sleep -Seconds 5
        } while ($true)
    }
    $expectedSha=if ($Repository -ceq $UnityWrapperRepository) { $WrapperSha } else { $GuiSha }
    if ($found.head_sha -cne $expectedSha) { throw 'Correlated preflight source changed; no automatic redispatch.' }
    Wait-UnityRun $Repository ([string]$found.id) $expectedSha 'wss-preflight.yml' 'workflow_dispatch'
}
function Read-UnityApproval([string]$Path) {
    $value=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($value.schema -cne 'wss-unity-promotion/v1') { throw 'Unity-specific approval schema required.' }
    Assert-UnityCandidate $value.candidate
    foreach ($role in @('wrapper','gui')) {
        Assert-UnitySha $value.$role.source_sha
        if ([string]$value.$role.preflight_run_id -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid preflight run ID.' }
    }
    Assert-UnitySha $value.fixture.commit
    if ($value.fixture.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $value.projection_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid evidence digest.' }
    [pscustomobject][ordered]@{
        schema='wss-unity-promotion/v1'
        candidate=[ordered]@{ repository=$value.candidate.repository; commit=$value.candidate.commit; run_id=[string]$value.candidate.run_id; artifact_id=[string]$value.candidate.artifact_id; archive=$value.candidate.archive; sha256=$value.candidate.sha256 }
        wrapper=[ordered]@{source_sha=$value.wrapper.source_sha;preflight_run_id=[string]$value.wrapper.preflight_run_id}
        gui=[ordered]@{source_sha=$value.gui.source_sha;preflight_run_id=[string]$value.gui.preflight_run_id}
        fixture=[ordered]@{commit=$value.fixture.commit;sha256=$value.fixture.sha256}
        projection_sha256=$value.projection_sha256
    }
}
function Get-UnityApprovalMarker($Approval) {
    '<!-- wss-unity-approval:'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Approval | ConvertTo-Json -Depth 8 -Compress)))+' -->'
}
function Read-UnityApprovalMarker([string]$Body,[string]$Destination) {
    $matches=[regex]::Matches($Body,'(?m)^<!-- wss-unity-approval:([A-Za-z0-9+/=]+) -->\r?$')
    if ($matches.Count -ne 1 -or [regex]::Matches($Body,'<!-- wss-unity-approval:').Count -ne 1) { throw 'Missing/ambiguous Unity approval marker.' }
    [IO.File]::WriteAllText($Destination,[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($matches[0].Groups[1].Value)))
    $approval=Read-UnityApproval $Destination
    if ((Get-UnityApprovalMarker $approval) -cne $matches[0].Value.TrimEnd("`r")) { throw 'Noncanonical approval marker.' }
    $approval
}
function Get-UnityEvidence([string]$Repository,[string]$RunId,[string]$SourceSha,[string]$Role,$Candidate,[string]$Root,$Config) {
    $null=Wait-UnityRun $Repository $RunId $SourceSha 'wss-preflight.yml' 'workflow_dispatch'
    $pages=Invoke-UnityGh @('api','--paginate','--slurp',"repos/$Repository/actions/runs/$RunId/jobs?per_page=100") | ConvertFrom-Json
    $requiredName=if ($Role -ceq 'wrapper') { 'Preflight behavioral tests' } else { 'GUI general conformance' }
    $required=@($pages | ForEach-Object { $_.jobs } | Where-Object { $_.name -ceq $requiredName })
    if ($required.Count -ne 1 -or $required[0].conclusion -cne 'success') { throw 'Required candidate acceptance job missing/skipped/failed.' }
    foreach ($platform in @('Windows','Ubuntu','macOS')) {
        $matching=@($pages | ForEach-Object { $_.jobs } | Where-Object { ($_.name -split ' / ')[-1] -ceq "Preflight platform compatibility ($platform)" })
        if ($matching.Count -ne 1 -or $matching[0].conclusion -cne 'success') { throw "Candidate platform validation missing/skipped/failed: $platform" }
    }
    if (Test-Path -LiteralPath $Root) { throw 'Evidence download destination must be new.' }
    $null=Invoke-UnityGh @('run','download',$RunId,'--repo',$Repository,'--name','unity-preflight-evidence','--dir',$Root)
    $files=@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object @('evidence.json','results.xml','dotnet.log','projection.json') $files -CaseSensitive).Count -ne 0) { throw 'Unexpected/incomplete preflight artifact.' }
    $e=Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
    Assert-UnitySameCandidate $e.candidate $Candidate
    $expectedRunSha=if ($Role -ceq 'wrapper') { $e.wrapper_sha } else { $e.gui_sha }
    if ($e.schema -cne 'wss-dotnet-evidence/v1' -or $e.execution -cne 'dotnet' -or $e.unity_executed -cne $false -or $e.role -cne $Role -or $e.mode -cne 'candidate' -or $e.run_repository -cne $Repository -or
        [string]$e.run_id -cne $RunId -or $e.run_sha -cne $SourceSha -or $expectedRunSha -cne $SourceSha -or
        $e.fixture_sha -cne $Config.fixture_commit -or $e.fixture_sha256 -cne $Config.fixture_sha256 -or
        $e.sdk -cne $Config.dotnet_sdk -or $e.target_framework -cne 'net9.0' -or $e.test_framework -cne 'NUnit 3.14.0' -or
        $e.discovered -ne 10 -or $e.executed -ne 10 -or $e.passed -ne 10 -or $e.failed -ne 0 -or $e.skipped -ne 0 -or $e.assertion_expressions -ne 18) { throw 'Invalid runtime/source/fixture evidence.' }
    foreach ($pair in @(@('results.xml','results_sha256'),@('dotnet.log','log_sha256'))) {
        if ((Get-FileHash -LiteralPath (Join-Path $Root $pair[0])).Hash.ToLowerInvariant() -cne $e.($pair[1])) { throw 'Evidence content hash mismatch.' }
    }
    Assert-UnityResults (Join-Path $Root 'results.xml') $Config -DotNet
    $projection=Get-Content -LiteralPath (Join-Path $Root 'projection.json') -Raw | ConvertFrom-Json
    Assert-UnitySameCandidate $projection.candidate $Candidate
    if ($projection.schema -cne 'wss-unity-projection/v1' -or (Get-UnityProjectionDigest $projection.files) -cne $e.projection_sha256 -or
        $projection.projection_sha256 -cne $e.projection_sha256) { throw 'Projection/evidence mismatch.' }
    $e
}
function Assert-UnityApproval($Approval,[string]$EvidenceRoot,$Config) {
    Assert-UnityProducer $Approval.candidate
    foreach ($role in @('wrapper','gui')) {
        $repo=if ($role -ceq 'wrapper') { $UnityWrapperRepository } else { $UnityGuiRepository }
        $e=Get-UnityEvidence $repo $Approval.$role.preflight_run_id $Approval.$role.source_sha $role $Approval.candidate (Join-Path $EvidenceRoot $role) $Config
        if ($e.wrapper_sha -cne $Approval.wrapper.source_sha -or $e.gui_sha -cne $Approval.gui.source_sha -or
            $e.projection_sha256 -cne $Approval.projection_sha256 -or $e.fixture_sha -cne $Approval.fixture.commit -or
            $e.fixture_sha256 -cne $Approval.fixture.sha256) { throw 'Preflights did not test the same source/candidate tuple.' }
    }
}
function Assert-UnityMergedGuiPreflight($Approval,[string]$WrapperSha,[string]$GuiSha,[string]$RunId,[string]$Root,$Config) {
    Assert-UnitySha $WrapperSha
    Assert-UnitySha $GuiSha
    if ($RunId -cnotmatch '^[1-9][0-9]*$') { throw 'Exact merged-wrapper GUI preflight ID required.' }
    $e=Get-UnityEvidence $UnityGuiRepository $RunId $GuiSha 'gui' $Approval.candidate $Root $Config
    if ($e.wrapper_sha -cne $WrapperSha -or $e.gui_sha -cne $GuiSha -or $e.projection_sha256 -cne $Approval.projection_sha256 -or
        $e.fixture_sha -cne $Approval.fixture.commit -or $e.fixture_sha256 -cne $Approval.fixture.sha256) { throw 'GUI preflight did not test the exact accepted merged wrapper and current GUI source.' }
}
function Get-UnityGuiPreflightMarker([string]$WrapperSha,[string]$GuiSha,[string]$RunId) {
    Assert-UnitySha $WrapperSha
    Assert-UnitySha $GuiSha
    if ($RunId -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid GUI preflight ID.' }
    $record=[ordered]@{wrapper_sha=$WrapperSha;gui_sha=$GuiSha;preflight_run_id=$RunId} | ConvertTo-Json -Compress
    '<!-- wss-unity-gui-preflight:v1 '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($record))+' -->'
}
function Assert-UnityRemoteProjection([string]$Sha,$Record) {
    Assert-UnitySha $Sha
    if ($Record.schema -cne 'wss-unity-projection/v1' -or (Get-UnityProjectionDigest $Record.files) -cne $Record.projection_sha256 -or
        @(Compare-Object $UnityProjectionFiles @($Record.files.source) -CaseSensitive).Count) { throw 'Invalid merged projection inventory/digest.' }
    $tree=Invoke-UnityGh @('api',"repos/$UnityWrapperRepository/git/trees/${Sha}?recursive=1") | ConvertFrom-Json
    if ($tree.truncated) { throw 'Merged wrapper tree response is truncated.' }
    $dlls=@($tree.tree | Where-Object { $_.path.StartsWith($UnityPluginPath+'/',[StringComparison]::Ordinal) -and ($_.path.EndsWith('.dll',[StringComparison]::Ordinal) -or $_.path.EndsWith('.so',[StringComparison]::Ordinal) -or $_.path.EndsWith('.dylib',[StringComparison]::Ordinal)) } | ForEach-Object { $_.path })
    $expected=@($UnityProjectionFiles | ForEach-Object { "$UnityPluginPath/$(Get-UnityProjectionPath $_)" })
    if (@(Compare-Object $expected $dlls -CaseSensitive).Count) { throw 'Merged wrapper has extra/missing payload DLLs.' }
    foreach ($file in $Record.files) {
        foreach ($suffix in @('','.meta')) {
            $path="$UnityPluginPath/$(Get-UnityProjectionPath $file.source)$suffix"
            $entries=@($tree.tree | Where-Object { $_.path -ceq $path -and $_.type -ceq 'blob' })
            if ($entries.Count -ne 1) { throw "Merged payload path missing/ambiguous: $path" }
            $blob=Invoke-UnityGh @('api',"repos/$UnityWrapperRepository/git/blobs/$($entries[0].sha)") | ConvertFrom-Json
            if ($blob.encoding -cne 'base64') { throw 'Unsupported merged blob encoding.' }
            $bytes=[Convert]::FromBase64String($blob.content)
            if ($suffix) {
                $reader=[IO.StreamReader]::new([IO.MemoryStream]::new($bytes),[Text.Encoding]::UTF8,$true)
                try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }
                $bytes=[Text.Encoding]::UTF8.GetBytes($text.Replace("`r`n","`n"))
            }
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            $expectedHash=if ($suffix) { $file.meta_sha256 } else { $file.sha256 }
            if ($hash -cne $expectedHash) { throw "Actual merged payload differs from accepted evidence: $path" }
        }
    }
}
function Assert-UnityMergedWrapper([string]$Sha,[string]$PrNumber,$Approval) {
    Assert-UnitySha $Sha
    if ($PrNumber -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid wrapper PR number.' }
    $pr=Invoke-UnityGh @('api',"repos/$UnityWrapperRepository/pulls/$PrNumber") | ConvertFrom-Json
    if (!$pr.merged -or $pr.merge_commit_sha -cne $Sha -or $pr.base.ref -cne 'dev' -or $pr.base.repo.full_name -cne $UnityWrapperRepository -or
        $pr.head.repo.full_name -cne $UnityWrapperRepository -or $pr.user.type -cne 'Bot') { throw 'Wrapper must be the actual reviewed same-repository bot PR merge into dev.' }
    if ($pr.head.ref -cne "automation/unity-wss-$($Approval.candidate.run_id)-$($Approval.candidate.sha256)") { throw 'Merged wrapper PR is not the canonical candidate branch.' }
    $compare=Invoke-UnityGh @('api',"repos/$UnityWrapperRepository/compare/${Sha}...dev") | ConvertFrom-Json
    if ($compare.status -cnotin @('ahead','identical')) { throw 'Wrapper merge is not contained in dev.' }
    $delta=Invoke-UnityGh @('api',"repos/$UnityWrapperRepository/compare/$($Approval.wrapper.source_sha)...$Sha") | ConvertFrom-Json
    if ($delta.total_commits -lt 1 -or $delta.files.Count -ge 300) { throw 'Wrapper comparison empty or potentially truncated.' }
    Assert-UnityDiff @($delta.files.filename) (Get-UnityAllowedWrapperPaths)
    $pages=Invoke-UnityGh @('api','--paginate','--slurp',"repos/$UnityWrapperRepository/actions/workflows/unity-compatibility.yml/runs?event=pull_request&head_sha=$($pr.head.sha)&per_page=100") | ConvertFrom-Json
    $runs=@($pages | ForEach-Object { $_.workflow_runs } | Where-Object { @($_.pull_requests.number) -contains [int]$PrNumber } | Sort-Object { [long]$_.id } -Descending)
    if ($runs.Count -eq 0 -or $runs[0].status -cne 'completed' -or $runs[0].conclusion -cne 'success') { throw 'Latest final-head normal wrapper PR CI has not succeeded.' }
    $jobs=Invoke-UnityGh @('api','--paginate','--slurp',"repos/$UnityWrapperRepository/actions/runs/$($runs[0].id)/jobs?per_page=100") | ConvertFrom-Json
    $required=@($jobs | ForEach-Object { $_.jobs } | Where-Object { $_.name -ceq 'Integration behavioral tests' })
    if ($required.Count -ne 1 -or $required[0].conclusion -cne 'success') { throw 'Normal committed-state acceptance missing/skipped/failed.' }
    foreach ($platform in @('Windows','Ubuntu','macOS')) {
        $matching=@($jobs | ForEach-Object { $_.jobs } | Where-Object { $_.name -ceq "Integration compatibility ($platform)" })
        if ($matching.Count -ne 1 -or $matching[0].conclusion -cne 'success') { throw "Normal committed-state platform validation missing/skipped/failed: $platform" }
    }
    $content=Invoke-UnityGh @('api',"repos/$UnityWrapperRepository/contents/.github/unity-candidate.json?ref=$Sha") | ConvertFrom-Json
    $record=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.content)) | ConvertFrom-Json
    Assert-UnitySameCandidate $record.candidate $Approval.candidate
    if ($record.projection_sha256 -cne $Approval.projection_sha256) { throw 'Merged projection differs from preflights.' }
    Assert-UnityRemoteProjection $Sha $record
    $marker=Get-UnityApprovalMarker $Approval
    if (!(($pr.body -split "`r?`n") -ccontains $marker)) { throw 'Merged PR does not carry the exact approval.' }
}

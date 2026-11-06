. "$PSScriptRoot/UnityContract.ps1"
. "$PSScriptRoot/wss-ci/Preflight.ps1"
. "$PSScriptRoot/MacOSConsumerContract.ps1"

function Wait-UnityRun([string]$Repository,[string]$RunId,[string]$Sha,[string]$Workflow,[string]$Event,[int]$TimeoutSeconds=2400) {
    Wait-WssCiRun $Repository $RunId $Sha $Workflow $Event $TimeoutSeconds
}
function Assert-UnityProducer($Candidate) {
    Assert-UnityCandidate $Candidate
    $run=Wait-UnityRun $Candidate.repository $Candidate.run_id $Candidate.commit 'artifacts.yml' 'push'
    if ($run.run_attempt -lt 1) { throw 'Exact producer attempt is required.' }
    if ($run.head_branch -cne (Get-WssCiChannel) -or $run.head_repository.full_name -cne $Candidate.repository -or $Candidate.archive -cne 'WSS-Universal-ci.zip') { throw 'Automatic Unity propagation requires the canonical Core dev push archive.' }
    $compare=Invoke-UnityGh -Arguments @('api',"repos/$($Candidate.repository)/compare/$($Candidate.commit)...$(Get-WssCiChannel)") | ConvertFrom-Json
    if ($compare.status -cnotin @('ahead','identical')) { throw 'Producer commit is not contained in Core dev.' }
    $pages=Invoke-UnityGh -Arguments @('api','--paginate','--slurp',"repos/$($Candidate.repository)/actions/runs/$($Candidate.run_id)/attempts/$($run.run_attempt)/jobs?per_page=100") | ConvertFrom-Json
    $jobs=@($pages | ForEach-Object { $_.jobs })
    . "$PSScriptRoot/wss-ci/Producer.ps1"
    Assert-WssCiProducerJobs $jobs 'macos-ble-v1'
    $artifact=Invoke-UnityGh -Arguments @('api',"repos/$($Candidate.repository)/actions/artifacts/$($Candidate.artifact_id)") | ConvertFrom-Json
    if ($artifact.expired -or $artifact.name -cne 'universal-release-assets' -or [string]$artifact.workflow_run.id -cne [string]$Candidate.run_id -or $artifact.workflow_run.head_sha -cne $Candidate.commit) { throw 'Wrong/expired producer artifact.' }
    if((Get-WssCiChannel) -ceq 'main'){if($compare.status -cne 'identical'){throw 'Core main moved from exact candidate.'};$proof=Assert-WssCiWorkflowAuthorization ([string]$Candidate.run_id);Assert-UnitySameCandidate $proof.candidate $Candidate}
}
function Get-UnityHead([string]$Repository) {
    $branch=Invoke-UnityGh -Arguments @('api',"repos/$Repository/branches/$(Get-WssCiChannel)") | ConvertFrom-Json
    Assert-UnitySha $branch.commit.sha
    $branch.commit.sha
}
function Start-UnityPreflight([string]$Repository,$Candidate,[string]$WrapperSha,[string]$GuiSha) {
    Assert-UnityCandidate $Candidate
    Assert-UnitySha $WrapperSha
    Assert-UnitySha $GuiSha
    if($Repository -cnotin @($UnityWrapperRepository,$UnityGuiRepository)){throw 'Unknown Unity preflight repository.'}
    $found=Start-WssCiPreflight -Repository $Repository -Candidate $Candidate -WrapperSha $WrapperSha -ApplicationSha $GuiSha -DispatchToken $env:UNITY_PREFLIGHT_TOKEN

    $expectedSha=if($Repository -ceq $UnityWrapperRepository){$WrapperSha}else{$GuiSha}
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
    $run=Wait-UnityRun $Repository $RunId $SourceSha 'wss-preflight.yml' 'workflow_dispatch'
    $pages=Invoke-UnityGh -Arguments @('api','--paginate','--slurp',"repos/$Repository/actions/runs/$RunId/attempts/$($run.run_attempt)/jobs?per_page=100") | ConvertFrom-Json
    $requiredName=if ($Role -ceq 'wrapper') { 'Preflight behavioral tests' } else { 'GUI general conformance' }
    $required=@($pages | ForEach-Object { $_.jobs } | Where-Object { $_.name -ceq $requiredName })
    if ($required.Count -ne 1 -or $required[0].conclusion -cne 'success') { throw 'Required candidate acceptance job missing/skipped/failed.' }
    foreach ($platform in @('Windows','Ubuntu','macOS')) {
        $matching=@($pages | ForEach-Object { $_.jobs } | Where-Object { ($_.name -split ' / ')[-1] -ceq "Preflight platform compatibility ($platform)" })
        if ($matching.Count -ne 1 -or $matching[0].conclusion -cne 'success') { throw "Candidate platform validation missing/skipped/failed: $platform" }
    }
    $macProofs=@()
    foreach ($arch in @(@('x64','X64'),@('arm64','Arm64'))) {
        $macRoot="$Root-macos-$($arch[0])"
        if (Test-Path -LiteralPath $macRoot) { throw 'Mac evidence destination must be new.' }
        $null=Invoke-UnityGh -Arguments @('run','download',$RunId,'--repo',$Repository,'--name',"unity-preflight-platform-$Role-macOS-$($arch[0])",'--dir',$macRoot)
        $null=Assert-MacOSConsumerProbe (Join-Path $macRoot 'platform-result.json') $arch[1] -RequireBackend -Repository $Repository -RunId $RunId -Attempt ([string]$run.run_attempt) -SourceSha $SourceSha
        $proof=Get-Content -LiteralPath (Join-Path $macRoot 'platform-evidence.json') -Raw | ConvertFrom-Json
        Assert-UnitySameCandidate $proof.candidate $Candidate
        if ($proof.schema -cne 'wss-dotnet-platform-evidence/v1' -or $proof.execution -cne 'dotnet' -or $proof.unity_executed -cne $false -or
            $proof.mode -cne 'candidate' -or $proof.role -cne $Role -or $proof.run_repository -cne $Repository -or
            [string]$proof.run_id -cne $RunId -or $proof.run_sha -cne $SourceSha -or
            (Get-FileHash -LiteralPath (Join-Path $macRoot 'platform-result.json')).Hash.ToLowerInvariant() -cne $proof.platform_result_sha256) {
            throw "Invalid macOS $($arch[0]) source/run/probe binding."
        }
        $macProofs+=$proof
    }
    if (Test-Path -LiteralPath $Root) { throw 'Evidence download destination must be new.' }
    $null=Invoke-UnityGh -Arguments @('run','download',$RunId,'--repo',$Repository,'--name','unity-preflight-evidence','--dir',$Root)
    $e=Assert-UnityEvidenceFiles $Root $Repository $RunId $SourceSha $Role $Candidate $Config
    foreach ($proof in $macProofs) {
        if ($proof.wrapper_sha -cne $e.wrapper_sha -or $proof.gui_sha -cne $e.gui_sha -or $proof.projection_sha256 -cne $e.projection_sha256 -or
            $proof.fixture_sha -cne $e.fixture_sha -or $proof.fixture_sha256 -cne $e.fixture_sha256) { throw 'Mac architectures did not test the same approved sources/projection/fixture.' }
    }
    $e
}
function Assert-UnityEvidenceFiles([string]$Root,[string]$Repository,[string]$RunId,[string]$SourceSha,[string]$Role,$Candidate,$Config) {
    $files=@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object @('evidence.json','results.xml','dotnet.log','projection.json') $files -CaseSensitive).Count -ne 0) { throw 'Unexpected/incomplete preflight artifact.' }
    $e=Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
    Assert-UnitySameCandidate $e.candidate $Candidate
    $expectedRunSha=if ($Role -ceq 'wrapper') { $e.wrapper_sha } else { $e.gui_sha }
    if ($e.schema -cne 'wss-dotnet-evidence/v1' -or $e.execution -cne 'dotnet' -or $e.unity_executed -cne $false -or $e.role -cne $Role -or $e.mode -cne 'candidate' -or $e.run_repository -cne $Repository -or
        [string]$e.run_id -cne $RunId -or $e.run_sha -cne $SourceSha -or $expectedRunSha -cne $SourceSha -or
        $e.fixture_sha -cne $Config.fixture_commit -or $e.fixture_sha256 -cne $Config.fixture_sha256 -or
        $e.sdk -cne $Config.dotnet_sdk -or $e.target_framework -cne 'net9.0' -or $e.test_framework -cne 'NUnit 3.14.0' -or
        $e.discovered -ne 12 -or $e.executed -ne 12 -or $e.passed -ne 12 -or $e.failed -ne 0 -or $e.skipped -ne 0 -or $e.assertion_expressions -ne 20) { throw 'Invalid runtime/source/fixture evidence.' }
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
    $tree=Invoke-UnityGh -Arguments @('api',"repos/$UnityWrapperRepository/git/trees/${Sha}?recursive=1") | ConvertFrom-Json
    if ($tree.truncated) { throw 'Merged wrapper tree response is truncated.' }
    $dlls=@($tree.tree | Where-Object { $_.path.StartsWith($UnityPluginPath+'/',[StringComparison]::Ordinal) -and ($_.path.EndsWith('.dll',[StringComparison]::Ordinal) -or $_.path.EndsWith('.so',[StringComparison]::Ordinal) -or $_.path.EndsWith('.dylib',[StringComparison]::Ordinal)) } | ForEach-Object { $_.path })
    $expected=@($UnityProjectionFiles | ForEach-Object { "$UnityPluginPath/$(Get-UnityProjectionPath $_)" })
    if (@(Compare-Object $expected $dlls -CaseSensitive).Count) { throw 'Merged wrapper has extra/missing payload DLLs.' }
    foreach ($file in $Record.files) {
        foreach ($suffix in @('','.meta')) {
            $path="$UnityPluginPath/$(Get-UnityProjectionPath $file.source)$suffix"
            $entries=@($tree.tree | Where-Object { $_.path -ceq $path -and $_.type -ceq 'blob' })
            if ($entries.Count -ne 1) { throw "Merged payload path missing/ambiguous: $path" }
            $blob=Invoke-UnityGh -Arguments @('api',"repos/$UnityWrapperRepository/git/blobs/$($entries[0].sha)") | ConvertFrom-Json
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
function Get-UnityReviewedPrRun([object[]]$Runs,$Pr,[string]$PrNumber) {
    $matching=@($Runs | Where-Object {
        $_.repository.full_name -ceq $UnityWrapperRepository -and
        $_.head_repository.full_name -ceq $UnityWrapperRepository -and
        $_.path -ceq '.github/workflows/unity-compatibility.yml' -and
        $_.event -ceq 'pull_request' -and $_.head_sha -ceq $Pr.head.sha -and
        $_.head_branch -ceq $Pr.head.ref -and
        (@($_.pull_requests).Count -eq 0 -or
            (@($_.pull_requests).Count -eq 1 -and [string]$_.pull_requests[0].number -ceq $PrNumber))
    } | Sort-Object { [long]$_.id } -Descending)
    if ($matching.Count -eq 0 -or $matching[0].status -cne 'completed' -or $matching[0].conclusion -cne 'success') {
        throw 'Latest final-head normal wrapper PR CI has not succeeded.'
    }
    $matching[0]
}
function Assert-UnityRequiredWrapperJobs([object[]]$Jobs) {
    foreach ($name in @('Integration behavioral tests','Integration compatibility (Windows)','Integration compatibility (Ubuntu)','Integration compatibility (macOS)')) {
        $matching=@($Jobs | Where-Object { $_.name -ceq $name })
        if ($matching.Count -ne 1 -or $matching[0].conclusion -cne 'success') { throw "Normal committed-state validation missing/skipped/failed: $name" }
    }
}
function Assert-UnityFanoutSources([string]$WrapperSha,[string]$GuiSha) {
    Assert-UnitySha $WrapperSha
    Assert-UnitySha $GuiSha
    foreach ($entry in @(@($UnityWrapperRepository,$WrapperSha),@($UnityGuiRepository,$GuiSha))) {
        $head=Invoke-UnityGh -Arguments @('api',"repos/$($entry[0])/git/ref/heads/$(Get-WssCiChannel)") | ConvertFrom-Json
        if ($head.object.sha -cne $entry[1]) { throw "Fanout source moved: $($entry[0]); require fresh reviewed evidence." }
    }
}
function Assert-UnityUnchangedFanoutBarrier([string]$ExpectedMergeSha,[string]$CurrentMergeSha) {
    Assert-UnitySha $ExpectedMergeSha
    Assert-UnitySha $CurrentMergeSha
    if ($CurrentMergeSha -cne $ExpectedMergeSha) { throw 'Shared barrier integration changed before application write credentials.' }
}
function Get-UnityGuiDispatchReuse($Approval,[string]$WrapperSha) {
    . "$PSScriptRoot/wss-ci/DispatchProof.ps1"
    $title="Promote Integration $WrapperSha / wss-$($Approval.candidate.run_id)-$($Approval.candidate.artifact_id)"
    $repo='cwru-non-academic/GUI_Unity_WSS_Application'
    $pages=Invoke-UnityGh -Arguments @('api','--paginate','--slurp',"repos/$repo/actions/workflows/promote-integration.yml/runs?event=workflow_dispatch&per_page=100")|ConvertFrom-Json
    $runs=@($pages|ForEach-Object {$_.workflow_runs}|Where-Object display_title -CEQ $title)
    $run=if($runs.Count -eq 1 -and [string]$runs[0].id -cmatch '^[1-9][0-9]*$'){Invoke-UnityGh -Arguments @('api',"repos/$repo/actions/runs/$($runs[0].id)")|ConvertFrom-Json}else{$null}
    Invoke-WssCiDispatchProof @{operation='reuse';runs=$runs;run=$run;expected=@{repository=$repo;source_sha=$Approval.gui.source_sha;title=$title}}
}

function Assert-UnityGuiDispatchIntent([string]$WrapperSha,[switch]$RequireCurrent) {
    . "$PSScriptRoot/wss-ci/DispatchProof.ps1"
    $name="unity-gui-dispatch-$WrapperSha"
    $pages=Invoke-UnityGh -Arguments @('api','--paginate','--slurp',"repos/cwru-non-academic/Unity_WSS_Integration_Lib/actions/artifacts?name=$name&per_page=100")|ConvertFrom-Json
    $artifacts=@($pages|ForEach-Object {$_.artifacts}|Where-Object name -CEQ $name)
    $null=Invoke-WssCiDispatchProof @{operation='intent';artifacts=$artifacts;run_id=$env:GITHUB_RUN_ID;attempt=$env:GITHUB_RUN_ATTEMPT;source_sha=$env:GITHUB_SHA;required=[bool]$RequireCurrent}
}

function Send-UnityGuiDispatch([string]$RequestPath,[string]$ReadToken,[string]$WriteToken) {
    if (!$ReadToken -or !$WriteToken) { throw 'Separate read and scoped application-write tokens required.' }
    $request=Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    if ($request.ref -cne (Get-WssCiChannel)) { throw 'GUI dispatch must target dev.' }
    $approval=$request.inputs.approval_json | ConvertFrom-Json
    $original=$env:GH_TOKEN
    try {
        $env:GH_TOKEN=$ReadToken
        Assert-UnityFanoutSources $request.inputs.wrapper_sha $approval.gui.source_sha
        if (Get-UnityGuiDispatchReuse $approval $request.inputs.wrapper_sha) { return }
        Assert-UnityGuiDispatchIntent $request.inputs.wrapper_sha -RequireCurrent
        if((Get-WssCiChannel) -ceq 'main'){
            $source=(& git -C $env:GITHUB_WORKSPACE rev-parse HEAD).Trim()
            if($LASTEXITCODE -ne 0 -or $env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
               $env:GITHUB_REPOSITORY -cne $UnityWrapperRepository -or $env:GITHUB_REF -cne 'refs/heads/main' -or
               $env:GITHUB_WORKFLOW_REF -cne "$UnityWrapperRepository/.github/workflows/dispatch-unity-promotion.yml@refs/heads/main" -or
               $env:GITHUB_SHA -cne $request.inputs.wrapper_sha -or $env:GITHUB_WORKFLOW_SHA -cne $env:GITHUB_SHA -or $source -cne $env:GITHUB_SHA){throw 'Main fanout must execute the exact accepted integration workflow source.'}
            $proof=Assert-WssCiWorkflowAuthorization ([string]$approval.candidate.run_id)
            Assert-UnitySameCandidate $proof.candidate $approval.candidate
            Assert-UnityFanoutSources $request.inputs.wrapper_sha $approval.gui.source_sha
        }
        $env:GH_TOKEN=$WriteToken
        try { $null=Invoke-UnityGh -Arguments @('api','--method','POST',"repos/$UnityGuiRepository/actions/workflows/promote-integration.yml/dispatches",'--input',$RequestPath) }
        catch { throw 'GUI dispatch failed or uncertain; inspect remote state before any replay.' }
    } finally { $env:GH_TOKEN=$original }
}
function Assert-UnityMergedWrapper([string]$Sha,[string]$PrNumber,$Approval) {
    Assert-UnitySha $Sha
    if ($PrNumber -cnotmatch '^[1-9][0-9]*$') { throw 'Invalid wrapper PR number.' }
    $pr=Invoke-UnityGh -Arguments @('api',"repos/$UnityWrapperRepository/pulls/$PrNumber") | ConvertFrom-Json
    if (!$pr.merged -or $pr.merge_commit_sha -cne $Sha -or $pr.base.ref -cne (Get-WssCiChannel) -or $pr.base.repo.full_name -cne $UnityWrapperRepository -or
        $pr.head.repo.full_name -cne $UnityWrapperRepository -or $pr.user.type -cne 'Bot') { throw 'Wrapper must be the actual reviewed same-repository bot PR merge into dev.' }
    if ($pr.head.ref -cne "automation/unity-wss-$($Approval.candidate.run_id)-$($Approval.candidate.sha256)") { throw 'Merged wrapper PR is not the canonical candidate branch.' }
    $compare=Invoke-UnityGh -Arguments @('api',"repos/$UnityWrapperRepository/compare/${Sha}...$(Get-WssCiChannel)") | ConvertFrom-Json
    if ($compare.status -cnotin @('ahead','identical')) { throw 'Wrapper merge is not contained in dev.' }
    $delta=Invoke-UnityGh -Arguments @('api',"repos/$UnityWrapperRepository/compare/$($Approval.wrapper.source_sha)...$Sha") | ConvertFrom-Json
    if ($delta.total_commits -lt 1 -or $delta.files.Count -ge 300) { throw 'Wrapper comparison empty or potentially truncated.' }
    Assert-UnityDiff @($delta.files.filename) (Get-UnityAllowedWrapperPaths)
    $pages=Invoke-UnityGh -Arguments @('api','--paginate','--slurp',"repos/$UnityWrapperRepository/actions/workflows/unity-compatibility.yml/runs?event=pull_request&head_sha=$($pr.head.sha)&per_page=100") | ConvertFrom-Json
    # GitHub may clear pull_requests after merge. Bind an empty association to
    # the reviewed PR's exact repository, workflow, event, head SHA and branch.
    # Nonempty associations must name only that PR; conflicting evidence fails.
    $run=Get-UnityReviewedPrRun @($pages | ForEach-Object { $_.workflow_runs }) $pr $PrNumber
    $jobs=Invoke-UnityGh -Arguments @('api','--paginate','--slurp',"repos/$UnityWrapperRepository/actions/runs/$($run.id)/jobs?per_page=100") | ConvertFrom-Json
    Assert-UnityRequiredWrapperJobs @($jobs | ForEach-Object { $_.jobs })
    $content=Invoke-UnityGh -Arguments @('api',"repos/$UnityWrapperRepository/contents/.github/unity-candidate.json?ref=$Sha") | ConvertFrom-Json
    $record=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.content)) | ConvertFrom-Json
    Assert-UnitySameCandidate $record.candidate $Approval.candidate
    if ($record.projection_sha256 -cne $Approval.projection_sha256) { throw 'Merged projection differs from preflights.' }
    Assert-UnityRemoteProjection $Sha $record
    $marker=Get-UnityApprovalMarker $Approval
    if (!(($pr.body -split "`r?`n") -ccontains $marker)) { throw 'Merged PR does not carry the exact approval.' }
}

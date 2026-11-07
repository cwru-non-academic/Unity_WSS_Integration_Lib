Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Universal-WssFiles.ps1"
$UnityWrapperRepository = 'cwru-non-academic/Unity_WSS_Integration_Lib'
$UnityGuiRepository = 'cwru-non-academic/GUI_Unity_WSS_Application'
$UnityGitlink = 'Assets/SubModules/WSSInterfacingModule'
$UnityPluginPath = 'Plugins/WSS_Core_Interface'
$UnityProjectionFiles = @($WssUniversalFiles | Where-Object { $_ -notmatch '/' }) + @(
    'backends/windows/WSS.Transport.BLE.Windows.dll',
    'backends/windows/WSS.Transport.BLE.Windows.Native.dll',
    'backends/windows/WssBleWindows.dll',
    'backends/macos/WSS.Transport.BLE.MacOS.dll',
    'backends/macos/libwss_macos_ble.dylib') + @($WssUniversalFiles | Where-Object { $_ -like 'runtimes/*' })
$UnityLegacyProjectionFiles=@($UnityProjectionFiles | Where-Object { $_ -cnotlike 'backends/macos/*' })

function Get-UnityCommittedProjectionFiles($Record) {
    foreach ($inventory in @(@{files=$UnityProjectionFiles},@{files=$UnityLegacyProjectionFiles})) {
        if ($Record.files.Count -eq $inventory.files.Count -and @(Compare-Object $inventory.files @($Record.files.source) -CaseSensitive).Count -eq 0) { return $inventory.files }
    }
    throw 'Projection must match exactly the declared 20-file macOS or legacy 18-file layout.'
}

function Get-UnityProjectionPath([string]$Source) {
    # Preserve RID paths (including duplicate Ports filenames); the established
    # Unity Windows BLE importer layout remains flat.
    if ($Source.StartsWith('runtimes/',[StringComparison]::Ordinal) -or $Source.StartsWith('backends/macos/',[StringComparison]::Ordinal)) { return $Source }
    [IO.Path]::GetFileName($Source)
}

function Invoke-UnityGh([string[]]$Arguments) {
    . "$PSScriptRoot/wss-ci/Process.ps1"
    Invoke-WssCiProcess -Executable gh -Arguments $Arguments -FailureMessage 'GitHub operation failed'
}
function Invoke-UnityGit([string]$Root, [string[]]$Arguments) {
    $response = & git -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git operation failed: $($Arguments[0])" }
    $response
}
function Get-UnityFixtureHash([string]$Root) {
    # Git owns checkout EOLs. Hash the pinned blob, not OS-dependent worktree
    # bytes, and reject any worktree/index change to the canonical fixture.
    $relative='tests/Wss.CSharpImplementation.Tests/StimulationControllerConformanceTests.cs'
    $null=Invoke-UnityGit $Root @('diff','--exit-code','HEAD','--',$relative)
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command git).Source)
    foreach ($argument in @('-C',$Root,'cat-file','blob',"HEAD:$relative")) { $start.ArgumentList.Add($argument) }
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($start)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $hash=[Convert]::ToHexString($sha.ComputeHash($process.StandardOutput.BaseStream)).ToLowerInvariant()
        $errorText=$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Canonical Git fixture could not be read: $errorText" }
        $hash
    } finally { $sha.Dispose(); $process.Dispose() }
}
function Assert-UnitySha([string]$Sha) {
    if ($Sha -cnotmatch '^[0-9a-f]{40}$') { throw 'A full lowercase source SHA is required.' }
}
function Assert-UnityCandidate($Candidate) {
    if ($Candidate.repository -cne 'cwru-non-academic/WSSCore') { throw 'Unexpected producer.' }
    Assert-UnitySha $Candidate.commit
    foreach ($field in @('run_id','artifact_id')) {
        if ([string]$Candidate.$field -cnotmatch '^[1-9][0-9]*$') { throw "Invalid candidate $field." }
    }
    if ($Candidate.archive -cnotmatch '^WSS-Universal-[A-Za-z0-9._-]+\.zip$' -or
        $Candidate.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid archive/hash.' }
}
function Assert-UnitySameCandidate($Actual, $Expected) {
    Assert-UnityCandidate $Actual
    foreach ($field in @('repository','commit','run_id','artifact_id','archive','sha256')) {
        if ([string]$Actual.$field -cne [string]$Expected.$field) { throw "Candidate mismatch: $field" }
    }
}
function Get-UnityMetaHash([string]$Path) {
    # Hash canonical text without changing any on-disk EOLs; Git owns checkout EOLs.
    $bytes = [Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($Path).Replace("`r`n","`n"))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}
function Get-UnityProjectionDigest($Files) {
    $text = @($Files | Sort-Object { [string]$_.source } | ForEach-Object { "$($_.source)|$($_.sha256)|$($_.meta_sha256)" }) -join "`n"
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
}
function Assert-UnityMacImporter([string]$Meta) {
    if ($Meta -cnotmatch "(?m)^  defineConstraints:\r?\n  - '!ENABLE_IL2CPP'\r?\n" -or
        $Meta -cnotmatch '(?m)^  isPreloaded: 0\r?$') { throw 'macOS BLE importer must exclude IL2CPP and lazy-load native code.' }
    $blocks=@([regex]::Split($Meta,'(?m)^  - first:\r?\n') | Select-Object -Skip 1)
    if ($blocks.Count -ne 4) { throw 'Unexpected macOS BLE importer platform inventory.' }
    $seen=@{}
    foreach ($block in $blocks) {
        $platform=[regex]::Match($block,'(?m)^      (Any|Editor|Standalone|Windows Store Apps): *([^\r\n]*)\r?$')
        $enabled=[regex]::Matches($block,'(?m)^      enabled: ([01])\r?$')
        if (!$platform.Success -or $enabled.Count -ne 1) { throw 'Invalid macOS BLE importer platform.' }
        $key=$platform.Groups[1].Value+'|'+$platform.Groups[2].Value.Trim()
        if ($seen.ContainsKey($key)) { throw 'Duplicate macOS BLE importer platform.' }
        $seen[$key]=$true
        $expected=if ($key -cin @('Editor|Editor','Standalone|OSXUniversal')) { '1' } elseif ($key -cin @('Any|','Windows Store Apps|WindowsStoreApps')) { '0' } else { throw 'Unexpected macOS BLE target.' }
        if ($enabled[0].Groups[1].Value -cne $expected) { throw 'macOS BLE importer enabled an unsupported target or disabled macOS.' }
        if ($expected -ceq '1' -and $block -cnotmatch '(?m)^        CPU: AnyCPU\r?$') { throw 'macOS universal importer requires AnyCPU.' }
        if ($key -ceq 'Editor|Editor' -and $block -cnotmatch '(?m)^        OS: OSX\r?$') { throw 'macOS BLE Editor importer must be restricted to OSX.' }
    }
}
function Assert-UnityProjection([string]$Root, $Record) {
    if ($Record.schema -cne 'wss-unity-projection/v1') { throw 'Invalid Unity projection schema.' }
    Assert-UnityCandidate $Record.candidate
    $sources=@(Get-UnityCommittedProjectionFiles $Record)
    $expected = @($sources | ForEach-Object { Get-UnityProjectionPath $_ })
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in @('.dll','.so','.dylib') } | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $expected $actual -CaseSensitive).Count -ne 0 -or $Record.files.Count -ne $expected.Count) { throw 'Wrong Unity DLL inventory; stale fallback/extra DLLs are forbidden.' }
    if (@(Compare-Object $sources @($Record.files.source) -CaseSensitive).Count -ne 0) { throw 'Wrong projection source inventory.' }
    foreach ($item in $Record.files) {
        $path = Join-Path $Root (Get-UnityProjectionPath $item.source)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.sha256 -or
            (Get-UnityMetaHash ($path+'.meta')) -cne $item.meta_sha256) { throw "Projection bytes/importer mismatch: $($item.source)" }
        $meta = [IO.File]::ReadAllText($path+'.meta')
        if ($item.source -in @('Newtonsoft.Json.dll','System.Numerics.Vectors.dll') -and $meta -match 'enabled: 1') { throw 'Unity-provided JSON/Vectors payload copies must have disabled importers.' }
        if ($item.source -like 'runtimes/*' -and $meta -match 'enabled: 1') { throw '.NET runtime assets must not be imported into Unity Mono/IL2CPP.' }
        if ($item.source -like 'backends/macos/*') { Assert-UnityMacImporter $meta }
    }
    if ((Get-UnityProjectionDigest $Record.files) -cne $Record.projection_sha256) { throw 'Projection digest mismatch.' }
}
function New-UnityProjection([string]$ArtifactRoot, [string]$WrapperRoot, [string]$Destination, $Candidate) {
    Assert-UnityCandidate $Candidate
    if (Test-Path -LiteralPath $Destination) { throw 'Projection destination must be new; no stale payload may survive.' }
    $inventory = @(Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($ArtifactRoot,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $WssUniversalFiles $inventory -CaseSensitive).Count -ne 0) { throw 'Full universal inventory required before projection.' }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $files = @()
    foreach ($source in $UnityProjectionFiles) {
        $name = Get-UnityProjectionPath $source
        $null = New-Item -ItemType Directory -Path (Split-Path (Join-Path $Destination $name)) -Force
        Copy-Item -LiteralPath (Join-Path $ArtifactRoot $source) -Destination (Join-Path $Destination $name)
        Copy-Item -LiteralPath (Join-Path $WrapperRoot "$UnityPluginPath/$name.meta") -Destination (Join-Path $Destination ($name+'.meta'))
        $files += [ordered]@{ source=$source; sha256=(Get-FileHash -LiteralPath (Join-Path $Destination $name) -Algorithm SHA256).Hash.ToLowerInvariant(); meta_sha256=(Get-UnityMetaHash (Join-Path $Destination ($name+'.meta'))) }
    }
    $record = [pscustomobject][ordered]@{ schema='wss-unity-projection/v1'; candidate=$Candidate; projection_sha256=(Get-UnityProjectionDigest $files); files=$files }
    Assert-UnityProjection $Destination $record
    $record
}
function Read-UnityConfig([string]$Path,[ValidateSet('legacy-v1','layered-v1')][string]$Profile='layered-v1') {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.schema -cne 'wss-unity-ci/v1' -or $config.branch -cne 'dev' -or $config.editor -cne '2022.3.62f3' -or
        $config.revision -cne '96770f904ca7' -or $config.test_framework -cne '1.1.33' -or
        $config.fixture_repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $config.expected_cases.Count -notin @(10,16)) { throw 'Unexpected Unity CI contract.' }
    if($config.PSObject.Properties['profiles']) {
        if(@(Compare-Object @('legacy-v1','layered-v1') @($config.profiles.PSObject.Properties.Name) -CaseSensitive).Count){throw 'Both reviewed profile contracts are required.'}
        $fields=@('fixture_repository','fixture_commit','fixture_sha256','expected_cases','dotnet_expected_cases','multidevice_expected_cases')
        foreach($name in @('legacy-v1','layered-v1')) {
            $entry=$config.profiles.$name
            if(@(Compare-Object $fields @($entry.PSObject.Properties.Name) -CaseSensitive).Count){throw 'Unexpected profile contract fields.'}
            $hash=if($name -ceq 'legacy-v1'){'f6aeced83d35255532b6685d9c870307f856aad140da133695a77e9de6104ee2'}else{'96812ab33be7ede8840ddb78131a50796fd3f797d9627f958251b3e58796baf8'}
            $commit=if($name -ceq 'legacy-v1'){'7145e2307f997f703748530bf74311ef94455e98'}else{'fc427c5b8bc6534a7d02f00283830072572aa03a'}
            $count=if($name -ceq 'legacy-v1'){10}else{16}
            if($entry.fixture_repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $entry.fixture_sha256 -cne $hash -or $entry.fixture_commit -cne $commit -or $entry.expected_cases.Count -ne $count -or $entry.dotnet_expected_cases.Count -ne $count -or $entry.multidevice_expected_cases.Count -ne ($count-10)){throw 'Unreviewed canonical profile inventory.'}
        }
        foreach($field in $fields){
            if(($config.$field -join "`n") -cne ($config.profiles.'layered-v1'.$field -join "`n")){throw 'Compatibility fields must equal the mandatory modern profile.'}
        }
        foreach($field in $fields){$config.$field=$config.profiles.$Profile.$field}
    } elseif($Profile -ceq 'legacy-v1' -and $config.fixture_sha256 -cne 'f6aeced83d35255532b6685d9c870307f856aad140da133695a77e9de6104ee2'){throw 'Missing reviewed legacy profile.'}
    Assert-UnitySha $config.fixture_commit
    if ($config.fixture_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing fixture digest.' }
    $config
}
function Assert-UnityResults([string]$Path, $Config, [switch]$DotNet, [ValidateSet('single','multi')][string]$Stage='single') {
    # Disable DTD/entity resolution: results may originate from proposed source.
    $settings = [Xml.XmlReaderSettings]::new(); $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path,$settings)
    try { $xml=[Xml.XmlDocument]::new(); $xml.XmlResolver=$null; $xml.Load($reader) } finally { $reader.Dispose() }
    $count=$Config.expected_cases.Count
    if($count -notin @(10,16) -or ($count -eq 10 -and $Stage -ceq 'multi')){throw 'Invalid canonical profile/stage.'}
    $run=$xml.DocumentElement; $cases=@($xml.SelectNodes('//test-case'))
    if ($run.get_Name() -cne 'test-run' -or $run.GetAttribute('result') -cne 'Passed' -or
        $run.GetAttribute('testcasecount') -cne [string]$count -or $run.GetAttribute('total') -cne [string]$count -or
        $run.GetAttribute('passed') -cne [string]$count -or $cases.Count -ne $count) { throw 'All canonical profile cases must be discovered, executed and passed.' }
    foreach ($attribute in @('failed','skipped','inconclusive')) { if ($run.GetAttribute($attribute) -cne '0') { throw "Nonzero or absent $attribute count." } }
    $expected=if ($DotNet) { @($Config.dotnet_expected_cases) } else { @($Config.expected_cases) }
    if ($Stage -ceq 'multi') { $expected=@($expected | Select-Object -First 10)+@($Config.multidevice_expected_cases) }
    if ($expected.Count -ne $count -or @(Compare-Object $expected @($cases | ForEach-Object { $_.GetAttribute('name') }) -CaseSensitive).Count -ne 0 -or
        @($cases | Where-Object { $_.GetAttribute('result') -cne 'Passed' }).Count -gt 0) { throw 'Missing/duplicate/unexpected/unsuccessful canonical cases.' }
}
function Assert-UnitySource([string]$Root,[string]$Sha,[switch]$IgnoreSubmodule) {
    Assert-UnitySha $Sha
    if ((Invoke-UnityGit $Root @('rev-parse','HEAD')).Trim() -cne $Sha) { throw 'Checked-out source differs from the pinned SHA.' }
    $statusArguments=@('status','--porcelain','--untracked-files=normal')
    if ($IgnoreSubmodule) { $statusArguments+='--ignore-submodules=all' }
    if (@(Invoke-UnityGit $Root $statusArguments).Count -ne 0) { throw 'Source checkout must be clean before staging the disposable harness.' }
}
function Get-UnityAllowedWrapperPaths {
    @($UnityProjectionFiles | ForEach-Object { $name=Get-UnityProjectionPath $_; "$UnityPluginPath/$name"; "$UnityPluginPath/$name.meta" }) + @('.github/unity-candidate.json')
}
function Assert-UnityDiff([string[]]$Paths,[string[]]$Allowed) {
    if ($Paths.Count -eq 0 -or @($Paths | Where-Object { $_ -cnotin $Allowed }).Count -gt 0) { throw 'Empty or out-of-scope promotion diff.' }
}

# Require independently enumerated single- and multi-device runtime evidence.
function Assert-UnityMultiStageEvidence([string]$Root,$Single,$Config) {
    if ($Single.stage -cne 'single') { throw 'Root evidence must identify the single stage.' }
    $multiRoot = Join-Path $Root 'multi'
    foreach ($name in @('evidence.json','results.xml','dotnet.log','projection.json')) {
        if (!(Test-Path -LiteralPath (Join-Path $multiRoot $name) -PathType Leaf)) { throw "Missing multi-stage evidence: $name" }
    }
    $multi = Get-Content (Join-Path $multiRoot 'evidence.json') -Raw | ConvertFrom-Json
    Assert-UnitySameCandidate $multi.candidate $Single.candidate
    foreach ($field in @('test_root','test_sha','test_repository','test_selection_id','test_contract_sha256')) {
        if ($Single.PSObject.Properties[$field] -or $multi.PSObject.Properties[$field]) {
            if (!$Single.PSObject.Properties[$field] -or !$multi.PSObject.Properties[$field] -or $Single.$field -cne $multi.$field) { throw "Multi-stage selected test binding differs: $field" }
        }
    }
    foreach ($field in @('schema','execution','role','mode','wrapper_sha','gui_sha','fixture_sha','fixture_sha256','sdk','target_framework','test_framework','run_repository','run_id','run_sha','projection_sha256','unity_executed')) {
        if ($multi.$field -cne $Single.$field) { throw "Multi-stage evidence differs: $field" }
    }
    if ($multi.stage -cne 'multi' -or $multi.discovered -ne 16 -or $multi.executed -ne 16 -or $multi.passed -ne 16 -or
        $multi.failed -ne 0 -or $multi.skipped -ne 0 -or $multi.assertion_expressions -ne 20) { throw 'Incomplete multi-stage runtime evidence.' }
    foreach ($pair in @(@('results.xml','results_sha256'),@('dotnet.log','log_sha256'))) {
        if ((Get-FileHash -LiteralPath (Join-Path $multiRoot $pair[0])).Hash.ToLowerInvariant() -cne $multi.($pair[1])) { throw 'Multi-stage content hash mismatch.' }
    }
    if ((Get-FileHash -LiteralPath (Join-Path $multiRoot 'projection.json')).Hash -cne (Get-FileHash -LiteralPath (Join-Path $Root 'projection.json')).Hash) { throw 'Multi-stage package projection differs.' }
    Assert-UnityResults (Join-Path $multiRoot 'results.xml') $Config -DotNet -Stage multi
    if ($Single.PSObject.Properties['test_selection_id'] -and $Single.test_selection_id) {
        $baselineRoot=Join-Path $Root 'mandatory-baseline'
        $baseline=Get-Content -LiteralPath (Join-Path $baselineRoot 'evidence.json') -Raw | ConvertFrom-Json
        if (!$baseline.PSObject.Properties['test_selection_id'] -or $baseline.test_selection_id -or
            $baseline.wrapper_sha -cne $Single.wrapper_sha -or $baseline.gui_sha -cne $Single.gui_sha -or
            $baseline.role -cne $Single.role -or $baseline.mode -cne $Single.mode) { throw 'Selected suite cannot replace the fixed-product mandatory baseline.' }
        Assert-UnitySameCandidate $baseline.candidate $Single.candidate
        Assert-UnityResults (Join-Path $baselineRoot 'results.xml') $Config -DotNet
        Assert-UnityMultiStageEvidence $baselineRoot $baseline $Config
    }
}

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

function Get-UnityProjectionPath([string]$Source) {
    # Preserve RID paths (including duplicate Ports filenames); the established
    # Unity Windows BLE importer layout remains flat.
    if ($Source.StartsWith('runtimes/',[StringComparison]::Ordinal) -or $Source.StartsWith('backends/macos/',[StringComparison]::Ordinal)) { return $Source }
    [IO.Path]::GetFileName($Source)
}

function Invoke-UnityGh([string[]]$Arguments) {
    $response = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub operation failed: $($Arguments[0..([Math]::Min(1,$Arguments.Count-1))] -join ' ')" }
    $response
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
function Assert-UnityProjection([string]$Root, $Record) {
    if ($Record.schema -cne 'wss-unity-projection/v1') { throw 'Invalid Unity projection schema.' }
    Assert-UnityCandidate $Record.candidate
    $expected = @($UnityProjectionFiles | ForEach-Object { Get-UnityProjectionPath $_ })
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in @('.dll','.so','.dylib') } | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $expected $actual -CaseSensitive).Count -ne 0 -or $Record.files.Count -ne $expected.Count) { throw 'Wrong Unity DLL inventory; stale fallback/extra DLLs are forbidden.' }
    if (@(Compare-Object $UnityProjectionFiles @($Record.files.source) -CaseSensitive).Count -ne 0) { throw 'Wrong projection source inventory.' }
    foreach ($item in $Record.files) {
        $path = Join-Path $Root (Get-UnityProjectionPath $item.source)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.sha256 -or
            (Get-UnityMetaHash ($path+'.meta')) -cne $item.meta_sha256) { throw "Projection bytes/importer mismatch: $($item.source)" }
        $meta = [IO.File]::ReadAllText($path+'.meta')
        if ($item.source -in @('Newtonsoft.Json.dll','System.Numerics.Vectors.dll') -and $meta -match 'enabled: 1') { throw 'Unity-provided JSON/Vectors payload copies must have disabled importers.' }
        if ($item.source -like 'runtimes/*' -and $meta -match 'enabled: 1') { throw '.NET runtime assets must not be imported into Unity Mono/IL2CPP.' }
        if ($item.source -like 'backends/macos/*' -and $meta -match 'enabled: 1') { throw 'macOS Core package probes do not enable Unity plugin support.' }
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
function Read-UnityConfig([string]$Path) {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.schema -cne 'wss-unity-ci/v1' -or $config.branch -cne 'dev' -or $config.editor -cne '2022.3.62f3' -or
        $config.revision -cne '96770f904ca7' -or $config.test_framework -cne '1.1.33' -or
        $config.fixture_repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $config.expected_cases.Count -ne 10) { throw 'Unexpected Unity CI contract.' }
    Assert-UnitySha $config.fixture_commit
    if ($config.fixture_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing fixture digest.' }
    $config
}
function Assert-UnityResults([string]$Path, $Config, [switch]$DotNet) {
    # Disable DTD/entity resolution: results may originate from proposed source.
    $settings = [Xml.XmlReaderSettings]::new(); $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path,$settings)
    try { $xml=[Xml.XmlDocument]::new(); $xml.XmlResolver=$null; $xml.Load($reader) } finally { $reader.Dispose() }
    $run=$xml.DocumentElement; $cases=@($xml.SelectNodes('//test-case'))
    if ($run.get_Name() -cne 'test-run' -or $run.GetAttribute('result') -cne 'Passed' -or
        $run.GetAttribute('testcasecount') -cne '10' -or $run.GetAttribute('total') -cne '10' -or
        $run.GetAttribute('passed') -cne '10' -or $cases.Count -ne 10) { throw 'All ten canonical cases must be discovered, executed and passed.' }
    foreach ($attribute in @('failed','skipped','inconclusive')) { if ($run.GetAttribute($attribute) -cne '0') { throw "Nonzero or absent $attribute count." } }
    $expected=if ($DotNet) { @($Config.dotnet_expected_cases) } else { @($Config.expected_cases) }
    if ($expected.Count -ne 10 -or @(Compare-Object $expected @($cases | ForEach-Object { $_.GetAttribute('name') }) -CaseSensitive).Count -ne 0 -or
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

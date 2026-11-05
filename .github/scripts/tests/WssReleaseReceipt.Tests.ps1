$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/../WssReleaseReceipt.ps1"
$parseErrors=$null;$parseTokens=$null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Write-ReleaseReceipt.ps1'),[ref]$parseTokens,[ref]$parseErrors) | Out-Null
if ($parseErrors) { throw ($parseErrors | Out-String) }
$count = 0
function Reject([scriptblock] $Action) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw 'Expected invalid receipt evidence to be rejected.' }
    $script:count++
}
$repo = 'cwru-non-academic/Unity_WSS_Integration_Lib'
$sha = '1' * 40
function Pr { [pscustomobject]@{merged=$true;merged_by=@{type='User'};state='closed';merge_commit_sha=$sha;base=@{ref='dev';repo=@{full_name=$repo}};head=@{repo=@{full_name=$repo}};user=@{type='Bot'}} }
$p = Pr
Assert-WssReceiptPr $p $repo $sha
foreach ($mutate in @(
    { param($p) $p.merged=$false }, { param($p) $p.state='open' },
    { param($p) $p.merge_commit_sha='2'*40 }, { param($p) $p.base.ref='main' },
    { param($p) $p.head.repo.full_name='fork/test' }, { param($p) $p.user.type='User' }, { param($p) $p.merged_by.type='Bot' }
)) { $p=Pr; & $mutate $p; Reject { Assert-WssReceiptPr $p $repo $sha } }
$target = @{workflow='.github/workflows/unity-compatibility.yml';jobs=@('Integration behavioral tests','Integration compatibility (macOS)')}
function Run { [pscustomobject]@{status='completed';conclusion='success';head_branch='dev';head_sha=$sha;repository=@{full_name=$repo};head_repository=@{full_name=$repo};path=$target.workflow;event='workflow_dispatch'} }
function Jobs { @($target.jobs | ForEach-Object { [pscustomobject]@{name=$_;status='completed';conclusion='success'} }) }
Assert-WssReceiptNormalRun (Run) $repo $target $sha (Jobs)
$push=Run;$push.event='push';Assert-WssReceiptNormalRun $push $repo $target $sha (Jobs)
foreach ($mutate in @(
    { param($r) $r.event='pull_request' }, { param($r) $r.status='in_progress' },
    { param($r) $r.conclusion='failure' }, { param($r) $r.head_branch='main' },
    { param($r) $r.head_sha='2'*40 }, { param($r) $r.path='.github/workflows/wss-preflight.yml' },
    { param($r) $r.head_repository.full_name='fork/test' }
)) { $r=Run; & $mutate $r; Reject { Assert-WssReceiptNormalRun $r $repo $target $sha (Jobs) } }
Reject { Assert-WssReceiptNormalRun (Run) $repo $target $sha @() }
$j=Jobs; $j[1].conclusion='skipped'; Reject { Assert-WssReceiptNormalRun (Run) $repo $target $sha $j }
$j=Jobs; $j+= $j[1]; Reject { Assert-WssReceiptNormalRun (Run) $repo $target $sha $j }
Assert-WssReceiptChangedFiles unity-wrapper @(@{filename='Plugins/WSS_Core_Interface/backends/macos/libwss_macos_ble.dylib'})
Assert-WssReceiptChangedFiles unity-gui @(@{filename='Assets/SubModules/WSSInterfacingModule'})
Reject { Assert-WssReceiptChangedFiles unity-wrapper @() }
Reject { Assert-WssReceiptChangedFiles unity-wrapper @(@{filename='.github/workflows/unrelated.yml'}) }
Reject { Assert-WssReceiptChangedFiles unity-gui @(@{filename='Assets/SubModules/WSSInterfacingModule'},@{filename='Program.cs'}) }
Reject { Assert-WssReceiptChangedFiles unknown @(@{filename='lib/test'}) }
"Receipt acceptance boundary tests passed ($count rejections; valid merged PR, exact normal CI and allowed dependency scopes)."

# Exercise production command wrappers without network, credentials, or receipt emission.
& {
    $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Write-ReleaseReceipt.ps1'),[ref]$null,[ref]$errors)
    if ($errors.Count) { throw 'Receipt emitter does not parse.' }
    foreach ($name in @('Invoke-ReceiptGh','Invoke-ReceiptGit','Api')) {
        $definitions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true))
        if ($definitions.Count -ne 1) { throw "Unique production command helper required: $name" }
        . ([scriptblock]::Create($definitions[0].Extent.Text))
    }
    $collisions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('gh','git')},$true))
    if ($collisions.Count) { throw 'Receipt helpers must not shadow native command names.' }
    $calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Invoke-ReceiptGh','Invoke-ReceiptGit')},$true))
    foreach ($call in $calls) {
        if (!@($call.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'Arguments' }).Count) {
            throw 'Receipt command arrays must be bound explicitly, not splatted into positional parameters.'
        }
    }
    $savedExitVariable=Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $hadExitCode=$null -ne $savedExitVariable
    $savedExitCode=if ($hadExitCode) { $savedExitVariable.Value } else { $null }
    try {
        function gh { $global:LASTEXITCODE=0; @{arguments=@($args)} | ConvertTo-Json -Compress }
        function git { $global:LASTEXITCODE=0; @{arguments=@($args)} | ConvertTo-Json -Compress }
        $api=Api 'repos/example/repo'
        if (($api.arguments -join '|') -cne 'api|repos/example/repo') { throw 'GitHub API arguments were lost.' }
        $download=Invoke-ReceiptGh -Arguments @('run','download','123','--repo','example/repo','--dir','path with spaces') | ConvertFrom-Json
        if (($download.arguments -join '|') -cne 'run|download|123|--repo|example/repo|--dir|path with spaces') { throw 'GitHub command arguments were changed.' }
        $object=Invoke-ReceiptGit 'root with spaces' -Arguments @('rev-parse','HEAD:.github/scripts') | ConvertFrom-Json
        if (($object.arguments -join '|') -cne '-C|root with spaces|rev-parse|HEAD:.github/scripts') { throw 'Git command arguments were changed.' }
        function gh { $global:LASTEXITCODE=17 }
        function git { $global:LASTEXITCODE=18 }
        foreach ($failure in @(
            @{action={Invoke-ReceiptGh -Arguments @('api','missing')};message='GitHub evidence request failed: api'},
            @{action={Invoke-ReceiptGit '.' -Arguments @('rev-parse','missing')};message='Git evidence request failed.'}
        )) {
            $rejected=$false
            try { & $failure.action } catch {
                if ($_.Exception.Message -cne $failure.message) { throw }
                $rejected=$true
            }
            if (!$rejected) { throw 'Native command failure was accepted.' }
        }
    } finally {
        if ($hadExitCode) { $global:LASTEXITCODE=$savedExitCode }
        else { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
}
"Receipt command dispatch contracts passed (no native-name collision; complete argument arrays; fail-closed exit codes)."

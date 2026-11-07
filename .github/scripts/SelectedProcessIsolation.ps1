# Selected suites have no authentication environment or parent PowerShell scope.
function Invoke-CredentialFreeSelectedProcess([string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds=1800) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$FilePath
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    foreach($argument in $Arguments){$start.ArgumentList.Add([string]$argument)}
    $handles=@('GITHUB_ENV','GITHUB_OUTPUT','GITHUB_PATH','GITHUB_STATE','SSH_AUTH_SOCK','SSH_AGENT_PID','GIT_ASKPASS','GIT_SSH_COMMAND')
    foreach($name in @($start.Environment.Keys)){
        if($name -match '(?i)TOKEN|SECRET|PASSWORD|PRIVATE.?KEY|CREDENTIAL' -or $name -cin $handles){$null=$start.Environment.Remove($name)}
    }
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    try{
        if(!$process.Start()){throw 'Could not start isolated selected suite.'}
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if(!$process.WaitForExit($TimeoutSeconds*1000)){$process.Kill($true);$process.WaitForExit();throw 'Isolated selected suite timed out; no evidence emitted.'}
        $out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
        if($out){Write-Host $out}
        if($err){Write-Host $err}
        if($process.ExitCode -ne 0){throw "Isolated selected suite failed ($($process.ExitCode)); no evidence emitted."}
    } finally {$process.Dispose()}
}
function Invoke-CredentialFreeSelectedPowerShell([string]$Runner,[hashtable]$Options) {
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',$Runner)
    foreach($key in $Options.Keys){$arguments+="-$key";$arguments+=[string]$Options[$key]}
    Invoke-CredentialFreeSelectedProcess (Get-Command pwsh -ErrorAction Stop).Source $arguments
}

# Kept in the trusted parent, never serialized into selected-process state.
function Get-UnityEvidenceInventory([string]$Root) {
    if (!(Test-Path -LiteralPath $Root -PathType Container)) { throw 'Mandatory evidence root missing.' }
    $rootItem=Get-Item -LiteralPath $Root -Force
    $items=@($rootItem)+@(Get-ChildItem -LiteralPath $Root -Recurse -Force)
    $inventory=@{}
    foreach($item in $items){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Mandatory evidence contains a filesystem link.'}
        $relative=[IO.Path]::GetRelativePath($rootItem.FullName,$item.FullName)
        $inventory[$relative]=if($item.PSIsContainer){'directory'}else{(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    return $inventory
}
function Assert-UnityEvidenceInventory([string]$Root,[hashtable]$Expected) {
    $actual=Get-UnityEvidenceInventory $Root
    if($actual.Count -ne $Expected.Count){throw 'Mandatory evidence inventory changed.'}
    foreach($key in $Expected.Keys){
        if(!$actual.ContainsKey($key) -or $actual[$key] -cne $Expected[$key]){throw 'Mandatory evidence inventory changed.'}
    }
}

function Invoke-UnitySelectedWithMandatoryBaseline([string]$Runner,[hashtable]$Options,[string]$BaselineRoot,[switch]$ConformanceOnly) {
    $baselineOptions=$Options.Clone()
    foreach($key in @('TestRoot','TestSha','TestRepository','TestSelectionId')){$baselineOptions.Remove($key)}
    $baselineOptions.OutputRoot=$BaselineRoot
    Invoke-CredentialFreeSelectedPowerShell $Runner $baselineOptions
    $baselineEvidence=Join-Path $BaselineRoot $(if($ConformanceOnly){'evidence.json'}else{'platform-evidence.json'})
    if(!(Test-Path -LiteralPath $baselineEvidence -PathType Leaf)){throw 'Trusted mandatory baseline evidence missing.'}
    $mandatoryInventory=Get-UnityEvidenceInventory $BaselineRoot
    Invoke-CredentialFreeSelectedPowerShell $Runner $Options
    Assert-UnityEvidenceInventory $BaselineRoot $mandatoryInventory
}

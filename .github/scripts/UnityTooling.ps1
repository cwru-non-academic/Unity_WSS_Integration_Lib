# This module is executed only from the workflow's literal pinned tooling checkout.
# These arguments assert that boundary; selected test metadata cannot choose it.
function Resolve-UnityTooling([string]$ToolRoot,[string]$ToolSha,[string]$WrapperRoot,[string]$WrapperSha,[string]$ConfigPath,[string]$TestRoot='') {
 if([bool]$ToolRoot -ne [bool]$ToolSha){throw 'ToolRoot and ToolSha are required together.'}
 if(!$ToolRoot){$ToolRoot=$WrapperRoot;$ToolSha=$WrapperSha}
 Assert-UnitySha $ToolSha
 $root=[IO.Path]::GetFullPath($ToolRoot)
 $executing=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
 if($root -cne $executing){throw 'ToolRoot must be the executing immutable tooling checkout.'}
 if([IO.Path]::GetFullPath($ConfigPath) -cne (Join-Path $root '.github/unity-ci.json')){throw 'ConfigPath must be the executing tooling common config.'}
 if($TestRoot -and [IO.Path]::GetFullPath($TestRoot) -ceq $root){throw 'Selected tests cannot be the tooling checkout.'}
 if([IO.Path]::GetFullPath((Invoke-UnityGit $root @('rev-parse','--show-toplevel')).Trim()) -cne $root){throw 'ToolRoot must be a repository root.'}
 Assert-UnitySource $root $ToolSha
 if(@(Invoke-UnityGit $root @('status','--porcelain','--untracked-files=all','--ignored')).Count){throw 'Tooling checkout must have no ignored or untracked execution inputs.'}
 if(@(Invoke-UnityGit $root @('ls-files','-v') | Where-Object {$_ -cnotmatch '^H '}).Count){throw 'Tooling checkout cannot hide index modifications.'}
 foreach($path in @($root,(Join-Path $root '.github'))+@(Get-ChildItem (Join-Path $root '.github/scripts') -Recurse -Force | ForEach-Object FullName)) {
  if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Tooling dependencies cannot use filesystem links.'}
 }
 [pscustomobject]@{root=$root;sha=$ToolSha;config=[IO.Path]::GetFullPath($ConfigPath);config_sha256=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Assert-UnityTooling($Tooling,[string]$WrapperRoot,[string]$WrapperSha,[string]$TestRoot='') {
 $current=Resolve-UnityTooling $Tooling.root $Tooling.sha $WrapperRoot $WrapperSha $Tooling.config $TestRoot
 if($current.config_sha256 -cne $Tooling.config_sha256){throw 'Tooling config changed during execution.'}
}

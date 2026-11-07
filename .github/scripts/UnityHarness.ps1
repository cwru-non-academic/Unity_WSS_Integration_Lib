# Mandatory harness builders are external dependencies of protected CI tooling.
# Hash canonical strict UTF-8/LF text; checkout line endings are not a permission change.
function Assert-UnityHarnessBuilders([string]$WrapperRoot,[ValidateSet('legacy-v1','layered-v1')][string]$Profile) {
 $allowed=@{
  'Conformance~/Prepare-Harness.ps1'=@('085b9b2e70c9d9255863cd0107ad1b8bb92a7816d6625b97de674e01d9637b27')
  'Conformance~/Prepare-PlatformHarness.ps1'=@('38232d30c9286cec88aad95e9b6fd0f1c4009bb716b63a2d4f17e8b1308d2f01')
 }
 if($Profile -ceq 'legacy-v1'){$allowed['Conformance~/Prepare-Harness.ps1']+='46831019a7afe9df4636c2e7b232e3a30412da3c8e0734894df30d5903f819cd'}
 foreach($relative in $allowed.Keys) {
  $path=Join-Path $WrapperRoot $relative
  $text=[IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true)).Replace("`r`n","`n")
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
  if($hash -cnotin $allowed[$relative]){throw "Unreviewed mandatory harness builder: $relative"}
 }
}

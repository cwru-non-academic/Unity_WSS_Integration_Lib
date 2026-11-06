Set-StrictMode -Version Latest
. "$PSScriptRoot/wss-ci/Channel.ps1"

function Assert-WssReceiptPr($Pr,[string] $Repository,[string] $Sha) {
    if (-not $Pr.merged -or $Pr.state -cne 'closed' -or $Pr.merge_commit_sha -cne $Sha -or
        $Pr.base.ref -cne (Get-WssCiChannel) -or $Pr.base.repo.full_name -cne $Repository -or
        $Pr.head.repo.full_name -cne $Repository -or $Pr.user.type -cne 'Bot' -or $Pr.merged_by.type -cne 'User') {
        throw 'Receipt requires an actual same-repository bot dependency PR merged into dev.'
    }
}

function Assert-WssReceiptNormalRun($Run,[string] $Repository,$Target,[string] $Sha,$Jobs) {
    if ($Run.status -cne 'completed' -or $Run.conclusion -cne 'success' -or $Run.head_branch -cne (Get-WssCiChannel) -or
        $Run.head_sha -cne $Sha -or $Run.repository.full_name -cne $Repository -or $Run.head_repository.full_name -cne $Repository -or
        $Run.path -cne $Target.workflow -or $Run.event -cnotin @('push','workflow_dispatch')) {
        throw 'Fresh exact-merge normal CI is not successful.'
    }
    foreach ($name in $Target.jobs) {
        $match = @($Jobs | Where-Object name -CEQ $name)
        if ($match.Count -ne 1 -or $match[0].status -cne 'completed' -or $match[0].conclusion -cne 'success') { throw "Missing unique successful normal job: $name" }
    }
}

function Assert-WssReceiptChangedFiles([string] $TargetId,$Files) {
    if (@($Files).Count -eq 0) { throw 'Dependency PR must change the accepted dependency.' }
    if ($TargetId -ceq 'unity-wrapper') {
        if (@($Files | Where-Object filename -CNotMatch '^(Plugins/WSS_Core_Interface/|\.github/unity-candidate\.json$)').Count -ne 0) { throw 'Wrapper receipt PR may change only the accepted projection.' }
    } elseif ($TargetId -ceq 'unity-gui') {
        if (@($Files).Count -ne 1 -or $Files[0].filename -cne 'Assets/SubModules/WSSInterfacingModule') { throw 'GUI receipt PR may change only its wrapper gitlink.' }
    } else { throw 'Unknown Unity acceptance target.' }
}

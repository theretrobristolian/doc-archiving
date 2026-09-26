function exit-script {
    param(
        [int]$ExitCode
    )

    Write-Log "----------------------------------------------------------------"
    $timer.Stop()
    Write-Log "Command: '$CommandName'"
    Write-Log "Script: '$ScriptName' has finished with Exit Code: $ExitCode"
    Write-Log ("Total runtime of: {0:N2} minutes ({1:N2} seconds)" -f ($timer.Elapsed.TotalMinutes), $timer.Elapsed.TotalSeconds)
    Write-Log "----------------------------------------------------------------"

    #exit $ExitCode
}

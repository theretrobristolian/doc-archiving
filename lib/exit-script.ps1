function exit-script {
    param(
        [int]$ExitCode
    )

    write-log "----------------------------------------------------------------"
    $timer.Stop()
    write-log "Command: '$CommandName'"
    write-log "Script: '$ScriptName' has finished with Exit Code: $ExitCode"
    write-log ("Total runtime of: {0:N2} minutes ({1:N2} seconds)" -f ($timer.Elapsed.TotalMinutes), $timer.Elapsed.TotalSeconds)
    write-log "----------------------------------------------------------------"

    #exit $ExitCode
}

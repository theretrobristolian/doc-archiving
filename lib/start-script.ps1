function start-script {
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    write-log "----------------------------------------------------------------"
    
    write-log "Command: '$CommandName'"
    write-log "Script : '$ScriptName' started."
    write-log "Root   : '$scriptRoot'"
    write-log "User   : '$CurrentUser'"
    write-log "----------------------------------------------------------------"
}

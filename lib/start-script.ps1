function start-script {
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "----------------------------------------------------------------"
    
    Write-Log "Command: '$CommandName'"
    Write-Log "Script : '$ScriptName' started."
    Write-Log "Root   : '$scriptRoot'"
    Write-Log "User   : '$CurrentUser'"
    Write-Log "----------------------------------------------------------------"
}

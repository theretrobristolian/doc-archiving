function question-pdf {
    param (
        [string]$SourcePath,
        [string]$OutputPath,
        [string]$img2pdfPath
    )

    # Get all directories within the source path
    $directories = Get-ChildItem -Path $SourcePath -Directory

    # Prompt user for confirmation
    Write-Host "Warning: Do you need to make any last-minute changes before proceeding? Type (Y/N)" -ForegroundColor Yellow
    $confirmation = Read-Host
    if ($confirmation -eq "N") {
        Write-Output ""
        convert-topdf -SourcePath $SourcePath -OutputPath $OutputPath -img2pdfPath $img2pdfPath
    } elseif ($confirmation -eq "Y") {
        additionalactions
    } else {
        Write-Host "Invalid input. Script exited."
    }
}

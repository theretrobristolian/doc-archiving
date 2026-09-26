function ensure-foldersexist {
    param (
        [string[]]$Folders
    )

    foreach ($Folder in $Folders) {

        $FullPath = Join-Path $scriptRoot $Folder

        if (-not (Test-Path -Path $FullPath -PathType Container)) {

            New-Item `
                -ItemType Directory `
                -Path $FullPath `
                -Force | Out-Null

            Write-Log " - '$Folder' created."
        }
        else {
            Write-Log " - '$Folder' already exists."
        }
    }
}
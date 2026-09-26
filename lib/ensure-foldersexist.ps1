function ensure-foldersexist {
    param (
        [string[]]$Folders,
        [string]$RootPath = $PSScriptRoot
    )

    foreach ($Folder in $Folders) {
        $FullPath = Join-Path $RootPath $Folder

        if (-not (Test-Path $FullPath)) {
            New-Item -ItemType Directory -Path $FullPath -Force | Out-Null
            Write-Log " - '$Folder' created."
        }
        else {
            Write-Log " - '$Folder' already exists."
        }
    }
}
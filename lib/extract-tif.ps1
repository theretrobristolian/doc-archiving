function extract-tif {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$IrfanViewPath
    )

    $DocumentFolders = Get-ChildItem -Path $SourcePath -Directory

    foreach ($DocumentFolder in $DocumentFolders) {

        $DocumentName = $DocumentFolder.Name
        $DocumentDestination = Join-Path $DestinationPath $DocumentName

        if (Test-Path $DocumentDestination) {
            Write-Log " - Skipping $DocumentName because extraction folder already exists."
            continue
        }

        $TifFiles = Get-ChildItem -Path $DocumentFolder.FullName -Filter *.tif -File |
            Sort-Object Name

        if (-not $TifFiles) {
            Write-Log " - Skipping $DocumentName because no TIF files were found." "WARN"
            continue
        }

        New-Item -ItemType Directory -Path $DocumentDestination -Force | Out-Null
        Write-Log " - Extracting document folder: $DocumentName"

        $PageNumber = 1

        foreach ($File in $TifFiles) {

            $InputFile = $File.FullName
            $BaseName  = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)

            Write-Log "   - Extracting $($File.Name)..."

            & cmd.exe /c "`"$IrfanViewPath`" `"$InputFile`" /extract=`"($DocumentDestination\$BaseName,tif)`" /cmdexit"

            $ExtractedPages = Get-ChildItem -Path $DocumentDestination -Filter *.tif -File -Recurse |
                Where-Object { $_.Name -notmatch '^\d{3}\.tif$' } |
                Sort-Object FullName

            foreach ($Page in $ExtractedPages) {
                $NewName = "{0:D3}.tif" -f $PageNumber
                $NewPath = Join-Path $DocumentDestination $NewName

                Move-Item -Path $Page.FullName -Destination $NewPath -Force
                $PageNumber++
            }
        }

        Get-ChildItem -Path $DocumentDestination -Directory -Recurse |
            Sort-Object FullName -Descending |
            Remove-Item -Force
    }
}
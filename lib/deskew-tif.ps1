<#
.SYNOPSIS
Deskews extracted single-page TIFF files into the deskew output folder.

.DESCRIPTION
This function expects the extracted folder to contain one subfolder per document.

Example:
2 - Extracted\
    Document 1\
        Page001.tif
        Page002.tif

It creates a matching folder in the deskewed directory:

3 - Deskewed\
    Document 1\
        Page001.tif
        Page002.tif

If the destination document folder already exists, the document is skipped. This makes the process resumable and prevents already-processed documents being overwritten.

.PARAMETER SourcePath
The root folder containing extracted document folders.

.PARAMETER DeskewedPath
The root folder where deskewed document folders will be created.

.PARAMETER Deskew64Path
The full path to deskew.exe.

.EXAMPLE
Deskew-TIF -SourcePath $Extracted -DeskewedPath $Deskewed -Deskew64Path $deskew64
#>
function deskew-tif {
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DeskewedPath,

        [Parameter(Mandatory)]
        [string]$Deskew64Path
    )

    if (-not (Test-Path $SourcePath)) {
        Write-Log "Source path does not exist: $SourcePath"
        exit 1
    }

    if (-not (Test-Path $Deskew64Path)) {
        Write-Log "Deskew executable not found: $Deskew64Path"
        exit 1
    }

    $DocumentFolders = Get-ChildItem -Path $SourcePath -Directory

    if (-not $DocumentFolders) {
        Write-Log "No extracted document folders found in: $SourcePath"
        return
    }

    foreach ($DocumentFolder in $DocumentFolders) {

        $DocumentName = $DocumentFolder.Name
        $DocumentDestination = Join-Path $DeskewedPath $DocumentName

        if (Test-Path $DocumentDestination) {
            Write-Log " - Skipping $DocumentName because deskew folder already exists."
            continue
        }

        $TifFiles = Get-ChildItem -Path $DocumentFolder.FullName -Filter *.tif -File -Recurse | Sort-Object FullName
        
        if (-not $TifFiles) {
            Write-Log " - Skipping $DocumentName because no TIF files were found."
            continue
        }

        New-Item -ItemType Directory -Path $DocumentDestination -Force | Out-Null

        Write-Log " - Deskewing document folder: $DocumentName"

        foreach ($File in $TifFiles) {

            $RelativePath = $File.FullName.Substring($DocumentFolder.FullName.Length).TrimStart('\')
            $OutputFile = Join-Path $DocumentDestination $RelativePath
            $OutputFolder = Split-Path $OutputFile -Parent

            if (-not (Test-Path $OutputFolder)) {
                New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
            }

            Write-Log "   - Deskewing $RelativePath..."

            & $Deskew64Path `
                -t a `
                -a 10 `
                -b FFFFFF `
                -c tinput `
                -o $OutputFile `
                $File.FullName | Out-Null
        }
    }
}
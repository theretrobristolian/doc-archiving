function Convert-ToPDF {
    param (
        [string]$SourcePath,
        [string]$OutputPath,
        [string]$img2pdfPath
    )

    # Get all directories within the source path
    $directories = Get-ChildItem -Path $SourcePath -Directory

    # Process each directory to convert TIFF files to PDF
    foreach ($dir in $directories) {
        $tiffFiles = Get-ChildItem -Path $dir.FullName -Filter *.tif -File | Sort-Object Name
        Write-Output "Attempting to create PDFS:"
        Write-Output " - Directory found $dir, creating PDF..."

        # If there are TIFF files, construct the img2pdf command with all TIFF files as arguments
        if ($tiffFiles) {
            $pdfOutput = Join-Path -Path $OutputPath -ChildPath "$($dir.Name).pdf"
            $img2pdfArgs = @()
            foreach ($file in $tiffFiles) {
                $img2pdfArgs += '"' + $file.FullName + '"'
            }
            $img2pdfArgs += @('-o', $pdfOutput)
            
            # Execute the img2pdf command
            Write-Output "   - Merging..."
            & $img2pdfPath @img2pdfArgs
        }
    }
}

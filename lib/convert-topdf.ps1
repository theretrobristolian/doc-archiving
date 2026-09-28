function convert-topdf {
    param (
        [string]$SourcePath,
        [string]$OutputPath,
        [string]$img2pdfPath
    )

    $directories = Get-ChildItem -Path $SourcePath -Directory | Sort-Object Name

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    foreach ($dir in $directories) {
        $tiffFiles = @(
            Get-ChildItem -Path $dir.FullName -Filter *.tif -File |
            Sort-Object Name
        )

        Write-Output "Attempting to create PDFs:"
        Write-Output " - Directory found $($dir.Name), creating PDF..."

        if ($tiffFiles.Count -eq 0) {
            Write-Output "   - No TIFF files found. Skipping."
            continue
        }

        $pdfOutput = Join-Path -Path $OutputPath -ChildPath "$($dir.Name).pdf"
        $temporaryPdf = "$pdfOutput.incomplete"

        if (Test-Path -LiteralPath $temporaryPdf -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPdf -Force
        }

        # The inputs are trusted TIFFs created by this local workflow. The very
        # wide foldouts legitimately exceed Pillow's generic pixel-count warning
        # threshold, so tell img2pdf to allow them.
        $img2pdfArgs = @('--pillow-limit-break')
        $img2pdfArgs += @($tiffFiles.FullName)
        $img2pdfArgs += @('-o', $temporaryPdf)

        Write-Output "   - Merging $($tiffFiles.Count) TIFF files..."

        try {
            $img2pdfOutput = @(& $img2pdfPath @img2pdfArgs 2>&1)
            $img2pdfExitCode = $LASTEXITCODE

            if ($img2pdfOutput.Count -gt 0) {
                $img2pdfOutput | ForEach-Object {
                    Write-Output "     $_"
                }
            }

            if ($img2pdfExitCode -ne 0) {
                throw "img2pdf exited with code $img2pdfExitCode."
            }

            if (-not (Test-Path -LiteralPath $temporaryPdf -PathType Leaf)) {
                throw "img2pdf reported success but did not create '$temporaryPdf'."
            }

            $temporaryFile = Get-Item -LiteralPath $temporaryPdf

            if ($temporaryFile.Length -le 0) {
                throw "img2pdf created an empty PDF at '$temporaryPdf'."
            }

            Move-Item -LiteralPath $temporaryPdf -Destination $pdfOutput -Force

            $pdfFile = Get-Item -LiteralPath $pdfOutput
            $sizeMb = [math]::Round($pdfFile.Length / 1MB, 2)

            Write-Output "   - Created $($pdfFile.FullName) ($sizeMb MB)."
        }
        catch {
            if (Test-Path -LiteralPath $temporaryPdf -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPdf -Force
            }

            throw
        }
    }
}

function crop-imagesrecursively {
    param (
        [string]$SourcePath,
        [string]$CroppedPath,
        [Hashtable]$PaperSizes,
        [string]$ProfileName,
        [string]$IrfanViewPath,
        [ValidateSet(0, 1, 4)]
        [int]$TiffCompression
    )

    $tifFiles = Get-ChildItem -Path $SourcePath -Filter *.tif -Recurse -File |
                Sort-Object FullName

    write-log " - Paper profile: $ProfileName"
    write-log " - TIFF files found: $($tifFiles.Count)"

    $batchIniFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("doc-archiving-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $batchIniFolder -Force | Out-Null

    $batchIniFile = Join-Path $batchIniFolder "i_view64.ini"
    $unicodeEncoding = New-Object System.Text.UnicodeEncoding($false, $true)

    try {
        foreach ($file in $tifFiles) {
            $image = $null

            try {
                $image = [System.Drawing.Image]::FromFile($file.FullName)
                $width = $image.Width
                $height = $image.Height
            }
            finally {
                if ($null -ne $image) {
                    $image.Dispose()
                }
            }

            $closestSize = find-closestpapersize -Width $width -Height $height -PaperSizes $PaperSizes

            if ($null -eq $closestSize) {
                write-log " - [REVIEW] No '$ProfileName' paper size matches $($file.FullName) ($width x $height)."
                continue
            }

            if ($closestSize.PreserveWidth) {
                if ($closestSize.Rotated) {
                    $paperWidth = [int]$closestSize.OutputHeightPx
                    $paperHeight = $height
                }
                else {
                    $paperWidth = $width
                    $paperHeight = [int]$closestSize.OutputHeightPx
                }
            }
            elseif ($closestSize.Rotated) {
                $paperWidth = [int]$closestSize.OutputHeightPx
                $paperHeight = [int]$closestSize.OutputWidthPx
            }
            else {
                $paperWidth = [int]$closestSize.OutputWidthPx
                $paperHeight = [int]$closestSize.OutputHeightPx
            }

            $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
            $croppedFile = Join-Path -Path $CroppedPath -ChildPath $relativePath
            $destinationFolder = Split-Path -Path $croppedFile -Parent

            if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $destinationFolder | Out-Null
            }

            $horizontalAction = if ($width -gt $paperWidth) {
                "crop $($width - $paperWidth) px"
            }
            elseif ($width -lt $paperWidth) {
                "pad $($paperWidth - $width) px"
            }
            else {
                "unchanged"
            }

            $verticalAction = if ($height -gt $paperHeight) {
                "crop $($height - $paperHeight) px"
            }
            elseif ($height -lt $paperHeight) {
                "pad $($paperHeight - $height) px"
            }
            else {
                "unchanged"
            }

            write-log " - $($file.Name): $($closestSize.Name), $width x $height -> $paperWidth x $paperHeight; horizontal $horizontalAction; vertical $verticalAction."

            # IrfanView's advanced-batch canvas method can both crop and pad to an
            # exact total size. CanvCorner=4 centres the image and CanvColor uses
            # IrfanView's decimal BGR value for white.
            $batchIniLines = @(
                "; UNICODE FILE - edit with care ;-)"
                ""
                "[Batch]"
                "AdvCrop=0"
                "AdvResize=0"
                "AdvCanvas=1"
                "AdvOverwrite=1"
                "AdvAllPages=1"
                "UseAdvanced=1"
                ""
                "[Effects]"
                "CanvMethod=1"
                "CanvInside=1"
                "CanvW=$paperWidth"
                "CanvH=$paperHeight"
                "CanvCorner=4"
                "CanvColor=16777215"
                ""
                "[TIFF]"
                "Save Compression=$TiffCompression"
                "SaveAllPages=1"
                "GrayPalette=1"
            )

            [System.IO.File]::WriteAllLines($batchIniFile, [string[]]$batchIniLines, $unicodeEncoding)

            $arguments = @(
                $file.FullName
                "/ini=$batchIniFolder"
                "/advancedbatch"
                "/tifc=$TiffCompression"
                "/convert=$croppedFile"
                "/cmdexit"
            )

            & $IrfanViewPath @arguments | Out-Null

            if (-not (Test-Path -LiteralPath $croppedFile -PathType Leaf)) {
                throw "IrfanView did not create '$croppedFile'."
            }

            $outputImage = $null

            try {
                $outputImage = [System.Drawing.Image]::FromFile($croppedFile)
                $outputWidth = $outputImage.Width
                $outputHeight = $outputImage.Height
            }
            finally {
                if ($null -ne $outputImage) {
                    $outputImage.Dispose()
                }
            }

            if ($outputWidth -ne $paperWidth -or $outputHeight -ne $paperHeight) {
                throw "Crop verification failed for '$croppedFile'. Expected $paperWidth x $paperHeight, received $outputWidth x $outputHeight."
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $batchIniFolder -PathType Container) {
            Remove-Item -LiteralPath $batchIniFolder -Recurse -Force
        }
    }
}

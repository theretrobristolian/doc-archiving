function crop-imagesrecursively {
    param (
        [string]$SourcePath,
        [string]$CroppedPath,
        [Hashtable]$PaperSizes,
        [string]$ProfileName,
        [string]$IrfanViewPath
    )

    $tifFiles = Get-ChildItem -Path $SourcePath -Filter *.tif -Recurse -File |
                Sort-Object FullName

    write-log " - Paper profile: $ProfileName"
    write-log " - TIFF files found: $($tifFiles.Count)"

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

        # Positive offsets crop existing pixels. Negative offsets request equal
        # padding around a smaller scan. IrfanView writes the requested canvas.
        $x = [int][math]::Floor(($width - $paperWidth) / 2)
        $y = [int][math]::Floor(($height - $paperHeight) / 2)

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

        $arguments = @(
            $file.FullName
            "/crop=($x,$y,$paperWidth,$paperHeight)"
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

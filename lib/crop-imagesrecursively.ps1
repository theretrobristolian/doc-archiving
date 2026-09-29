function get-tiffcompressiontag {
    param (
        [System.Drawing.Image]$Image
    )

    try {
        $property = $Image.GetPropertyItem(259)
    }
    catch {
        return $null
    }

    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }

    switch ($property.Value.Length) {
        1 {
            return [int]$property.Value[0]
        }
        2 {
            return [int][System.BitConverter]::ToUInt16($property.Value, 0)
        }
        4 {
            return [int][System.BitConverter]::ToUInt32($property.Value, 0)
        }
        default {
            return $null
        }
    }
}

function get-cropworkitems {
    param (
        [string]$SourcePath,
        [string]$CroppedPath,
        [int]$DefaultTiffCompression
    )

    $sourceRoot = (Resolve-Path -LiteralPath $SourcePath).Path.TrimEnd('\')
    $tifFiles = Get-ChildItem -Path $sourceRoot -Filter *.tif -Recurse -File |
                Sort-Object FullName

    $workItems = foreach ($file in $tifFiles) {
        $relativePath = $file.FullName.Substring($sourceRoot.Length)
        $relativePath = $relativePath.TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )

        $pathParts = @($relativePath -split '[\\/]')
        $processingMode = 'default'
        $compression = $DefaultTiffCompression
        $convertToBlackWhite = $false
        $destinationRelativePath = $relativePath

        # Optional per-document folders:
        #   <document>\colour\       -> preserve colour/grayscale, force LZW
        #   <document>\black-white\  -> convert to 1 BPP, force CCITT Fax 4
        #
        # Both are flattened back into <cropped>\<document>\ for PDF ordering.
        if ($pathParts.Count -ge 3) {
            $documentName = $pathParts[0]
            $specialFolder = $pathParts[1]

            if ($specialFolder -ieq 'colour') {
                $processingMode = 'colour'
                $compression = 1
                $destinationRelativePath = Join-Path $documentName $file.Name
            }
            elseif ($specialFolder -ieq 'black-white') {
                $processingMode = 'black-white'
                $compression = 4
                $convertToBlackWhite = $true
                $destinationRelativePath = Join-Path $documentName $file.Name
            }
        }

        $destinationPath = Join-Path $CroppedPath $destinationRelativePath

        [pscustomobject]@{
            File                = $file
            RelativePath        = $relativePath
            DestinationPath     = $destinationPath
            DestinationKey      = $destinationPath.ToLowerInvariant()
            Mode                = $processingMode
            TiffCompression     = $compression
            ConvertToBlackWhite = $convertToBlackWhite
        }
    }

    $collisions = @(
        $workItems |
        Group-Object DestinationKey |
        Where-Object Count -gt 1
    )

    if ($collisions.Count -gt 0) {
        $collisionDetails = foreach ($collision in $collisions) {
            $sources = $collision.Group.File.FullName -join "', '"
            "'$($collision.Group[0].DestinationPath)' would receive '$sources'"
        }

        throw "Crop output filename collision detected. $($collisionDetails -join '; ')"
    }

    return @($workItems)
}

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

    $workItems = @(
        get-cropworkitems -SourcePath $SourcePath -CroppedPath $CroppedPath -DefaultTiffCompression $TiffCompression
    )

    $defaultCount = @($workItems | Where-Object Mode -eq 'default').Count
    $colourCount = @($workItems | Where-Object Mode -eq 'colour').Count
    $blackWhiteCount = @($workItems | Where-Object Mode -eq 'black-white').Count

    write-log " - Paper profile: $ProfileName"
    write-log " - TIFF files found: $($workItems.Count)"
    write-log "   - Default structure: $defaultCount"
    write-log "   - Colour/LZW: $colourCount"
    write-log "   - Black-white/CCITT Fax 4: $blackWhiteCount"

    $batchIniFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("doc-archiving-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $batchIniFolder -Force | Out-Null

    $batchIniFile = Join-Path $batchIniFolder "i_view64.ini"
    $unicodeEncoding = New-Object System.Text.UnicodeEncoding($false, $true)

    $compressionNames = @{
        0 = 'None'
        1 = 'LZW'
        4 = 'CCITT Fax 4'
    }

    $expectedCompressionTags = @{
        0 = 1
        1 = 5
        4 = 4
    }

    try {
        foreach ($workItem in $workItems) {
            $file = $workItem.File
            $effectiveCompression = [int]$workItem.TiffCompression
            $convertToBlackWhite = [bool]$workItem.ConvertToBlackWhite
            $compressionName = $compressionNames[$effectiveCompression]

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

            $croppedFile = $workItem.DestinationPath
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

            write-log " - $($file.Name): mode=$($workItem.Mode), compression=$compressionName, $($closestSize.Name), $width x $height -> $paperWidth x $paperHeight; horizontal $horizontalAction; vertical $verticalAction."

            $useBlackWhite = if ($convertToBlackWhite) { 1 } else { 0 }

            $batchIniLines = @(
                "; UNICODE FILE - edit with care ;-)"
                ""
                "[Batch]"
                "AdvCrop=0"
                "AdvResize=0"
                "AdvCanvas=1"
                "AdvOverwrite=1"
                "AdvAllPages=1"
                "AdvUseBPP=$useBlackWhite"
                "AdvBPP=2"
                "AdvUseFSDither=0"
                "UseAdvanced=1"
                ""
                "[BatchCanvas]"
                "CanvL=0"
                "CanvR=0"
                "CanvT=0"
                "CanvB=0"
                "CanvMethod=1"
                "CanvInside=1"
                "CanvW=$paperWidth"
                "CanvH=$paperHeight"
                "CanvCorner=4"
                "CanvColor=16777215"
                "CanvRatio=1"
                "CanvRatioEdit=1.00"
                "CanvBlur=0"
                ""
                "[TIFF]"
                "Save Compression=$effectiveCompression"
                "SaveAllPages=1"
                "GrayPalette=1"
            )

            [System.IO.File]::WriteAllLines($batchIniFile, [string[]]$batchIniLines, $unicodeEncoding)

            $arguments = @(
                $file.FullName
                "/ini=$batchIniFolder"
                "/advancedbatch"
                "/tifc=$effectiveCompression"
                "/convert=$croppedFile"
                "/cmdexit"
            )

            & $IrfanViewPath @arguments | Out-Null

            if (-not (Test-Path -LiteralPath $croppedFile -PathType Leaf)) {
                throw "IrfanView did not create '$croppedFile'."
            }

            $outputImage = $null
            $outputCompressionTag = $null

            try {
                $outputImage = [System.Drawing.Image]::FromFile($croppedFile)
                $outputWidth = $outputImage.Width
                $outputHeight = $outputImage.Height
                $outputPixelFormat = $outputImage.PixelFormat.ToString()
                $outputCompressionTag = get-tiffcompressiontag -Image $outputImage
            }
            finally {
                if ($null -ne $outputImage) {
                    $outputImage.Dispose()
                }
            }

            if ($outputWidth -ne $paperWidth -or $outputHeight -ne $paperHeight) {
                throw "Crop verification failed for '$croppedFile'. Expected $paperWidth x $paperHeight, received $outputWidth x $outputHeight."
            }

            if ($convertToBlackWhite -and $outputPixelFormat -ne 'Format1bppIndexed') {
                throw "Black-white verification failed for '$croppedFile'. Expected Format1bppIndexed, received $outputPixelFormat."
            }

            $expectedCompressionTag = $expectedCompressionTags[$effectiveCompression]

            if ($null -eq $outputCompressionTag) {
                write-log "   - [REVIEW] TIFF compression tag could not be read for $($file.Name)."
            }
            elseif ($outputCompressionTag -ne $expectedCompressionTag) {
                throw "Compression verification failed for '$croppedFile'. Expected TIFF compression tag $expectedCompressionTag, received $outputCompressionTag."
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $batchIniFolder -PathType Container) {
            Remove-Item -LiteralPath $batchIniFolder -Recurse -Force
        }
    }
}

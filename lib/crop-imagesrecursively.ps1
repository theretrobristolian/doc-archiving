function crop-imagesrecursively {
    param (
        [string]$SourcePath,
        [string]$CroppedPath,
        [Hashtable]$PaperSizes,
        [string]$IrfanViewPath
    )

    # Get all TIF files recursively within the source directory
    $tifFiles = Get-ChildItem -Path $SourcePath -Filter *.tif -Recurse -File | Sort-Object FullName

    foreach ($file in $tifFiles) {
        ### Console Output
        write-log " - Now Cropping $($file.FullName)..." # Console output to show progress through the source folder.

        # Get the dimensions of the image
        $image = [System.Drawing.Image]::FromFile($file.FullName)
        $width = $image.Width
        $height = $image.Height
        $image.Dispose()

        # Find the closest paper size
        $closestSize = find-closestpapersize -Width $width -Height $height -PaperSizes $PaperSizes

        if ($null -eq $closestSize) {
            # Calculate the differences for the closest size
            $closestDiff = $null
            foreach ($size in $PaperSizes.GetEnumerator()) {
                $diffWidth = [math]::Abs($size.Value[0] - $width)
                $diffHeight = [math]::Abs($size.Value[1] - $height)
                $totalDiff = $diffWidth + $diffHeight
                if ($null -eq $closestDiff -or $totalDiff -lt $closestDiff) {
                    $closestDiff = $totalDiff
                    $closestSize = $size
                }
            }
            #Write-Output " - $($file.FullName) not cropped."
            Write-Output "   No predefined paper size found within tolerance for dimensions Width=$width, Height=$height."
            $closestSizeName = $closestSize.Key
            Write-Output "   Closest size: $closestSizeName with difference $closestDiff."
            Write-Output ""
            continue
        }

        if ($closestSize.Rotated) {
            $paperWidth  = $closestSize.Height
            $paperHeight = $closestSize.Width
        }
        else {
            $paperWidth  = $closestSize.Width
            $paperHeight = $closestSize.Height
        }

        # Calculate the cropping dimensions
        $cropWidth = [math]::Min($width, $paperWidth)
        $cropHeight = [math]::Min($height, $paperHeight)

        # Construct the relative path to create the same structure in the destination folder
        $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
        $destinationFolder = Join-Path -Path $CroppedPath -ChildPath $relativePath | Split-Path -Parent

        if (-not (Test-Path -Path $destinationFolder -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $destinationFolder | Out-Null
        }

        $croppedFileName = Join-Path -Path $destinationFolder -ChildPath $file.Name

        # Calculate cropping offsets
        $widthDifference = $width - $paperWidth
        $heightDifference = $height - $paperHeight
        $x1 = [math]::Round($widthDifference / 2)
        $y1 = [math]::Round($heightDifference / 2)
        $x2 = $paperWidth
        $y2 = $paperHeight

        # Construct the crop command
        $command = "`"$IrfanViewPath`" `"$($file.FullName)`" /crop=($x1,$y1,$x2,$y2) /convert=`"$croppedFileName`" /cmdexit"

        # Execute the crop command
        & cmd.exe /c $command | Out-Null
    }
}

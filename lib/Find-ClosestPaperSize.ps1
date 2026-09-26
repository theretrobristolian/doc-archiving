function Find-ClosestPaperSize {
    param (
        [int]$Width,
        [int]$Height,
        [Hashtable]$PaperSizes
    )

    $closestSize = $null
    $closestDiff = [int]::MaxValue
    $closestRotated = $false

    foreach ($size in $PaperSizes.GetEnumerator()) {
        $paperWidth  = $size.Value[0]
        $paperHeight = $size.Value[1]
        $tolerance   = $size.Value[2]

        $normalDiff = [math]::Abs($Width - $paperWidth) +
                      [math]::Abs($Height - $paperHeight)

        $rotatedDiff = [math]::Abs($Width - $paperHeight) +
                       [math]::Abs($Height - $paperWidth)

        if ($normalDiff -le $rotatedDiff) {
            $totalDiff = $normalDiff
            $rotated = $false
        }
        else {
            $totalDiff = $rotatedDiff
            $rotated = $true
        }

        if ($totalDiff -le $tolerance -and $totalDiff -lt $closestDiff) {
            $closestDiff = $totalDiff
            $closestSize = $size
            $closestRotated = $rotated
        }
    }

    if ($null -eq $closestSize) {
        return $null
    }

    return [pscustomobject]@{
        Name    = $closestSize.Key
        Width   = $closestSize.Value[0]
        Height  = $closestSize.Value[1]
        Diff    = $closestDiff
        Rotated = $closestRotated
    }
}

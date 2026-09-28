function test-papersizeorientation {
    param (
        [int]$Width,
        [int]$Height,
        [Hashtable]$Definition
    )

    if ($Definition.ContainsKey('TotalTolerancePx')) {
        $difference = [math]::Abs($Width - [int]$Definition.MatchWidthPx) +
                      [math]::Abs($Height - [int]$Definition.MatchHeightPx)

        return [pscustomobject]@{
            Matches    = ($difference -le [int]$Definition.TotalTolerancePx)
            Difference = $difference
        }
    }

    $widthMatches = $Width -ge [int]$Definition.MinimumWidthPx -and
                    $Width -le [int]$Definition.MaximumWidthPx

    $heightMatches = $Height -ge [int]$Definition.MinimumHeightPx -and
                     $Height -le [int]$Definition.MaximumHeightPx

    if ([bool]$Definition.PreserveWidth) {
        $difference = [math]::Abs(
            $Height -
            [math]::Round(
                ([int]$Definition.MinimumHeightPx + [int]$Definition.MaximumHeightPx) / 2
            )
        )
    }
    else {
        $centreWidth = [math]::Round(
            ([int]$Definition.MinimumWidthPx + [int]$Definition.MaximumWidthPx) / 2
        )
        $centreHeight = [math]::Round(
            ([int]$Definition.MinimumHeightPx + [int]$Definition.MaximumHeightPx) / 2
        )

        $difference = [math]::Abs($Width - $centreWidth) +
                      [math]::Abs($Height - $centreHeight)
    }

    return [pscustomobject]@{
        Matches    = ($widthMatches -and $heightMatches)
        Difference = $difference
    }
}

function find-closestpapersize {
    param (
        [int]$Width,
        [int]$Height,
        [Hashtable]$PaperSizes
    )

    $closestSize = $null
    $closestDiff = [int]::MaxValue
    $closestRotated = $false

    foreach ($size in $PaperSizes.GetEnumerator()) {
        $definition = $size.Value

        $normal = test-papersizeorientation -Width $Width -Height $Height -Definition $definition
        $rotated = test-papersizeorientation -Width $Height -Height $Width -Definition $definition

        if ($normal.Matches -and $normal.Difference -lt $closestDiff) {
            $closestSize = $size
            $closestDiff = $normal.Difference
            $closestRotated = $false
        }

        if ($rotated.Matches -and $rotated.Difference -lt $closestDiff) {
            $closestSize = $size
            $closestDiff = $rotated.Difference
            $closestRotated = $true
        }
    }

    if ($null -eq $closestSize) {
        return $null
    }

    return [pscustomobject]@{
        Name           = $closestSize.Key
        OutputWidthPx  = $closestSize.Value.OutputWidthPx
        OutputHeightPx = $closestSize.Value.OutputHeightPx
        PreserveWidth  = [bool]$closestSize.Value.PreserveWidth
        Difference     = $closestDiff
        Rotated        = $closestRotated
    }
}

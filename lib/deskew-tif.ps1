<#
.SYNOPSIS
Safely deskews extracted single-page TIFF files.

.DESCRIPTION
Runs Deskew in detection-only mode before changing each page. Corrections are
applied only when the detected angle falls within the configured safe range.
Pages with tiny, suspicious, failed or unparseable detections are copied to the
deskew output unchanged so the rest of the document pipeline can continue.

A percentage margin is excluded from detection to reduce false angles caused by
page borders, punched holes and scanner edges.

Existing destination document folders are skipped, keeping the process resumable.

.PARAMETER SourcePath
The root folder containing extracted document folders.

.PARAMETER DeskewedPath
The root folder where deskewed document folders will be created.

.PARAMETER Deskew64Path
The full path to the current, locally compiled deskew.exe.

.PARAMETER DetectionSearchAngle
The full angle range searched during detection. This remains wider than the
allowed correction range so suspicious large results can be identified and logged.

.PARAMETER MinimumCorrectionAngle
Angles below this value are considered insignificant and are copied unchanged.

.PARAMETER MaximumCorrectionAngle
Angles above this value are considered unsafe and are copied unchanged for review.

.PARAMETER DetectionMargins
Margins excluded from angle detection using Deskew's -m option.

.EXAMPLE
deskew-tif -SourcePath $Extracted -DeskewedPath $Deskewed -Deskew64Path $deskew64
#>
function deskew-tif {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DeskewedPath,

        [Parameter(Mandatory)]
        [string]$Deskew64Path,

        [ValidateRange(0.1, 45)]
        [double]$DetectionSearchAngle = 10.0,

        [ValidateRange(0, 45)]
        [double]$MinimumCorrectionAngle = 0.10,

        [ValidateRange(0.1, 45)]
        [double]$MaximumCorrectionAngle = 2.0,

        [AllowNull()]
        [string]$DetectionMargins = $null
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Source path does not exist: $SourcePath"
    }

    if (-not (Test-Path -LiteralPath $Deskew64Path -PathType Leaf)) {
        throw "Deskew executable not found: $Deskew64Path"
    }

    if ($MinimumCorrectionAngle -ge $MaximumCorrectionAngle) {
        throw "MinimumCorrectionAngle must be lower than MaximumCorrectionAngle."
    }

    if ($MaximumCorrectionAngle -gt $DetectionSearchAngle) {
        throw "MaximumCorrectionAngle cannot exceed DetectionSearchAngle."
    }

    $DocumentFolders = Get-ChildItem -LiteralPath $SourcePath -Directory

    if (-not $DocumentFolders) {
        write-log "No extracted document folders found in: $SourcePath"
        return
    }

    $MarginDescription = if ($DetectionMargins) {
        $DetectionMargins
    }
    else {
        "disabled"
    }

    $SafetyMessage = (
        " - Deskew safety limits: apply {0:N2} to {1:N2} degrees; " +
        "search +/-{2:N2} degrees; margins {3}."
    ) -f @(
        $MinimumCorrectionAngle,
        $MaximumCorrectionAngle,
        $DetectionSearchAngle,
        $MarginDescription
    )

    write-log $SafetyMessage

    foreach ($DocumentFolder in $DocumentFolders) {
        $DocumentName = $DocumentFolder.Name
        $DocumentDestination = Join-Path $DeskewedPath $DocumentName

        if (Test-Path -LiteralPath $DocumentDestination -PathType Container) {
            write-log " - Skipping $DocumentName because deskew folder already exists."
            continue
        }

        $TifFiles = Get-ChildItem -LiteralPath $DocumentFolder.FullName -Filter *.tif -File -Recurse |
            Sort-Object FullName

        if (-not $TifFiles) {
            write-log " - Skipping $DocumentName because no TIF files were found."
            continue
        }

        New-Item -ItemType Directory -Path $DocumentDestination -Force | Out-Null

        $AppliedCount = 0
        $UnchangedCount = 0
        $ReviewCount = 0

        write-log " - Deskewing document folder: $DocumentName"

        foreach ($File in $TifFiles) {
            $RelativePath = $File.FullName.Substring($DocumentFolder.FullName.Length).TrimStart('\')
            $OutputFile = Join-Path $DocumentDestination $RelativePath
            $OutputFolder = Split-Path $OutputFile -Parent

            if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
                New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
            }

            write-log "   - Detecting angle for $RelativePath..."

            $DetectionArguments = @(
                "-t", "a",
                "-a", ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $DetectionSearchAngle)),
                "-g", "d",
                "-s", "s"
            )

            if ($DetectionMargins) {
                $DetectionArguments += @("-m", $DetectionMargins)
            }

            $DetectionArguments += $File.FullName

            $DetectionOutput = @(& $Deskew64Path @DetectionArguments 2>&1)
            $DetectionExitCode = $LASTEXITCODE
            $DetectionText = ($DetectionOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

            if ($DetectionExitCode -ne 0) {
                Copy-Item -LiteralPath $File.FullName -Destination $OutputFile -Force
                $UnchangedCount++
                $ReviewCount++

                $DetectionError = ($DetectionText -replace '\s+', ' ').Trim()
                if ($DetectionError.Length -gt 500) {
                    $DetectionError = $DetectionError.Substring(0, 500) + "..."
                }

                write-log "     [REVIEW] Detection failed with exit code $DetectionExitCode; copied unchanged."
                if ($DetectionError) {
                    write-log "       Deskew output: $DetectionError"
                }

                continue
            }

            $AngleMatch = [regex]::Match(
                $DetectionText,
                'Skew angle found \[deg\]:\s*([+-]?(?:\d+(?:[\.,]\d*)?|[\.,]\d+))'
            )

            if (-not $AngleMatch.Success) {
                Copy-Item -LiteralPath $File.FullName -Destination $OutputFile -Force
                $UnchangedCount++
                $ReviewCount++
                write-log "     [REVIEW] No skew angle could be parsed; copied unchanged."
                continue
            }

            $AngleText = $AngleMatch.Groups[1].Value.Replace(',', '.')
            $DetectedAngle = 0.0
            $AngleParsed = [double]::TryParse(
                $AngleText,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$DetectedAngle
            )

            if (-not $AngleParsed) {
                Copy-Item -LiteralPath $File.FullName -Destination $OutputFile -Force
                $UnchangedCount++
                $ReviewCount++
                write-log "     [REVIEW] Invalid detected angle '$AngleText'; copied unchanged."
                continue
            }

            $AbsoluteAngle = [math]::Abs($DetectedAngle)
            $FormattedAngle = [string]::Format(
                [Globalization.CultureInfo]::InvariantCulture,
                "{0:F3}",
                $DetectedAngle
            )

            if ($AbsoluteAngle -lt $MinimumCorrectionAngle) {
                Copy-Item -LiteralPath $File.FullName -Destination $OutputFile -Force
                $UnchangedCount++
                write-log "     Angle $FormattedAngle degrees is insignificant; copied unchanged."
                continue
            }

            if ($AbsoluteAngle -gt $MaximumCorrectionAngle) {
                Copy-Item -LiteralPath $File.FullName -Destination $OutputFile -Force
                $UnchangedCount++
                $ReviewCount++
                write-log (
                    "     [REVIEW] Angle {0} degrees exceeds the {1:N2}-degree safety limit; copied unchanged." -f
                    $FormattedAngle,
                    $MaximumCorrectionAngle
                )
                continue
            }

            $DeskewArguments = @(
                "-t", "a",
                "-a", ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $DetectionSearchAngle)),
                "-l", ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $MinimumCorrectionAngle)),
                "-b", "FFFFFF",
                "-c", "tinput",
                "-o", $OutputFile
            )

            if ($DetectionMargins) {
                $DeskewArguments += @("-m", $DetectionMargins)
            }

            $DeskewArguments += $File.FullName

            $DeskewOutput = @(& $Deskew64Path @DeskewArguments 2>&1)
            $DeskewExitCode = $LASTEXITCODE

            if ($DeskewExitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
                Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue
                Copy-Item -LiteralPath $File.FullName -Destination $OutputFile -Force
                $UnchangedCount++
                $ReviewCount++
                $DeskewError = (($DeskewOutput | ForEach-Object { $_.ToString() }) -join " " -replace '\s+', ' ').Trim()
                if ($DeskewError.Length -gt 500) {
                    $DeskewError = $DeskewError.Substring(0, 500) + "..."
                }

                write-log "     [REVIEW] Deskew failed with exit code $DeskewExitCode; copied unchanged."
                if ($DeskewError) {
                    write-log "       Deskew output: $DeskewError"
                }
                continue
            }

            $AppliedCount++
            write-log "     Applied correction for detected angle $FormattedAngle degrees."
        }

        write-log (
            "   - Deskew summary for {0}: {1} corrected, {2} copied unchanged, {3} flagged for review." -f
            $DocumentName,
            $AppliedCount,
            $UnchangedCount,
            $ReviewCount
        )
    }
}

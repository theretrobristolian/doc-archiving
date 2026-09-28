<#
.SYNOPSIS
Archives scanned document folders into cleaned PDF output.

.DESCRIPTION
This script processes scanned documents through a staged folder workflow.

Each document should be placed into its own folder under:

1 - source

The script can then run these stages:

1. Extract multipage TIFF files into single-page TIFF files.
2. Deskew extracted pages using deskew.exe.
3. Crop deskewed pages back to expected paper sizes.
4. Combine final TIFF pages into PDF documents.

The workflow is designed to be resumable. Each stage checks whether the destination document folder already exists and skips that document if it has already been processed.

.SWITCHES
$Run_TIFF_Extraction
When set to "Y", extracts multipage TIFF files from each document folder in 1 - source into matching folders in 2 - extracted.

$Run_Deskew
When set to "Y", deskews files from 2 - extracted into matching folders in 3 - deskewed.

$Run_Crop
When set to "Y", crops files from 3 - deskewed into matching folders in 4 - cropped.

$Combine_to_PDF
When set to "Y", combines files from 4 - cropped into PDF files in 5 - pdfs.

.NOTES
Author: David Little as TheRetroBristolian 2026.
#>
Clear-Host                                                                  # This Clears the console output terminal
$scriptRoot = $PSScriptRoot; Set-Location -Path $scriptRoot | Out-Null      # This sets the script/console root to the folder this script is in.
$timer      = [System.Diagnostics.Stopwatch]::StartNew()                    # Start the timer
#region Switches, Variables, Global Variables, Config & Functions
### Switches
$Logging_Enabled     = $true                            # Master on/off for file logging
$Set_Compression     = "n"                              #(Y/N) - If Y the global variable applies, if N it will set to LZW as default.
$Run_TIFF_Extraction = "n"                              #(Y/N) - If Y the script will run the multipage TIF extraction.
$Run_Deskew          = "n"                              #(Y/N) - If Y then the deskewing of the extracted TIF files will process.
$Run_Crop            = "n"                              #(Y/N) - If Y the deskewed (straightened) TIF files will now be cropped to their nearest standard size (probably A4).
$Combine_to_PDF      = "n"                              #(Y/N) - If Y there will be a pause question, which you can progress past when ready, and combine the available TIF files into a PDF.

### Script specific variables
$Compression        = "LZW"                             #Set to either 'CCITT Fax 4' or 'None' or 'LZW'
$CommandName        = "Document Archiver Script"        # Command display name.
$ScriptName         = "doc-archiving"                   # Script and log name.

#Folder variables
$Source             = Join-Path $scriptRoot "1 - source"
$Extracted          = Join-Path $scriptRoot "2 - extracted"
$Deskewed           = Join-Path $scriptRoot "3 - deskewed"
$Cropped            = Join-Path $scriptRoot "4 - cropped"
$PDFs               = Join-Path $scriptRoot "5 - pdfs"

### Global Variables
$logPath            = "$scriptRoot\logs\$scriptname.log"# This gives the default path + name for the log location
$libDir             = "$scriptRoot\lib"                 # This specifies the local repo of functions to import them all
$FirstRunLog        = "$scriptRoot\logs\firstrun.log"
$AppsRoot           = Join-Path $scriptRoot "apps"
$deskew64           = Join-Path $AppsRoot "deskew\bin\deskew.exe"
$img2pdf            = Join-Path $AppsRoot "img2pdf\img2pdf.exe"

### Deskew safety settings
$DeskewDetectionSearchAngle  = 10.0     # Search widely enough to identify suspicious results.
$DeskewMinimumCorrectionAngle = 0.10    # Smaller angles are copied unchanged.
$DeskewMaximumCorrectionAngle = 2.0     # Larger angles are copied unchanged and flagged for review.
$DeskewDetectionMargins       = $null   # Optional for newer builds, for example "5,5,%".

### Define the compression type mapping
$compressionMapping = @{
      'CCITT Fax 4' = 4
              'LZW' = 1
             'None' = 0
}

### IrfanView specific variables
$IrfanView          = "C:\Program Files\IrfanView\i_view64.exe"
$IrfanViewIniPath   = $null # Optional: set to a specific INI file or folder; $null enables automatic discovery.

### Define Paper Profiles ###
# Profiles use 600-DPI pixel dimensions. Match dimensions identify the
# scanner/deskew output; output dimensions define the finished PDF page.
#
# Select "B&O-Service-Manual" when processing the custom B&O manual pages.
$PaperProfile = "Standard"

$PaperProfiles = @{
    'Standard' = @{
        'A4' = @{
            MatchWidthPx     = 4792
            MatchHeightPx    = 6846
            TotalTolerancePx = 330
            OutputWidthPx    = 4792
            OutputHeightPx   = 6846
            PreserveWidth    = $false
        }
        'A3' = @{
            MatchWidthPx     = 9268
            MatchHeightPx    = 6846
            TotalTolerancePx = 600
            OutputWidthPx    = 9268
            OutputHeightPx   = 6846
            PreserveWidth    = $false
        }
    }

    'B&O-Service-Manual' = @{
        'B&O-Standard' = @{
            MinimumWidthPx   = 4850
            MaximumWidthPx   = 5050
            MinimumHeightPx  = 6780
            MaximumHeightPx  = 7000
            OutputWidthPx    = 4950
            OutputHeightPx   = 6900
            PreserveWidth    = $false
        }
        'B&O-Wide' = @{
            MinimumWidthPx   = 9250
            MaximumWidthPx   = 9500
            MinimumHeightPx  = 6750
            MaximumHeightPx  = 7000
            OutputWidthPx    = 9413
            OutputHeightPx   = 6900
            PreserveWidth    = $false
        }
        'B&O-Foldout' = @{
            MinimumWidthPx   = 15000
            MaximumWidthPx   = [int]::MaxValue
            MinimumHeightPx  = 6750
            MaximumHeightPx  = 7050
            OutputWidthPx    = $null
            OutputHeightPx   = 6900
            PreserveWidth    = $true
        }
    }
}

if (-not $PaperProfiles.ContainsKey($PaperProfile)) {
    throw "Unknown paper profile '$PaperProfile'. Available profiles: $($PaperProfiles.Keys -join ', ')"
}

$ActivePaperSizes = $PaperProfiles[$PaperProfile]
### Default folders to create on first run
$RequiredFolders = @(
    "1 - source",
    "2 - extracted",
    "3 - deskewed",
    "4 - cropped",
    "5 - pdfs",
    "logs",
    "apps"
)

$Apps = @(
    @{
        Name = "img2pdf"
        Version = "0.6.0"
        Urls = @{
            x86   = "https://gitlab.mister-muffin.de/josch/img2pdf/releases/download/0.6.0/img2pdf.exe"
            x64   = "https://gitlab.mister-muffin.de/josch/img2pdf/releases/download/0.6.0/img2pdf.exe"
            ARM64 = "https://gitlab.mister-muffin.de/josch/img2pdf/releases/download/0.6.0/img2pdf.exe"
        }
    }
)

### Functions
#Load all functions
Get-ChildItem -Path $libDir -Filter '*.ps1' -File | ForEach-Object {
    . $_.FullName   # <-- dot-source so the function definitions enter this scope
}
#endregion
start-script
#region Pre-flight checks
write-log ""
write-log "Running Pre-req checks..."
write-log " - Checking OS Architecture..."
$OSArch  = get-osarchitecture
write-log "  - Detected: $OSArch"
#endregion
write-log ""
write-log "----------------------------------------------------------------"
write-log ""
#region First Run
write-log "Checking if First Run..."
if (-not (Test-Path $FirstRunLog)) {
    write-log " - First run detected, Performing initial setup..."
    write-log ""
    write-log "Checking default folder structure..."
    ensure-foldersexist -Folders $RequiredFolders
    write-log ""
    write-log "Checking if Irfanview is installed..."
    test-dependency `
        -Name "IrfanView" `
        -Path "C:\Program Files\IrfanView\i_view64.exe" `
        -DownloadPage "https://www.irfanview.com/"
    write-log ""
    write-log "Downloading required pre-req apps..."
    get-appdownloads -Apps $Apps -Architecture $OSArch -AppsRoot $AppsRoot

    New-Item -ItemType File -Path $FirstRunLog -Force | Out-Null         # Create the marker file
    }
    else {
    write-log " - Existing installation detected. Skipping setup."
    }
#endregion
write-log ""
write-log "----------------------------------------------------------------"
write-log ""
#region IrfanView configuration
write-log "Configuring IrfanView defaults..."

if ($Set_Compression -eq "Y") {
    $EffectiveCompression = $Compression
}
else {
    $EffectiveCompression = "LZW"
    write-log " - Compression defaulted to LZW."
}

if (-not $compressionMapping.ContainsKey($EffectiveCompression)) {
    throw "Unsupported TIFF compression type: $EffectiveCompression"
}

$CompressionNumber = $compressionMapping[$EffectiveCompression]

$DesiredIrfanViewSettings = @(
    @{ Section = "TIFF"; Key = "Save Compression"; Value = $CompressionNumber }
    @{ Section = "TIFF"; Key = "SaveAllPages";      Value = 1 }
    @{ Section = "TIFF"; Key = "GrayPalette";       Value = 1 }
    @{ Section = "Save"; Key = "SaveExtension";     Value = "tif" }
)

try {
    $inifile = get-irfanviewinifile -IrfanViewPath $IrfanView -OverridePath $IrfanViewIniPath
    write-log " - Active INI file: $inifile"
    write-log " - Setting TIFF compression to $EffectiveCompression ($CompressionNumber)."
    set-irfanviewinidefaults -IniFile $inifile -Settings $DesiredIrfanViewSettings
}
catch {
    write-log " - IrfanView configuration failed: $($_.Exception.Message)"
    throw
}
#endregion
write-log ""
write-log "----------------------------------------------------------------"
write-log ""
#region TIFF extraction from source to extracted folder
if ($Run_TIFF_Extraction -eq "Y") {
    write-log "Searching the Source directory '$Source' for documents to extract..."
    ### Call the function with global variables
    extract-tif -SourcePath $Source -DestinationPath $Extracted -IrfanViewPath $IrfanView
    }
    else {
    write-log "Skipping Multi-Page TIFF extraction."
}
#endregion
write-log ""
write-log "----------------------------------------------------------------"
write-log ""
#region Run the deskew process
write-log "Attempting to run the 'deskew process' on the directory $extracted..."
if ($Run_Deskew -eq "Y") {
    ### Call the function for deskewing TIF files
    write-log " - Searching..."
    $DeskewArguments = @{
        SourcePath = $Extracted
        DeskewedPath = $Deskewed
        Deskew64Path = $deskew64
        DetectionSearchAngle = $DeskewDetectionSearchAngle
        MinimumCorrectionAngle = $DeskewMinimumCorrectionAngle
        MaximumCorrectionAngle = $DeskewMaximumCorrectionAngle
        DetectionMargins = $DeskewDetectionMargins
    }

    deskew-tif @DeskewArguments
}
else {
    write-log " - Skipping deskew and straighten process."
}
#endregion
write-log ""
write-log "----------------------------------------------------------------"
write-log ""
#region somethingelse
write-log "Attempting Crop..."
if ($Run_Crop -eq "Y") {
    ### Call Crop-Images function
    crop-imagesrecursively -SourcePath $Deskewed -CroppedPath $Cropped -PaperSizes $ActivePaperSizes -ProfileName $PaperProfile -IrfanViewPath $IrfanView -TiffCompression $CompressionNumber
}
else {
    write-log " - Skipping crop of deskewed images back to correct size."

}
#endregion
write-log ""
write-log "----------------------------------------------------------------"
write-log ""
#region pdf merge

write-log "Attempting to combine to PDF..."
if ($Combine_to_PDF -eq "Y") {
    ### Call the function to start the process of combining to PDFs
    write-log "Searching the Cropped directory '$Cropped' for TIF files to convert and combine into PDFs..."
    question-pdf -SourcePath $Cropped -OutputPath $PDFs -img2pdfPath $img2pdf
}
else {
    write-log " - Skipping combining the cropped images to a PDF."

}
#endregion
write-log ""
exit-script                                          # Stop timer, write summary output, and exit cleanly.
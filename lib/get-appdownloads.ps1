# Download app function
function get-appdownloads {
    param (
        [array]$Apps,
        [string]$Architecture,
        [string]$AppsRoot
    )

    foreach ($App in $Apps) {
        if (-not $App.Urls.ContainsKey($Architecture)) {
            Write-log " - Skipping $($App.Name): no URL for $Architecture"
            continue
        }

        $DownloadUrl = $App.Urls[$Architecture]
        $FileName    = Split-Path $DownloadUrl -Leaf

        $AppFolder   = Join-Path $AppsRoot $App.Name
        $OutputFile  = Join-Path $AppFolder $FileName

        New-Item -ItemType Directory -Path $AppFolder -Force | Out-Null         # Create app folder
        write-log " - Downloading $($App.Name) $($App.Version) $Architecture..."
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutputFile
        write-log "  - Saved to: $OutputFile."
    }
}
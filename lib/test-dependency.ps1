function test-dependency {
    param (
        [string]$Name,
        [string]$Path,
        [string]$DownloadPage
    )

    if (-not (Test-Path $Path)) {
        write-log " - $Name not found at: $Path"
        write-log "   Please install manually first:"
        write-log "   $DownloadPage"
        exit 1
    }
    write-log " - $Name detected."
}
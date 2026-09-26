function set-irfanviewinidefaults {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IniFile,

        [Parameter(Mandatory)]
        [array]$Settings
    )

    if (-not (Test-Path -LiteralPath $IniFile -PathType Leaf)) {
        throw "IrfanView INI file not found: $IniFile"
    }

    $processName = if ([System.IO.Path]::GetFileName($IniFile) -ieq "i_view32.ini") {
        "i_view32"
    }
    else {
        "i_view64"
    }

    if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
        throw "Close IrfanView before updating '$IniFile'."
    }

    $backupFile = "$IniFile.original.bak"

    if (-not (Test-Path -LiteralPath $backupFile)) {
        Copy-Item -LiteralPath $IniFile -Destination $backupFile
        write-log " - Original INI backed up to: $backupFile"
    }
    else {
        write-log " - Original INI backup already exists: $backupFile"
    }

    if ((Get-Item -LiteralPath $IniFile).IsReadOnly) {
        throw "The IrfanView INI file is read-only: $IniFile"
    }

    $reader = [System.IO.StreamReader]::new(
        $IniFile,
        [System.Text.Encoding]::Default,
        $true
    )

    try {
        $content = $reader.ReadToEnd()
        $encoding = $reader.CurrentEncoding
    }
    finally {
        $reader.Dispose()
    }

    $crlf = ([string][char]13) + ([char]10)
    $lf = [string][char]10
    $cr = [string][char]13

    if ($content.Contains($crlf)) {
        $newLine = $crlf
    }
    elseif ($content.Contains($lf)) {
        $newLine = $lf
    }
    elseif ($content.Contains($cr)) {
        $newLine = $cr
    }
    else {
        $newLine = [Environment]::NewLine
    }

    $hadFinalNewLine = (
        $content.EndsWith($crlf) -or
        $content.EndsWith($lf) -or
        $content.EndsWith($cr)
    )

    $splitLines = [regex]::Split($content, '\r\n|\n|\r')

    if ($hadFinalNewLine -and $splitLines.Count -gt 1 -and $splitLines[-1] -eq "") {
        $splitLines = $splitLines[0..($splitLines.Count - 2)]
    }

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $splitLines) {
        $null = $lines.Add($line)
    }

    foreach ($setting in $Settings) {
        $settingArguments = @{
            Lines = $lines
            Section = [string]$setting.Section
            Key = [string]$setting.Key
            Value = [string]$setting.Value
        }

        set-inivalue @settingArguments
    }

    $updatedContent = [string]::Join($newLine, $lines)

    if ($hadFinalNewLine) {
        $updatedContent += $newLine
    }

    if ($updatedContent -ne $content) {
        [System.IO.File]::WriteAllText($IniFile, $updatedContent, $encoding)
        write-log " - IrfanView INI settings updated using $($encoding.EncodingName)."
    }
    else {
        write-log " - IrfanView INI settings already match the requested values."
    }

    $verificationLines = Get-Content -LiteralPath $IniFile

    foreach ($setting in $Settings) {
        $currentSection = $null
        $verified = $false
        $keyPattern = '^\s*' + [regex]::Escape([string]$setting.Key) + '\s*=(.*)$'

        foreach ($line in $verificationLines) {
            if ($line -match '^\s*\[([^\]]+)\]\s*$') {
                $currentSection = $matches[1]
                continue
            }

            if ($currentSection -ieq [string]$setting.Section -and $line -match $keyPattern) {
                $verified = ($matches[1].Trim() -eq [string]$setting.Value)
                break
            }
        }

        if (-not $verified) {
            throw "Verification failed for [$($setting.Section)] $($setting.Key). Restore from '$backupFile' if required."
        }

        write-log "   - Verified [$($setting.Section)] $($setting.Key)=$($setting.Value)"
    }
}

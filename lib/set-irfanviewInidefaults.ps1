function set-irfanviewInidefaults {
    param (
        [string]$IniFile,
        [int]$CompressionValue
    )

    $desired = @{
        "TIFF" = @{
            "Save Compression" = "$CompressionValue"
            "SaveAllPages"     = "1"
            "GrayPalette"      = "1"
        }
        "Save" = @{
            "SaveExtension" = "tif"
        }
    }

    $sections = [ordered]@{}
    $currentSection = $null

    foreach ($line in Get-Content -Path $IniFile) {

        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]

            if (-not $sections.Contains($currentSection)) {
                $sections[$currentSection] = [ordered]@{}
            }

            continue
        }

        if ($currentSection -and $line -match '^\s*([^=]+?)\s*=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2]

            $sections[$currentSection][$key] = $value
        }
    }

    foreach ($section in $desired.Keys) {

        if (-not $sections.Contains($section)) {
            $sections[$section] = [ordered]@{}
        }

        foreach ($key in $desired[$section].Keys) {
            $sections[$section][$key] = $desired[$section][$key]
        }
    }

    $output = @()

    foreach ($section in $sections.Keys) {
        $output += "[$section]"

        foreach ($key in $sections[$section].Keys) {
            $output += "$key=$($sections[$section][$key])"
        }

        $output += ""
    }

    $output | Set-Content -Path $IniFile -Encoding UTF8
 
    #Write-Log "IrfanView INI defaults applied."
}
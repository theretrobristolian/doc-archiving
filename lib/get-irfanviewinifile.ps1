function get-irfanviewinifile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IrfanViewPath,

        [string]$OverridePath
    )

    $iniName = if ([System.IO.Path]::GetFileName($IrfanViewPath) -ieq "i_view32.exe") {
        "i_view32.ini"
    }
    else {
        "i_view64.ini"
    }

    if ($OverridePath) {
        $candidate = if ([System.IO.Path]::GetExtension($OverridePath) -ieq ".ini") {
            $OverridePath
        }
        else {
            Join-Path $OverridePath $iniName
        }

        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "The configured IrfanView INI file does not exist: $candidate"
        }

        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $installFolder = Split-Path -Path $IrfanViewPath -Parent
    $installIni = Join-Path $installFolder $iniName

    if (Test-Path -LiteralPath $installIni -PathType Leaf) {
        $currentSection = $null
        $redirectFolder = $null

        foreach ($line in Get-Content -LiteralPath $installIni) {
            if ($line -match '^\s*\[([^\]]+)\]\s*$') {
                $currentSection = $matches[1]
                continue
            }

            if (
                $currentSection -ieq "Others" -and
                $line -match '^\s*INI_Folder\s*=(.*?)\s*$'
            ) {
                $redirectFolder = $matches[1].Trim().Trim('"')
                break
            }
        }

        if ($redirectFolder) {
            $redirectFolder = [Environment]::ExpandEnvironmentVariables($redirectFolder)

            if (-not [System.IO.Path]::IsPathRooted($redirectFolder)) {
                $redirectFolder = Join-Path $installFolder $redirectFolder
            }

            $redirectedIni = Join-Path $redirectFolder $iniName

            if (-not (Test-Path -LiteralPath $redirectedIni -PathType Leaf)) {
                throw "IrfanView redirects its settings to '$redirectFolder', but '$iniName' was not found there."
            }

            return (Resolve-Path -LiteralPath $redirectedIni).Path
        }

        return (Resolve-Path -LiteralPath $installIni).Path
    }

    $appDataIni = Join-Path (Join-Path $env:APPDATA "IrfanView") $iniName

    if (Test-Path -LiteralPath $appDataIni -PathType Leaf) {
        return (Resolve-Path -LiteralPath $appDataIni).Path
    }

    throw "No active IrfanView INI file was found. Checked the installation folder and '$appDataIni'."
}

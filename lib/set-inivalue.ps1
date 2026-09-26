function set-inivalue {
    [CmdletBinding()]
    param (
        [System.Collections.Generic.List[string]]$Lines,

        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Lines) {
        throw "The INI content collection cannot be null."
    }

    $sectionStart = -1
    $sectionEnd = $Lines.Count

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[([^\]]+)\]\s*$') {
            if ($sectionStart -ge 0) {
                $sectionEnd = $index
                break
            }

            if ($matches[1] -ieq $Section) {
                $sectionStart = $index
            }
        }
    }

    if ($sectionStart -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1] -ne "") {
            $null = $Lines.Add("")
        }

        $null = $Lines.Add("[$Section]")
        $null = $Lines.Add("$Key=$Value")
        return
    }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='

    for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
        if ($Lines[$index] -match $keyPattern) {
            $indent = [regex]::Match($Lines[$index], '^\s*').Value
            $Lines[$index] = "$indent$Key=$Value"
            return
        }
    }

    $Lines.Insert($sectionEnd, "$Key=$Value")
}

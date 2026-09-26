<#
.SYNOPSIS
Lightweight logger for console and optional file logging.

.DESCRIPTION
Defines a single function, write-log, that writes timestamped messages to the console.
If $Logging_Enabled is $true and $logPath is set in the caller’s scope, it also
appends the same line to the specified log file.

On first use it ensures the log folder exists; subsequent calls skip the check
(via a cached flag), keeping per-call overhead minimal.

.REQUIREMENTS
The following variables must exist in the caller’s scope before calling write-log:
  - $Logging_Enabled [Boolean]  : $true to enable file logging; $false for console-only.
  - $logPath          [String]  : Full path to the log file (e.g. "C:\Logs\run.log").

.PARAMETER Message
Object to log. If a collection (non-string IEnumerable) is passed, each item is logged
on its own line.

.INPUTS
System.Object. You can pipe objects to write-log.

.OUTPUTS
None. Writes to host and optionally to a file.

.EXAMPLE
# In your main script:
$Logging_Enabled = $true
$logPath = "$PSScriptRoot\logs\run.log"
. "$PSScriptRoot\lib\write-log.ps1"    # dot-source this file

write-log "Starting job"
1..3 | write-log
write-log @('first','second')

.EXAMPLE
# Disable file logging; console only:
$Logging_Enabled = $false
. "$PSScriptRoot\lib\write-log.ps1"
write-log "This only hits the console."

.NOTES
- Idempotent directory creation is performed once per session using $script:LogDirReady.
- Uses Add-Content for file logging and Write-Host for console output.
#>

[CmdletBinding()]
param()

# Cached flag so the directory check happens once per session
$script:LogDirReady = $false

function write-log {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object]$Message
    )
    process {
        if ($null -eq $Message) { return }

        # Ensure the log directory once, and only if file logging is enabled
        if ($Logging_Enabled -and $logPath -and -not $script:LogDirReady) {
            try {
                $dir = Split-Path -Path $logPath -Parent
                if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
                $script:LogDirReady = $true
            } catch { }
        }

        # If it's a collection (but not a string), log each item
        if ($Message -is [System.Collections.IEnumerable] -and -not ($Message -is [string])) {
            foreach ($item in $Message) { write-log $item }
            return
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "$timestamp  $Message"

        if ($Logging_Enabled) {
            try { Add-Content -Path $logPath -Value $line } catch { }
        }

        Write-Host $line
    }
}
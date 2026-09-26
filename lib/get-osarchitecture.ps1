# Detect OS architecture
function get-osarchitecture {
    switch ((Get-CimInstance Win32_Processor).Architecture) {
        0  { return "x86" }
        5  { return "ARM" }
        9  { return "x64" }
        12 { return "ARM64" }
        default { return "Unknown" }
    }
}
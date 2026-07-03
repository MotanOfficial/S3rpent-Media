# Shrinks PATH so cmd.exe can run Qt's qt_setup_tool_path.bat during Ninja builds.
# That batch does:  set PATH=C:\Qt\...\bin;%PATH%
# If PATH is huge (Anaconda, many dev tools), the expanded line exceeds ~8191 chars and you get:
#   "The input line is too long. The syntax of the command is incorrect."
#
# Optional: $env:S3_PATH_MAX_CHARS = "4000" to tune the cap.
function Limit-PathForQtCmdBatch {
    $maxChars = 3800
    if ($env:S3_PATH_MAX_CHARS -match '^\d+$') {
        $maxChars = [int]$env:S3_PATH_MAX_CHARS
    }
    if (-not $env:PATH -or $env:PATH.Length -le $maxChars) {
        return
    }
    $parts = $env:PATH -split ';' | Where-Object { $_ }
    $seen = @{}
    $uniq = New-Object System.Collections.Generic.List[string]
    foreach ($p in $parts) {
        if ($seen.ContainsKey($p)) { continue }
        $seen[$p] = $true
        $uniq.Add($p)
    }
    $len = 0
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $uniq.Count; $i++) {
        $p = $uniq[$i]
        $add = if ($out.Count -eq 0) { $p.Length } else { $p.Length + 1 }
        if ($len + $add -gt $maxChars) { break }
        $out.Add($p)
        $len += $add
    }
    $newPath = [string]::Join(';', $out)
    Write-Host "PATH trimmed for qmlimportscanner (cmd line limit): $($env:PATH.Length) -> $($newPath.Length) chars." -ForegroundColor DarkYellow
    $env:PATH = $newPath
}


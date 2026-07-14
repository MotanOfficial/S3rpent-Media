# Trims PATH to stay safely under cmd.exe's 8191-character limit.
# Qt's qmlimportscanner and qmlcachegen invoke cmd.exe internally for qt_setup_tool_path.bat,
# and will fail if the PATH exceeds the limit.

$script:MAX_PATH_LENGTH = 4000

function Limit-PathForQtCmdBatch {
    $path = [Environment]::GetEnvironmentVariable("PATH", "Process")
    if (-not $path) { return }

    $parts = $path -split ';'
    $total = ($parts | ForEach-Object { $_.Length + 1 } | Measure-Object -Sum).Sum

    if ($total -le $script:MAX_PATH_LENGTH) { return }

    $essentialPrefixes = @(
        "C:\Qt",
        "C:\Program Files\Microsoft Visual Studio",
        "C:\Program Files (x86)\Microsoft Visual Studio",
        "C:\Program Files\Microsoft Visual Studio\2022",
        "C:\Program Files (x86)\Windows Kits",
        "C:\Program Files\dotnet",
        "C:\Program Files\Git",
        "C:\vcpkg",
        "G:\b"
    )

    $essential = New-Object System.Collections.ArrayList
    $nonessential = New-Object System.Collections.ArrayList

    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $isEssential = $false
        foreach ($prefix in $essentialPrefixes) {
            if ($part.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $isEssential = $true
                break
            }
        }
        if ($isEssential) {
            $null = $essential.Add($part)
        } else {
            $null = $nonessential.Add($part)
        }
    }

    $newPath = ($essential -join ';')
    foreach ($part in $nonessential) {
        $candidate = "$newPath;$part"
        if ($candidate.Length -le $script:MAX_PATH_LENGTH) {
            $newPath = $candidate
        }
    }

    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Process")
    $saved = (($parts | Measure-Object).Count) - (($newPath -split ';' | Where-Object { $_ }).Count)
    Write-Host "PATH trimmed for qmlimportscanner (cmd line limit): $total -> $($newPath.Length) chars ($saved entries removed)." -ForegroundColor DarkGray
}

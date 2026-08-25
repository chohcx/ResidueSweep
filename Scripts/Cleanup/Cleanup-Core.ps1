function Test-ResidueSweepPathWithinRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    try {
        $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
        $fullRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Root)).TrimEnd('\')
    }
    catch { return $false }

    if ([string]::IsNullOrWhiteSpace($fullRoot) -or $fullRoot -eq [IO.Path]::GetPathRoot($fullRoot)) { return $false }
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith("$fullRoot\", [StringComparison]::OrdinalIgnoreCase)
}

function Get-ResidueSweepCleanupExclusions {
    param([string]$Path)

    $result = [PSCustomObject]@{ ExcludePaths = @(); ExcludePatterns = @('*.lock', '*.lck') }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }

    try {
        $configured = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.ExcludePaths = @($configured.ExcludePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $result.ExcludePatterns = @($result.ExcludePatterns + @($configured.ExcludePatterns) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    }
    catch { }
    return $result
}

function Get-ResidueSweepCleanupFileTarget {
    [CmdletBinding()]
    param([string[]]$CapabilityId)

    $targets = [Collections.Generic.List[object]]::new()
    $addTarget = {
        param($id, $path, $recurse = $true, $include = @('*'), $minimumAgeHours = 0, $mode = 'Quarantine')
        if ([string]::IsNullOrWhiteSpace([string]$path)) { return }
        [void]$targets.Add([PSCustomObject]@{
            CapabilityId   = $id
            Path           = [Environment]::ExpandEnvironmentVariables([string]$path)
            Recurse        = [bool]$recurse
            Include        = @($include)
            MinimumAgeHours = [int]$minimumAgeHours
            Mode           = $mode
        })
    }

    & $addTarget 'UserTemp' $env:TEMP $true @('*') 24
    & $addTarget 'WindowsTemp' (Join-Path $env:SystemRoot 'Temp') $true @('*') 24
    & $addTarget 'WindowsUpdateCache' (Join-Path $env:SystemRoot 'SoftwareDistribution\Download') $true @('*') 24 'ServiceQuarantine'
    & $addTarget 'DirectXShaderCache' (Join-Path $env:LOCALAPPDATA 'D3DSCache') $true @('*') 1
    & $addTarget 'NVIDIAShaderCache' (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache') $true @('*') 1
    & $addTarget 'NVIDIAShaderCache' (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache') $true @('*') 1
    & $addTarget 'NVIDIAShaderCache' (Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NV_Cache') $true @('*') 1
    & $addTarget 'ShellCaches' (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') $false @('thumbcache_*.db', 'iconcache_*.db') 0 'ExplorerQuarantine'
    & $addTarget 'ShellCaches' (Join-Path $env:LOCALAPPDATA 'IconCache.db') $false @('IconCache.db') 0 'ExplorerQuarantine'
    & $addTarget 'RecentItems' (Join-Path $env:APPDATA 'Microsoft\Windows\Recent') $true @('*') 0
    & $addTarget 'CrashReports' (Join-Path $env:LOCALAPPDATA 'CrashDumps') $true @('*') 0
    & $addTarget 'CrashReports' (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') $true @('*') 0
    & $addTarget 'CrashReports' (Join-Path $env:ProgramData 'Microsoft\Windows\WER') $true @('*') 0
    & $addTarget 'CrashReports' (Join-Path $env:SystemRoot 'Minidump') $true @('*') 0
    & $addTarget 'CrashReports' (Join-Path $env:SystemRoot 'MEMORY.DMP') $false @('MEMORY.DMP') 0
    & $addTarget 'DiagnosticLogs' (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\logs') $true @('*.log', '*.etl', '*.odl', '*.odlgz') 168
    & $addTarget 'DiagnosticLogs' (Join-Path $env:ProgramData 'Microsoft\Diagnosis\FeedbackArchive') $true @('*') 168
    & $addTarget 'DiagnosticLogs' (Join-Path $env:ProgramData 'Microsoft\Diagnosis\EventTranscript') $true @('*') 168
    & $addTarget 'DiagnosticLogs' (Join-Path $env:SystemRoot 'Panther') $true @('*.log', '*.xml', '*.etl') 720
    & $addTarget 'DiagnosticLogs' (Join-Path $env:SystemRoot 'Logs\MoSetup') $true @('*.log', '*.xml', '*.etl') 720
    & $addTarget 'DiagnosticLogs' (Join-Path $env:SystemRoot 'Logs\CBS') $true @('*.cab', '*.persist.log') 720
    & $addTarget 'DiagnosticLogs' (Join-Path $env:SystemRoot 'Logs\DISM') $true @('*.log', '*.bak') 720
    & $addTarget 'DiagnosticLogs' (Join-Path $env:SystemRoot 'msdownld.tmp') $true @('*') 168
    & $addTarget 'DevelopmentCaches' (Join-Path $env:LOCALAPPDATA 'NuGet\v3-cache') $true @('*') 24
    & $addTarget 'DevelopmentCaches' (Join-Path $env:LOCALAPPDATA 'NuGet\plugins-cache') $true @('*') 24
    & $addTarget 'DevelopmentCaches' (Join-Path $env:TEMP 'NuGetScratch') $true @('*') 24
    & $addTarget 'DevelopmentCaches' (Join-Path $env:LOCALAPPDATA 'npm-cache') $true @('*') 24
    & $addTarget 'DevelopmentCaches' (Join-Path $env:LOCALAPPDATA 'pip\Cache') $true @('*') 24
    & $addTarget 'DevelopmentCaches' (Join-Path $env:LOCALAPPDATA 'Yarn\Cache') $true @('*') 24
    & $addTarget 'NetworkAndSessionCaches' (Join-Path $env:SystemRoot 'ServiceProfiles\LocalService\AppData\Local\FontCache') $true @('*') 0 'ServiceQuarantine'
    & $addTarget 'NetworkAndSessionCaches' (Join-Path $env:SystemRoot 'System32\FNTCACHE.DAT') $false @('FNTCACHE.DAT') 0 'ServiceQuarantine'

    $chromiumRoots = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data')
    )
    $chromiumCachePaths = @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'GrShaderCache', 'ShaderCache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache')
    foreach ($browserRoot in $chromiumRoots) {
        if (-not (Test-Path -LiteralPath $browserRoot -PathType Container)) { continue }
        foreach ($relativeCachePath in @('GrShaderCache', 'GraphiteDawnCache', 'DawnGraphiteCache', 'component_crx_cache', 'extensions_crx_cache')) {
            & $addTarget 'BrowserCaches' (Join-Path $browserRoot $relativeCachePath) $true @('*') 24
        }
        & $addTarget 'CrashReports' (Join-Path $browserRoot 'Crashpad\reports') $true @('*') 24
        $profiles = @(Get-ChildItem -LiteralPath $browserRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -eq 'Guest Profile' -or $_.Name -like 'Profile *' })
        foreach ($profile in $profiles) {
            foreach ($relativeCachePath in $chromiumCachePaths) {
                & $addTarget 'BrowserCaches' (Join-Path $profile.FullName $relativeCachePath) $true @('*') 1
            }
        }
    }

    $firefoxRoot = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $firefoxRoot -PathType Container) {
        foreach ($profile in @(Get-ChildItem -LiteralPath $firefoxRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            & $addTarget 'BrowserCaches' (Join-Path $profile.FullName 'cache2') $true @('*') 1
            & $addTarget 'BrowserCaches' (Join-Path $profile.FullName 'startupCache') $true @('*') 1
        }
    }

    & $addTarget 'DownloadedInstallers' (Join-Path $env:USERPROFILE 'Downloads') $true @('*.iso', '*.esd', '*.wim', '*.msi', '*.msix', '*.msixbundle', '*.appx', '*.appxbundle', '*.exe', '*.zip', '*.7z', '*.rar') 168 'DetectionOnly'

    $systemDriveRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    foreach ($index in 0..9) {
        & $addTarget 'RecoveryFragments' (Join-Path $systemDriveRoot ('FOUND.{0:D3}' -f $index)) $true @('*') 0 'DetectionOnly'
    }

    & $addTarget 'WindowsUpgradeFiles' (Join-Path $systemDriveRoot 'Windows.old') $true @('*') 0 'DetectionOnly'
    & $addTarget 'WindowsUpgradeFiles' (Join-Path $systemDriveRoot '$WINDOWS.~BT') $true @('*') 0 'DetectionOnly'
    & $addTarget 'WindowsUpgradeFiles' (Join-Path $systemDriveRoot '$WINDOWS.~WS') $true @('*') 0 'DetectionOnly'

    if ($CapabilityId) { return @($targets | Where-Object { $CapabilityId -contains $_.CapabilityId }) }
    return @($targets)
}

function Get-ResidueSweepCleanupFiles {
    param(
        [Parameter(Mandatory)]$Target,
        [string]$QuarantineRoot,
        [string]$ExclusionsPath
    )

    $root = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$Target.Path)).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { return @() }

    $exclusions = Get-ResidueSweepCleanupExclusions -Path $ExclusionsPath
    $excludedPaths = @($exclusions.ExcludePaths + $QuarantineRoot | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
        try { [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$_)).TrimEnd('\') } catch { }
    })
    $cutoff = (Get-Date).AddHours(-[int]$Target.MinimumAgeHours)

    if (Test-Path -LiteralPath $root -PathType Leaf) {
        $candidates = @(Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue)
    }
    else {
        $parameters = @{ LiteralPath = $root; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
        if ($Target.Recurse) { $parameters.Recurse = $true }
        $candidates = @(Get-ChildItem @parameters)
    }

    @($candidates | Where-Object {
        $file = $_
        if (-not (Test-ResidueSweepPathWithinRoot -Path $file.FullName -Root $root)) { return $false }
        if ($file.LastWriteTime -gt $cutoff) { return $false }
        if (@($Target.Include | Where-Object { $file.Name -like $_ -or $file.FullName -like $_ }).Count -eq 0) { return $false }
        if (@($excludedPaths | Where-Object { $file.FullName.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or $file.FullName.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { return $false }
        if (@($exclusions.ExcludePatterns | Where-Object { $file.Name -like $_ -or $file.FullName -like $_ }).Count -gt 0) { return $false }
        return $true
    })
}

function Get-ResidueSweepCleanupReport {
    [CmdletBinding()]
    param(
        [string[]]$CapabilityId,
        [string]$QuarantineRoot,
        [string]$ExclusionsPath
    )

    foreach ($target in @(Get-ResidueSweepCleanupFileTarget -CapabilityId $CapabilityId)) {
        $errors = @()
        try {
            $files = @(Get-ResidueSweepCleanupFiles -Target $target -QuarantineRoot $QuarantineRoot -ExclusionsPath $ExclusionsPath -ErrorVariable +errors)
            $size = [long](($files | Measure-Object Length -Sum).Sum)
            $exists = $false
            try { $exists = Test-Path -LiteralPath $target.Path -ErrorAction Stop }
            catch { $errors += $_ }
            [PSCustomObject]@{
                CapabilityId = $target.CapabilityId
                Path         = $target.Path
                Mode         = $target.Mode
                Exists       = $exists
                FileCount    = $files.Count
                SizeBytes    = $size
                SizeMiB      = [Math]::Round($size / 1MB, 2)
                SkippedItems = $errors.Count
                Items        = @($files | ForEach-Object { [PSCustomObject]@{ Path = $_.FullName; SizeBytes = [long]$_.Length } })
            }
        }
        catch {
            [PSCustomObject]@{ CapabilityId = $target.CapabilityId; Path = $target.Path; Mode = $target.Mode; Exists = $false; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 1; Items = @() }
        }
    }
}

function Move-ResidueSweepCleanupToQuarantine {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string[]]$CapabilityId,
        [Parameter(Mandatory)][string]$QuarantineRoot,
        [string]$ExclusionsPath,
        [string[]]$ApprovedPath
    )

    $quarantineFullPath = [IO.Path]::GetFullPath($QuarantineRoot).TrimEnd('\')
    $runPath = Join-Path $quarantineFullPath (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    $results = [Collections.Generic.List[object]]::new()
    $approvedPaths = if ($ApprovedPath) { [Collections.Generic.HashSet[string]]::new([string[]]$ApprovedPath, [StringComparer]::OrdinalIgnoreCase) } else { $null }
    $targetIndex = 0

    foreach ($target in @(Get-ResidueSweepCleanupFileTarget -CapabilityId $CapabilityId | Where-Object Mode -ne 'DetectionOnly')) {
        $targetIndex++
        $root = [IO.Path]::GetFullPath([string]$target.Path).TrimEnd('\')
        foreach ($file in @(Get-ResidueSweepCleanupFiles -Target $target -QuarantineRoot $quarantineFullPath -ExclusionsPath $ExclusionsPath)) {
            if ($approvedPaths -and -not $approvedPaths.Contains($file.FullName)) { continue }
            $relativePath = if ($file.FullName.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { $file.Name } else { $file.FullName.Substring($root.Length).TrimStart('\') }
            $destination = Join-Path (Join-Path $runPath "Target$targetIndex") $relativePath
            $status = 'Preview'
            $errorMessage = $null

            if ($PSCmdlet.ShouldProcess($file.FullName, "Move to quarantine '$destination'")) {
                try {
                    $parent = Split-Path $destination -Parent
                    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Move-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
                    $status = 'Moved'
                }
                catch { $status = 'Failed'; $errorMessage = $_.Exception.Message }
            }

            [void]$results.Add([PSCustomObject]@{
                CapabilityId   = $target.CapabilityId
                OriginalRoot   = $root
                OriginalPath   = $file.FullName
                QuarantinePath = $destination
                SizeBytes      = [long]$file.Length
                Status         = $status
                Error          = $errorMessage
            })
        }
    }

    $moved = @($results | Where-Object Status -eq 'Moved')
    if ($moved.Count -gt 0) {
        $manifest = [PSCustomObject]@{ Version = '1.0'; CreatedAt = (Get-Date).ToString('o'); Items = $moved }
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runPath 'Manifest.json') -Encoding UTF8
    }
    return @($results)
}

function Get-ResidueSweepQuarantineHistory {
    param([Parameter(Mandatory)][string]$QuarantineRoot)

    if (-not (Test-Path -LiteralPath $QuarantineRoot -PathType Container)) { return @() }
    foreach ($manifestFile in @(Get-ChildItem -LiteralPath $QuarantineRoot -Filter 'Manifest.json' -File -Recurse -Force -ErrorAction SilentlyContinue)) {
        try {
            $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $items = @($manifest.Items | Where-Object {
                (Test-ResidueSweepPathWithinRoot -Path ([string]$_.QuarantinePath) -Root $manifestFile.Directory.FullName) -and
                    (Test-Path -LiteralPath ([string]$_.QuarantinePath) -PathType Leaf)
            })
            if ($items.Count -eq 0) { continue }
            [PSCustomObject]@{
                RunPath    = $manifestFile.Directory.FullName
                CreatedAt  = [datetime]$manifest.CreatedAt
                ItemCount  = $items.Count
                SizeBytes  = [long](($items | Measure-Object SizeBytes -Sum).Sum)
                SizeMiB    = [Math]::Round(([long](($items | Measure-Object SizeBytes -Sum).Sum)) / 1MB, 2)
            }
        }
        catch { }
    }
}

function Restore-ResidueSweepQuarantineRun {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$RunPath,
        [Parameter(Mandatory)][string]$QuarantineRoot
    )

    $runFullPath = [IO.Path]::GetFullPath($RunPath).TrimEnd('\')
    $quarantineFullPath = [IO.Path]::GetFullPath($QuarantineRoot).TrimEnd('\')
    if ($runFullPath.Equals($quarantineFullPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-ResidueSweepPathWithinRoot -Path $runFullPath -Root $quarantineFullPath)) { throw 'The selected quarantine run is outside the configured quarantine root.' }

    $manifestPath = Join-Path $runFullPath 'Manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'The quarantine manifest is missing.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $results = [Collections.Generic.List[object]]::new()

    foreach ($item in @($manifest.Items)) {
        $status = 'Preview'
        $errorMessage = $null
        if (-not (Test-ResidueSweepPathWithinRoot -Path ([string]$item.QuarantinePath) -Root $runFullPath) -or
            -not (Test-ResidueSweepPathWithinRoot -Path ([string]$item.OriginalPath) -Root ([string]$item.OriginalRoot))) {
            $status = 'Rejected'
            $errorMessage = 'Manifest path validation failed.'
        }
        elseif (Test-Path -LiteralPath ([string]$item.OriginalPath)) {
            $status = 'Conflict'
            $errorMessage = 'The original path already exists.'
        }
        elseif (-not (Test-Path -LiteralPath ([string]$item.QuarantinePath) -PathType Leaf)) {
            $status = 'Missing'
            $errorMessage = 'The quarantined file is missing.'
        }
        elseif ($PSCmdlet.ShouldProcess([string]$item.OriginalPath, 'Restore quarantined file')) {
            try {
                $parent = Split-Path ([string]$item.OriginalPath) -Parent
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Move-Item -LiteralPath ([string]$item.QuarantinePath) -Destination ([string]$item.OriginalPath) -ErrorAction Stop
                $status = 'Restored'
            }
            catch { $status = 'Failed'; $errorMessage = $_.Exception.Message }
        }
        [void]$results.Add([PSCustomObject]@{ OriginalPath = [string]$item.OriginalPath; Status = $status; Error = $errorMessage })
    }
    return @($results)
}

function Remove-ResidueSweepQuarantineRun {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$RunPath,
        [Parameter(Mandatory)][string]$QuarantineRoot
    )

    $runFullPath = [IO.Path]::GetFullPath($RunPath).TrimEnd('\')
    $quarantineFullPath = [IO.Path]::GetFullPath($QuarantineRoot).TrimEnd('\')
    if (-not (Test-ResidueSweepPathWithinRoot -Path $runFullPath -Root $quarantineFullPath)) { throw 'The selected quarantine run is outside the configured quarantine root.' }
    if ($PSCmdlet.ShouldProcess($runFullPath, 'Permanently delete quarantine run')) {
        Remove-Item -LiteralPath $runFullPath -Recurse -Force -ErrorAction Stop
    }
}

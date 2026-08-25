function Get-ResidueSweepMemoryReport {
    try {
        $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        [PSCustomObject]@{
            CapabilityId = 'MemoryTools'
            Path         = 'Physical memory'
            Mode         = 'Diagnostics'
            Exists       = $true
            FileCount    = 0
            SizeBytes    = [long]$memory.CacheBytes
            SizeMiB      = [Math]::Round(([long]$memory.CacheBytes) / 1MB, 2)
            SkippedItems = 0
            Detail       = 'Available {0:N0} MiB; standby {1:N0} MiB; modified {2:N0} MiB; nonpaged pool {3:N0} MiB' -f
                ([long]$memory.AvailableBytes / 1MB),
                (([long]$memory.StandbyCacheCoreBytes + [long]$memory.StandbyCacheNormalPriorityBytes + [long]$memory.StandbyCacheReserveBytes) / 1MB),
                ([long]$memory.ModifiedPageListBytes / 1MB),
                ([long]$memory.PoolNonpagedBytes / 1MB)
        }
    }
    catch {
        [PSCustomObject]@{ CapabilityId = 'MemoryTools'; Path = 'Physical memory'; Mode = 'Diagnostics'; Exists = $false; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 1; Detail = $_.Exception.Message }
    }
}

function Get-ResidueSweepRecycleBinReport {
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -match '^[A-Za-z]$' -and $_.Root -and (Test-Path -LiteralPath $_.Root) })) {
        $recyclePath = Join-Path $drive.Root '$Recycle.Bin'
        $errors = @()
        $files = if (Test-Path -LiteralPath $recyclePath -PathType Container) {
            @(Get-ChildItem -LiteralPath $recyclePath -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +errors)
        }
        else { @() }
        $size = [long](($files | Measure-Object Length -Sum).Sum)
        [PSCustomObject]@{
            CapabilityId = 'RecycleBin'
            Path         = $drive.Root
            Mode         = 'IrreversibleAction'
            Exists       = (Test-Path -LiteralPath $recyclePath -PathType Container)
            FileCount    = $files.Count
            SizeBytes    = $size
            SizeMiB      = [Math]::Round($size / 1MB, 2)
            SkippedItems = $errors.Count
            Detail       = 'Recycle Bin on drive {0}' -f $drive.Name
        }
    }
}

function Get-ResidueSweepNativeActionReport {
    param([Parameter(Mandatory)][ValidateSet('DeliveryOptimizationCache', 'StoreCache', 'NetworkAndSessionCaches')][string]$CapabilityId)

    switch ($CapabilityId) {
        'DeliveryOptimizationCache' {
            $entries = if (Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue) { @(Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue) } else { @() }
            $size = [long](($entries | Measure-Object FileSize -Sum).Sum)
            [PSCustomObject]@{ CapabilityId = $CapabilityId; Path = 'Windows Delivery Optimization cache'; Mode = 'NativeAction'; Exists = [bool](Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue); FileCount = $entries.Count; SizeBytes = $size; SizeMiB = [Math]::Round($size / 1MB, 2); SkippedItems = 0; Detail = 'Cleared with the Windows Delivery Optimization API' }
        }
        'StoreCache' {
            $wsreset = Join-Path $env:SystemRoot 'System32\wsreset.exe'
            [PSCustomObject]@{ CapabilityId = $CapabilityId; Path = $wsreset; Mode = 'NativeAction'; Exists = (Test-Path -LiteralPath $wsreset -PathType Leaf); FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 0; Detail = 'Reset with the Windows Store cache reset tool' }
        }
        'NetworkAndSessionCaches' {
            [PSCustomObject]@{ CapabilityId = $CapabilityId; Path = 'DNS, ARP and clipboard'; Mode = 'NativeAction'; Exists = $true; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 0; Detail = 'Explicit Windows cache flush; font files are quarantined separately' }
        }
    }
}

function Get-ResidueSweepInstallerOrphanReport {
    $installerPath = Join-Path $env:SystemRoot 'Installer'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Container)) { return @() }

    $referenced = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($registryPath in @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\*\Products\*\InstallProperties',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\*\Patches\*'
    )) {
        foreach ($key in @(Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue)) {
            foreach ($propertyName in @('LocalPackage', 'InstallSource')) {
                $value = [string]$key.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    try { [void]$referenced.Add([IO.Path]::GetFullPath($value)) } catch { }
                }
            }
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $installerPath -File -Force -ErrorAction SilentlyContinue | Where-Object Extension -in '.msi', '.msp')) {
        if ($referenced.Contains($file.FullName)) { continue }
        [PSCustomObject]@{
            CapabilityId = 'InstallerOrphans'
            Path         = $file.FullName
            Mode         = 'DetectionOnly'
            Exists       = $true
            FileCount    = 1
            SizeBytes    = [long]$file.Length
            SizeMiB      = [Math]::Round(([long]$file.Length) / 1MB, 2)
            SkippedItems = 0
            Detail       = 'Unreferenced candidate; manual verification required'
        }
    }
}

function Get-ResidueSweepDriverPackageReport {
    try {
        $activePackages = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($deviceDriver in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$deviceDriver.InfName)) { [void]$activePackages.Add([string]$deviceDriver.InfName) }
        }
        $drivers = @(Get-WindowsDriver -Online -All -ErrorAction Stop | Where-Object { -not $_.Inbox })
        foreach ($group in @($drivers | Group-Object ProviderName, ClassName, OriginalFileName)) {
            $ordered = @($group.Group | Sort-Object Date -Descending)
            for ($index = 0; $index -lt $ordered.Count; $index++) {
                $driver = $ordered[$index]
                $isValidatedCandidate = $index -gt 0 -and -not $activePackages.Contains([string]$driver.Driver) -and ([string]$driver.Driver -match '^oem\d+\.inf$')
                [PSCustomObject]@{
                    CapabilityId = 'DriverPackages'
                    Path         = [string]$driver.Driver
                    Mode         = if ($isValidatedCandidate) { 'ValidatedCandidate' } else { 'DetectionOnly' }
                    Exists       = $true
                    FileCount    = 1
                    SizeBytes    = [long]0
                    SizeMiB      = 0.0
                    SkippedItems = 0
                    Detail       = if ($isValidatedCandidate) { 'Older duplicate package not bound to a present device; eligible for cautious removal' } elseif ($index -eq 0) { 'Newest third-party package in group' } else { 'Older package is still bound or could not be validated' }
                }
            }
        }
    }
    catch {
        [PSCustomObject]@{ CapabilityId = 'DriverPackages'; Path = 'Windows driver store'; Mode = 'DetectionOnly'; Exists = $false; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 1; Detail = $_.Exception.Message }
    }
}

function Resolve-ResidueSweepExecutablePath {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded.StartsWith('"')) {
        $closingQuote = $expanded.IndexOf('"', 1)
        if ($closingQuote -gt 1) { return $expanded.Substring(1, $closingQuote - 1) }
    }
    $match = [regex]::Match($expanded, '^(.*?\.exe)(?:\s|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { return $match.Groups[1].Value.Trim('"') }
    return $null
}

function Get-ResidueSweepUninstallResidueReport {
    $records = [Collections.Generic.List[object]]::new()
    $installedLocations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $installedNames = [Collections.Generic.List[string]]::new()
    foreach ($uninstallPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        foreach ($entry in @(Get-ItemProperty -Path $uninstallPath -ErrorAction SilentlyContinue)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.InstallLocation)) {
                try { [void]$installedLocations.Add([IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$entry.InstallLocation)).TrimEnd('\')) } catch { }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.DisplayName)) { [void]$installedNames.Add(([string]$entry.DisplayName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()) }
        }
    }

    $protectedFolderNames = @('Microsoft', 'Packages', 'Programs', 'Temp', 'ConnectedDevicesPlatform', 'CrashDumps', 'D3DSCache', 'Publishers', 'VirtualStore')
    $folderCandidates = [Collections.Generic.List[object]]::new()
    foreach ($root in @($env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($protectedFolderNames -contains $directory.Name -or $directory.LastWriteTime -gt (Get-Date).AddDays(-90)) { continue }
            $fullPath = $directory.FullName.TrimEnd('\')
            if (@($installedLocations | Where-Object { $fullPath.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase) -or $_.StartsWith("$fullPath\", [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { continue }
            $normalizedName = ($directory.Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
            if ($normalizedName.Length -ge 4 -and @($installedNames | Where-Object { $_ -like "*$normalizedName*" -or $normalizedName -like "*$_*" }).Count -gt 0) { continue }
            [void]$folderCandidates.Add([PSCustomObject]@{ CapabilityId = 'UninstallResidue'; Path = "Folder: $fullPath"; Mode = 'DetectionOnly'; Exists = $true; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 0; Detail = 'Stale folder with no matching uninstall registration; manual verification required' })
        }
    }
    foreach ($candidate in @($folderCandidates | Select-Object -First 200)) { [void]$records.Add($candidate) }

    foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $executable = Resolve-ResidueSweepExecutablePath -CommandLine ([string]$service.PathName)
        if ($executable -and [IO.Path]::IsPathRooted($executable) -and -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            [void]$records.Add([PSCustomObject]@{ CapabilityId = 'UninstallResidue'; Path = "Service: $($service.Name)"; Mode = 'DetectionOnly'; Exists = $false; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 0; Detail = "Missing executable: $executable" })
        }
    }
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            foreach ($action in @($task.Actions)) {
                $executable = Resolve-ResidueSweepExecutablePath -CommandLine ([string]$action.Execute)
                if ($executable -and [IO.Path]::IsPathRooted($executable) -and -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
                    [void]$records.Add([PSCustomObject]@{ CapabilityId = 'UninstallResidue'; Path = "Task: $($task.TaskPath)$($task.TaskName)"; Mode = 'DetectionOnly'; Exists = $false; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 0; Detail = "Missing executable: $executable" })
                }
            }
        }
    }
    foreach ($runPath in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
        $key = Get-ItemProperty -LiteralPath $runPath -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($property in @($key.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            $executable = Resolve-ResidueSweepExecutablePath -CommandLine ([string]$property.Value)
            if ($executable -and [IO.Path]::IsPathRooted($executable) -and -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
                [void]$records.Add([PSCustomObject]@{ CapabilityId = 'UninstallResidue'; Path = "Startup: $($property.Name)"; Mode = 'DetectionOnly'; Exists = $false; FileCount = 0; SizeBytes = [long]0; SizeMiB = 0.0; SkippedItems = 0; Detail = "Missing executable: $executable" })
            }
        }
    }
    return @($records)
}

function Get-ResidueSweepCleanupDiagnostics {
    param(
        [Parameter(Mandatory)][string[]]$CapabilityId,
        [string]$QuarantineRoot,
        [string]$ExclusionsPath
    )

    $results = [Collections.Generic.List[object]]::new()
    foreach ($item in @(Get-ResidueSweepCleanupReport -CapabilityId $CapabilityId -QuarantineRoot $QuarantineRoot -ExclusionsPath $ExclusionsPath)) { [void]$results.Add($item) }
    if ($CapabilityId -contains 'RecycleBin') { foreach ($item in @(Get-ResidueSweepRecycleBinReport)) { [void]$results.Add($item) } }
    foreach ($nativeId in @($CapabilityId | Where-Object { $_ -in @('DeliveryOptimizationCache', 'StoreCache', 'NetworkAndSessionCaches') })) {
        foreach ($item in @(Get-ResidueSweepNativeActionReport -CapabilityId $nativeId)) { [void]$results.Add($item) }
    }
    if ($CapabilityId -contains 'InstallerOrphans') { foreach ($item in @(Get-ResidueSweepInstallerOrphanReport)) { [void]$results.Add($item) } }
    if ($CapabilityId -contains 'DriverPackages') { foreach ($item in @(Get-ResidueSweepDriverPackageReport)) { [void]$results.Add($item) } }
    if ($CapabilityId -contains 'UninstallResidue') { foreach ($item in @(Get-ResidueSweepUninstallResidueReport)) { [void]$results.Add($item) } }
    if ($CapabilityId -contains 'MemoryTools') { foreach ($item in @(Get-ResidueSweepMemoryReport)) { [void]$results.Add($item) } }
    return @($results)
}

function Invoke-ResidueSweepWithStoppedServices {
    param(
        [Parameter(Mandatory)][string[]]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $running = @()
    try {
        foreach ($serviceName in $Name) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                $running += $serviceName
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
            }
        }
        & $Action
    }
    finally {
        foreach ($serviceName in $running) { Start-Service -Name $serviceName -ErrorAction SilentlyContinue }
    }
}

function Find-ResidueSweepRamMap {
    $candidates = @(
        (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Tools\RAMMap.exe'),
        (Join-Path $env:ProgramFiles 'Sysinternals\RAMMap.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Sysinternals\RAMMap.exe')
    )
    $command = Get-Command RAMMap.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    return @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)
}

function Write-ResidueSweepCleanupActionHistory {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$QuarantineRoot
    )

    if (-not (Test-Path -LiteralPath $QuarantineRoot -PathType Container)) { New-Item -ItemType Directory -Path $QuarantineRoot -Force | Out-Null }
    [PSCustomObject]@{
        Timestamp    = (Get-Date).ToString('o')
        CapabilityId = $Result.CapabilityId
        Status       = $Result.Status
        Error        = $Result.Error
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $QuarantineRoot 'Actions.jsonl') -Encoding UTF8
}

function Invoke-ResidueSweepNativeCleanupAction {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateSet('DeliveryOptimizationCache', 'StoreCache', 'NetworkAndSessionCaches', 'RecycleBin', 'WindowsUpgradeFiles', 'MemoryTools')][string]$CapabilityId,
        [string[]]$RecycleDrive
    )

    if (-not $PSCmdlet.ShouldProcess($CapabilityId, 'Run Windows cleanup action')) { return [PSCustomObject]@{ CapabilityId = $CapabilityId; Status = 'Preview'; Error = $null } }
    try {
        switch ($CapabilityId) {
            'DeliveryOptimizationCache' {
                $command = Get-Command Delete-DeliveryOptimizationCache -ErrorAction Stop
                & $command -Force -ErrorAction Stop
            }
            'StoreCache' {
                $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wsreset.exe') -PassThru -Wait -ErrorAction Stop
                if ($process.ExitCode -ne 0) { throw "wsreset.exe exited with code $($process.ExitCode)." }
            }
            'NetworkAndSessionCaches' {
                if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) { Clear-DnsClientCache -ErrorAction Stop }
                else { & (Join-Path $env:SystemRoot 'System32\ipconfig.exe') /flushdns | Out-Null }
                & (Join-Path $env:SystemRoot 'System32\netsh.exe') interface ip delete arpcache | Out-Null
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.Clipboard]::Clear()
            }
            'RecycleBin' {
                $availableDrives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -match '^[A-Za-z]$' })
                $selectedDrives = if ($RecycleDrive) { @($availableDrives | Where-Object { $RecycleDrive -contains $_.Name -or $RecycleDrive -contains $_.Root }) } else { @() }
                if ($selectedDrives.Count -eq 0) { throw 'Select at least one Recycle Bin drive from the scan results.' }
                foreach ($drive in $selectedDrives) {
                    Clear-RecycleBin -DriveLetter $drive.Name -Force -ErrorAction SilentlyContinue
                }
            }
            'WindowsUpgradeFiles' {
                $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\Dism.exe') -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
                if ($process.ExitCode -ne 0) { throw "DISM exited with code $($process.ExitCode)." }
            }
            'MemoryTools' {
                $ramMap = @(Find-ResidueSweepRamMap | Select-Object -First 1)
                if ($ramMap.Count -eq 0) { throw 'RAMMap.exe was not found. Place the official Sysinternals RAMMap.exe in the ResidueSweep Tools folder.' }
                $process = Start-Process -FilePath $ramMap[0] -ArgumentList '-Et' -PassThru -Wait -ErrorAction Stop
                if ($process.ExitCode -ne 0) { throw "RAMMap.exe exited with code $($process.ExitCode)." }
            }
        }
        return [PSCustomObject]@{ CapabilityId = $CapabilityId; Status = 'Completed'; Error = $null }
    }
    catch { return [PSCustomObject]@{ CapabilityId = $CapabilityId; Status = 'Failed'; Error = $_.Exception.Message } }
}

function Invoke-ResidueSweepCleanupExecution {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string[]]$CapabilityId,
        [Parameter(Mandatory)][string]$QuarantineRoot,
        [string]$ExclusionsPath,
        [string[]]$RecycleDrive,
        [string[]]$ApprovedPath
    )

    $results = [Collections.Generic.List[object]]::new()
    $fileIds = @($CapabilityId | Where-Object { $_ -notin @('DeliveryOptimizationCache', 'StoreCache', 'RecycleBin', 'WindowsUpgradeFiles', 'MemoryTools', 'InstallerOrphans', 'DriverPackages', 'UninstallResidue', 'DownloadedInstallers', 'RecoveryFragments', 'CleanupSafety', 'QuarantineAndUndo') })
    $ordinaryIds = @($fileIds | Where-Object { $_ -notin @('WindowsUpdateCache', 'ShellCaches', 'NetworkAndSessionCaches') })
    if ($ordinaryIds.Count -gt 0) {
        foreach ($item in @(Move-ResidueSweepCleanupToQuarantine -CapabilityId $ordinaryIds -QuarantineRoot $QuarantineRoot -ExclusionsPath $ExclusionsPath -ApprovedPath $ApprovedPath -Confirm:$false -WhatIf:$WhatIfPreference)) { [void]$results.Add($item) }
    }
    if ($fileIds -contains 'WindowsUpdateCache') {
        $windowsUpdateAction = {
            foreach ($item in @(Move-ResidueSweepCleanupToQuarantine -CapabilityId WindowsUpdateCache -QuarantineRoot $QuarantineRoot -ExclusionsPath $ExclusionsPath -ApprovedPath $ApprovedPath -Confirm:$false -WhatIf:$WhatIfPreference)) { [void]$results.Add($item) }
        }
        if ($WhatIfPreference) { & $windowsUpdateAction }
        else { Invoke-ResidueSweepWithStoppedServices -Name @('bits', 'wuauserv') -Action $windowsUpdateAction }
    }
    if ($fileIds -contains 'NetworkAndSessionCaches') {
        $fontCacheAction = {
            foreach ($item in @(Move-ResidueSweepCleanupToQuarantine -CapabilityId NetworkAndSessionCaches -QuarantineRoot $QuarantineRoot -ExclusionsPath $ExclusionsPath -ApprovedPath $ApprovedPath -Confirm:$false -WhatIf:$WhatIfPreference)) { [void]$results.Add($item) }
        }
        if ($WhatIfPreference) { & $fontCacheAction }
        else { Invoke-ResidueSweepWithStoppedServices -Name @('FontCache') -Action $fontCacheAction }
    }
    if ($fileIds -contains 'ShellCaches') {
        $explorerWasRunning = @(Get-Process explorer -ErrorAction SilentlyContinue).Count -gt 0
        try {
            if ($explorerWasRunning -and -not $WhatIfPreference) { Stop-Process -Name explorer -Force -ErrorAction Stop }
            foreach ($item in @(Move-ResidueSweepCleanupToQuarantine -CapabilityId ShellCaches -QuarantineRoot $QuarantineRoot -ExclusionsPath $ExclusionsPath -ApprovedPath $ApprovedPath -Confirm:$false -WhatIf:$WhatIfPreference)) { [void]$results.Add($item) }
        }
        finally { if ($explorerWasRunning -and -not $WhatIfPreference) { Start-Process (Join-Path $env:SystemRoot 'explorer.exe') } }
    }

    foreach ($id in @($CapabilityId | Where-Object { $_ -in @('DeliveryOptimizationCache', 'StoreCache', 'NetworkAndSessionCaches', 'RecycleBin', 'WindowsUpgradeFiles', 'MemoryTools') })) {
        foreach ($item in @(Invoke-ResidueSweepNativeCleanupAction -CapabilityId $id -RecycleDrive $RecycleDrive -Confirm:$false -WhatIf:$WhatIfPreference)) {
            [void]$results.Add($item)
            if (-not $WhatIfPreference) { Write-ResidueSweepCleanupActionHistory -Result $item -QuarantineRoot $QuarantineRoot }
        }
    }
    return @($results)
}

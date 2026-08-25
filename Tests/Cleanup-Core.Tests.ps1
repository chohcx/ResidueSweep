BeforeAll {
    . (Join-Path $PSScriptRoot '..\Scripts\Cleanup\Cleanup-Core.ps1')
}

Describe 'ResidueSweep cleanup safety core' {
    It 'accepts descendants but rejects drive roots and sibling-prefix paths' {
        Test-ResidueSweepPathWithinRoot -Path 'C:\Safe\Cache\one.tmp' -Root 'C:\Safe\Cache' | Should -BeTrue
        Test-ResidueSweepPathWithinRoot -Path 'C:\Safe\Cache-Evil\one.tmp' -Root 'C:\Safe\Cache' | Should -BeFalse
        Test-ResidueSweepPathWithinRoot -Path 'C:\Windows\one.tmp' -Root 'C:\' | Should -BeFalse
    }

    It 'scans only old, non-excluded files inside an approved target' {
        $source = Join-Path $TestDrive 'source'
        New-Item -ItemType Directory -Path $source | Out-Null
        $oldFile = Join-Path $source 'old.tmp'
        $newFile = Join-Path $source 'new.tmp'
        $lockedFile = Join-Path $source 'skip.lock'
        Set-Content -LiteralPath $oldFile -Value 'old'
        Set-Content -LiteralPath $newFile -Value 'new'
        Set-Content -LiteralPath $lockedFile -Value 'locked'
        (Get-Item -LiteralPath $oldFile).LastWriteTime = (Get-Date).AddHours(-48)
        (Get-Item -LiteralPath $lockedFile).LastWriteTime = (Get-Date).AddHours(-48)
        $target = [PSCustomObject]@{ CapabilityId = 'Test'; Path = $source; Recurse = $true; Include = @('*'); MinimumAgeHours = 24; Mode = 'Quarantine' }

        $files = @(Get-ResidueSweepCleanupFiles -Target $target)

        $files.Count | Should -Be 1
        $files[0].FullName | Should -Be $oldFile
    }

    It 'moves approved files into a manifest-backed quarantine and restores them' {
        $source = Join-Path $TestDrive 'move-source'
        $quarantine = Join-Path $TestDrive 'quarantine'
        New-Item -ItemType Directory -Path $source | Out-Null
        $file = Join-Path $source 'one.tmp'
        Set-Content -LiteralPath $file -Value 'recoverable'
        (Get-Item -LiteralPath $file).LastWriteTime = (Get-Date).AddHours(-48)
        Mock Get-ResidueSweepCleanupFileTarget {
            [PSCustomObject]@{ CapabilityId = 'Test'; Path = $source; Recurse = $true; Include = @('*'); MinimumAgeHours = 24; Mode = 'Quarantine' }
        }

        $moveResult = @(Move-ResidueSweepCleanupToQuarantine -CapabilityId Test -QuarantineRoot $quarantine -Confirm:$false)
        $history = @(Get-ResidueSweepQuarantineHistory -QuarantineRoot $quarantine)

        $moveResult.Status | Should -Be 'Moved'
        Test-Path -LiteralPath $file | Should -BeFalse
        $history.Count | Should -Be 1

        $restoreResult = @(Restore-ResidueSweepQuarantineRun -RunPath $history[0].RunPath -QuarantineRoot $quarantine -Confirm:$false)
        $restoreResult.Status | Should -Be 'Restored'
        Get-Content -LiteralPath $file -Raw | Should -Match 'recoverable'
    }

    It 'refuses quarantine manifests outside the configured root' {
        $quarantine = Join-Path $TestDrive 'quarantine-root'
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $quarantine | Out-Null
        New-Item -ItemType Directory -Path $outside | Out-Null

        { Restore-ResidueSweepQuarantineRun -RunPath $outside -QuarantineRoot $quarantine -Confirm:$false } |
            Should -Throw '*outside the configured quarantine root*'
    }

    It 'moves only paths included in the reviewed scan snapshot' {
        $source = Join-Path $TestDrive 'snapshot-source'
        $quarantine = Join-Path $TestDrive 'snapshot-quarantine'
        New-Item -ItemType Directory -Path $source | Out-Null
        $approved = Join-Path $source 'approved.tmp'
        $arrivedLater = Join-Path $source 'arrived-later.tmp'
        Set-Content -LiteralPath $approved -Value 'approved'
        Set-Content -LiteralPath $arrivedLater -Value 'later'
        (Get-Item -LiteralPath $approved).LastWriteTime = (Get-Date).AddHours(-48)
        (Get-Item -LiteralPath $arrivedLater).LastWriteTime = (Get-Date).AddHours(-48)
        Mock Get-ResidueSweepCleanupFileTarget {
            [PSCustomObject]@{ CapabilityId = 'Test'; Path = $source; Recurse = $true; Include = @('*'); MinimumAgeHours = 24; Mode = 'Quarantine' }
        }

        $result = @(Move-ResidueSweepCleanupToQuarantine -CapabilityId Test -QuarantineRoot $quarantine -ApprovedPath $approved -Confirm:$false)

        $result.Count | Should -Be 1
        $result[0].OriginalPath | Should -Be $approved
        Test-Path -LiteralPath $arrivedLater | Should -BeTrue
    }

    It 'includes only rebuildable development download caches' {
        $targets = @(Get-ResidueSweepCleanupFileTarget -CapabilityId DevelopmentCaches)

        $targets.Count | Should -BeGreaterThan 0
        @($targets | Where-Object Mode -ne 'Quarantine').Count | Should -Be 0
        @($targets | Where-Object MinimumAgeHours -lt 24).Count | Should -Be 0
        @($targets.Path | Where-Object { $_ -match '\\.nuget\\packages|VisualStudio\\Packages|ProgramData\\Package Cache' }).Count | Should -Be 0
    }

    It 'includes the three supported NVIDIA shader cache locations as recoverable targets' {
        $targets = @(Get-ResidueSweepCleanupFileTarget -CapabilityId NVIDIAShaderCache)

        $targets.Count | Should -Be 3
        @($targets | Where-Object Mode -ne 'Quarantine').Count | Should -Be 0
        @($targets | Where-Object MinimumAgeHours -lt 1).Count | Should -Be 0
        $targets.Path | Should -Contain (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache')
        $targets.Path | Should -Contain (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache')
        $targets.Path | Should -Contain (Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NV_Cache')
    }

    It 'keeps downloaded installers and recovered disk fragments detection-only' {
        $targets = @(Get-ResidueSweepCleanupFileTarget -CapabilityId @('DownloadedInstallers', 'RecoveryFragments'))

        $targets.Count | Should -BeGreaterThan 0
        @($targets | Where-Object Mode -ne 'DetectionOnly').Count | Should -Be 0
        @($targets | Where-Object CapabilityId -eq 'DownloadedInstallers').Include | Should -Contain '*.iso'
        @($targets | Where-Object CapabilityId -eq 'DownloadedInstallers').Include | Should -Contain '*.msi'
    }

    It 'reports inaccessible targets without emitting path errors' {
        Mock Get-ResidueSweepCleanupFileTarget {
            [PSCustomObject]@{ CapabilityId = 'Test'; Path = 'C:\Denied'; Recurse = $true; Include = @('*'); MinimumAgeHours = 0; Mode = 'Quarantine' }
        }
        Mock Get-ResidueSweepCleanupFiles { @() }
        Mock Test-Path { throw [System.UnauthorizedAccessException]::new('denied') }

        $report = Get-ResidueSweepCleanupReport -CapabilityId Test -ErrorAction Stop

        $report.Exists | Should -BeFalse
        $report.SkippedItems | Should -Be 1
    }
}

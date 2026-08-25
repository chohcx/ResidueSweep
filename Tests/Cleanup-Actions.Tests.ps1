BeforeAll {
    . (Join-Path $PSScriptRoot '..\Scripts\Cleanup\Cleanup-Core.ps1')
    . (Join-Path $PSScriptRoot '..\Scripts\Cleanup\Cleanup-Actions.ps1')
}

Describe 'ResidueSweep cleanup actions' {
    It 'extracts quoted and unquoted executable paths without executing them' {
        Resolve-ResidueSweepExecutablePath -CommandLine '"C:\Program Files\Example\app.exe" --background' | Should -Be 'C:\Program Files\Example\app.exe'
        Resolve-ResidueSweepExecutablePath -CommandLine 'C:\Tools\agent.exe /service' | Should -Be 'C:\Tools\agent.exe'
        Resolve-ResidueSweepExecutablePath -CommandLine 'not-a-path' | Should -BeNullOrEmpty
    }

    It 'returns stable memory diagnostics from Windows performance data' {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                CacheBytes = 1048576
                AvailableBytes = 2097152
                StandbyCacheCoreBytes = 1048576
                StandbyCacheNormalPriorityBytes = 1048576
                StandbyCacheReserveBytes = 0
                ModifiedPageListBytes = 0
                PoolNonpagedBytes = 1048576
            }
        }

        $report = Get-ResidueSweepMemoryReport

        $report.SizeMiB | Should -Be 1
        $report.Detail | Should -Match 'Available'
    }

    It 'does not stop services or move files during a WhatIf execution' {
        Mock Get-ResidueSweepCleanupFileTarget {
            [PSCustomObject]@{ CapabilityId = 'WindowsUpdateCache'; Path = 'C:\Cache'; Mode = 'ServiceQuarantine' }
        }
        Mock Move-ResidueSweepCleanupToQuarantine {
            [PSCustomObject]@{ CapabilityId = 'WindowsUpdateCache'; Status = 'Preview' }
        }
        Mock Stop-Service {}
        Mock Start-Service {}

        $result = @(Invoke-ResidueSweepCleanupExecution -CapabilityId WindowsUpdateCache -QuarantineRoot 'C:\Quarantine' -WhatIf)

        $result.Status | Should -Be 'Preview'
        Should -Invoke Stop-Service -Times 0 -Exactly
        Should -Invoke Start-Service -Times 0 -Exactly
    }

    It 'does not run native cleanup commands in WhatIf mode' {
        Mock Clear-RecycleBin {}

        $result = Invoke-ResidueSweepNativeCleanupAction -CapabilityId RecycleBin -WhatIf

        $result.Status | Should -Be 'Preview'
        Should -Invoke Clear-RecycleBin -Times 0 -Exactly
    }

    It 'reports only real drive-letter recycle bins' {
        Mock Get-PSDrive {
            @(
                [PSCustomObject]@{ Name = 'C'; Root = $TestDrive }
                [PSCustomObject]@{ Name = 'Temp'; Root = $TestDrive }
            )
        }
        Mock Test-Path { param($LiteralPath) $LiteralPath -eq $TestDrive }

        $report = @(Get-ResidueSweepRecycleBinReport)

        $report.Count | Should -Be 1
        $report[0].Path | Should -Be $TestDrive
    }

    It 'previews Store cache reset without running wsreset' {
        Mock Start-Process {}

        $report = Get-ResidueSweepNativeActionReport -CapabilityId StoreCache

        $report.Mode | Should -Be 'NativeAction'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'never executes driver package removal' {
        Mock Invoke-ResidueSweepNativeCleanupAction {}

        $result = @(Invoke-ResidueSweepCleanupExecution -CapabilityId DriverPackages -QuarantineRoot 'C:\Quarantine')

        $result | Should -HaveCount 0
        Should -Invoke Invoke-ResidueSweepNativeCleanupAction -Times 0 -Exactly
        { Invoke-ResidueSweepNativeCleanupAction -CapabilityId DriverPackages } | Should -Throw
    }
}

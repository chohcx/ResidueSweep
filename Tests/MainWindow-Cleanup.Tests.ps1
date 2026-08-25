BeforeAll {
    . (Join-Path $PSScriptRoot '..\Scripts\GUI\MainWindow-Cleanup.ps1')
}

Describe 'ResidueSweep cleanup scan session state' {
    It 'shares the reviewed scan snapshot across independent event closures' {
        $state = New-ResidueSweepCleanupSessionState
        $testScanCurrent = ${function:Test-ResidueSweepCleanupScanCurrent}
        $scanClosure = { $state.LastScanIds = @('UserTemp', 'WindowsTemp') }.GetNewClosure()
        $cleanClosure = { & $testScanCurrent -State $state -SelectedId @('WindowsTemp', 'UserTemp') }.GetNewClosure()

        & $scanClosure

        & $cleanClosure | Should -BeTrue
        Test-ResidueSweepCleanupScanCurrent -State $state -SelectedId @('UserTemp') | Should -BeFalse
    }

    It 'groups scan results by cleanup capability and keeps details collapsed-ready' {
        $report = @(
            [PSCustomObject]@{ CapabilityId = 'UserTemp'; Mode = 'Quarantine'; Path = 'C:\Temp'; Exists = $true; FileCount = 2; SizeBytes = 3072; SkippedItems = 0; Detail = $null; Items = @(
                [PSCustomObject]@{ Path = 'C:\Temp\a.tmp'; SizeBytes = 1024 },
                [PSCustomObject]@{ Path = 'C:\Temp\b.tmp'; SizeBytes = 2048 }
            ) },
            [PSCustomObject]@{ CapabilityId = 'WindowsTemp'; Mode = 'Quarantine'; Path = 'C:\Windows\Temp'; Exists = $true; FileCount = 1; SizeBytes = 4096; SkippedItems = 0; Detail = $null; Items = @(
                [PSCustomObject]@{ Path = 'C:\Windows\Temp\c.tmp'; SizeBytes = 4096 }
            ) },
            [PSCustomObject]@{ CapabilityId = 'UserTemp'; Mode = 'Quarantine'; Path = 'D:\Temp'; Exists = $true; FileCount = 1; SizeBytes = 4096; SkippedItems = 0; Detail = $null; Items = @(
                [PSCustomObject]@{ Path = 'D:\Temp\d.tmp'; SizeBytes = 4096 }
            ) }
        )

        $groups = @(ConvertTo-ResidueSweepCleanupPreviewGroup -Report $report -NameById @{ UserTemp = 'User TEMP'; WindowsTemp = 'Windows Temp' })

        $groups.Count | Should -Be 2
        $groups[0].CapabilityName | Should -Be 'User TEMP'
        $groups[0].FileCount | Should -Be 3
        $groups[0].DetailItems.Count | Should -Be 3
        $groups[0].SizeText | Should -Be '7.0 KiB'
    }
}

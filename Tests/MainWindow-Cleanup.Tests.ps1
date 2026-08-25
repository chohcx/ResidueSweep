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
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Scripts\Cleanup\Cleanup-Core.ps1')
    . (Join-Path $PSScriptRoot '..\Scripts\GUI\KeepList.ps1')
}

Describe 'ResidueSweep visual keep list' {
    It 'saves selected paths without losing protected filename patterns' {
        $path = Join-Path $TestDrive 'CleanupExclusions.json'

        Save-ResidueSweepKeepList -Path $path -KeepPath @('C:\Work', 'C:\Games\Mods') -ExcludePattern @('*.lock', '*.lck')
        $saved = Get-ResidueSweepCleanupExclusions -Path $path

        $saved.ExcludePaths | Should -Be @('C:\Work', 'C:\Games\Mods')
        $saved.ExcludePatterns | Should -Contain '*.lock'
        $saved.ExcludePatterns | Should -Contain '*.lck'
    }
}

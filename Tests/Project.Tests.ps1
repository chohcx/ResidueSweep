Describe 'ResidueSweep project contracts' {
    BeforeAll {
        $script:RepoRoot = Split-Path $PSScriptRoot -Parent
        $script:Catalog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Config\Cleanup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Locale = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Config\Locales\zh-TW.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'contains only the standalone cleanup product entry points' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'ResidueSweep.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'ResidueSweep.cmd') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'Win11Debloat.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'WinWin.ps1') | Should -BeFalse
    }

    It 'keeps every catalog capability translated and fully classified' {
        @($script:Catalog.Capabilities | Where-Object { -not $script:Locale.Cleanup.PSObject.Properties[$_.Id] }).Count | Should -Be 0
        @($script:Catalog.Capabilities | Where-Object { -not $_.Status -or -not $_.Safety -or -not $_.Execution }).Count | Should -Be 0
    }

    It 'translates every static user-facing XAML value' {
        $attributes = @('AutomationProperties.Name', 'Content', 'Header', 'Text', 'Title', 'ToolTip')
        $missing = foreach ($schema in @('MainWindow.xaml', 'KeepListWindow.xaml')) {
            [xml]$xaml = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Schemas\$schema") -Raw
            foreach ($node in $xaml.SelectNodes('//*')) {
                foreach ($attribute in @($node.Attributes)) {
                    $value = [string]$attribute.Value
                    if ($attributes -notcontains $attribute.LocalName -or $value -notmatch '[A-Za-z]' -or $value -match '^\{|^ResidueSweep$') { continue }
                    if (-not $script:Locale.Strings.PSObject.Properties[$value]) { $value }
                }
            }
        }
        $missing | Should -BeNullOrEmpty
    }

    It 'keeps dangerous inventory checks detection-only and NVIDIA cleanup opt-in' {
        foreach ($id in @('InstallerOrphans', 'DriverPackages', 'UninstallResidue', 'DownloadedInstallers', 'RecoveryFragments')) {
            ($script:Catalog.Capabilities | Where-Object Id -eq $id).Execution | Should -Be 'Detection only'
        }
        ($script:Catalog.Capabilities | Where-Object Id -eq 'NVIDIAShaderCache').SelectedByDefault | Should -BeFalse
    }

    It 'keeps the launcher direct and Windows PowerShell 5.1 safe' {
        $launcherPath = Join-Path $script:RepoRoot 'ResidueSweep.cmd'
        $launcher = Get-Content -LiteralPath $launcherPath -Raw
        $launcher | Should -Match 'ResidueSweep\.ps1'
        $launcher | Should -Not -Match 'choice /c|:menu|Read-Host'
        @([IO.File]::ReadAllBytes($launcherPath) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'preserves the upstream MIT attribution' {
        Get-Content -LiteralPath (Join-Path $script:RepoRoot 'LICENSE') -Raw | Should -Match 'Copyright \(c\) 2020 Raphire'
        Get-Content -LiteralPath (Join-Path $script:RepoRoot 'NOTICE.md') -Raw | Should -Match 'Win11Debloat'
    }
}

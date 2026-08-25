BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    . (Join-Path $script:RepoRoot 'Scripts\Localization\Localization.ps1')
    . (Join-Path $script:RepoRoot 'Scripts\GUI\Theme.ps1')
    . (Join-Path $script:RepoRoot 'Scripts\GUI\Show-MainWindow.ps1')
}

Describe 'ResidueSweep UI contracts' {
    BeforeEach {
        $script:LocalesPath = Join-Path $script:RepoRoot 'Config\Locales'
        Initialize-ResidueSweepLocalization -Language 'zh-TW' | Out-Null
    }

    It 'loads the localized main window and required cleanup controls' {
        $xaml = Get-ResidueSweepLocalizedXaml -Path (Join-Path $script:RepoRoot 'Schemas\MainWindow.xaml')
        $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($xaml))
        try { $window = [Windows.Markup.XamlReader]::Load($reader) }
        finally { $reader.Close() }

        foreach ($name in @('LanguageBtn', 'ThemeBtn', 'CleanupCapabilityList', 'CleanupPreviewList', 'CleanupScanBtn', 'CleanupQuarantineBtn', 'CleanupRestoreBtn', 'CleanupPurgeBtn')) {
            $window.FindName($name) | Should -Not -BeNullOrEmpty
        }
        $window.Title | Should -Be 'ResidueSweep'
        $window.Close()
    }

    It 'persists an explicit theme preference' {
        $script:ResidueSweepTheme = $null
        $script:ResidueSweepThemePath = Join-Path $TestDrive 'theme.json'
        Set-ResidueSweepTheme -Theme Dark
        $script:ResidueSweepTheme = $null

        Get-ResidueSweepTheme | Should -Be 'Dark'
    }

    It 'sets the shared reload flag before closing the window' {
        $script:ResidueSweepReloadRequested = $false
        $window = [PSCustomObject]@{ WasClosed = $false }
        $window | Add-Member ScriptMethod Close { $this.WasClosed = $true }

        Request-ResidueSweepReload -Window $window

        $script:ResidueSweepReloadRequested | Should -BeTrue
        $window.WasClosed | Should -BeTrue
    }

    It 'wires direct language and theme clicks into the reload loop' {
        $showScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Scripts\GUI\Show-MainWindow.ps1') -Raw
        $entryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ResidueSweep.ps1') -Raw

        $showScript | Should -Match '\$languageButton\.Add_Click'
        $showScript | Should -Match '\$themeButton\.Add_Click'
        $showScript | Should -Match 'Request-ResidueSweepReload -Window \$window'
        $entryScript | Should -Match 'while \(\$script:ResidueSweepReloadRequested\)'
    }

    It 'enables crisp DPI rendering before opening the WPF window' {
        $entryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ResidueSweep.ps1') -Raw
        [xml]$xaml = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Schemas\MainWindow.xaml') -Raw

        $entryScript | Should -Match 'SetProcessDpiAwarenessContext'
        $xaml.Window.UseLayoutRounding | Should -Be 'True'
        $xaml.Window.SnapsToDevicePixels | Should -Be 'True'
        $xaml.Window.'TextOptions.TextFormattingMode' | Should -Be 'Display'
    }

    It 'uses a themed modern scrollbar without the numbered empty-state badge' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Schemas\MainWindow.xaml') -Raw

        $xaml | Should -Match 'x:Key="CleanupScrollThumb"'
        $xaml | Should -Match 'CornerRadius="4"'
        $xaml | Should -Not -Match '<TextBlock Text="1"'
    }
}

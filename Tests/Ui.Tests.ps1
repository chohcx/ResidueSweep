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

        foreach ($name in @('LanguagePicker', 'ThemePicker', 'ApplySettingsBtn', 'CleanupCapabilityList', 'CleanupPreviewList', 'CleanupScanBtn', 'CleanupQuarantineBtn', 'CleanupOpenQuarantineBtn', 'CleanupRestoreBtn', 'CleanupPurgeBtn')) {
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

    It 'stages language and theme choices before applying them together' {
        $showScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Scripts\GUI\Show-MainWindow.ps1') -Raw
        $entryScript = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ResidueSweep.ps1') -Raw

        $showScript | Should -Match '\$applySettingsButton\.Add_Click'
        $showScript | Should -Match '\$languagePicker\.SelectedValue'
        $showScript | Should -Match '\$themePicker\.SelectedValue'
        $showScript | Should -Not -Match '\$languageButton\.Add_Click|\$themeButton\.Add_Click'
        $showScript | Should -Match '& \$requestReload -Window \$window'
        $entryScript | Should -Match 'while \(\$script:ResidueSweepReloadRequested\)'
    }

    It 'keeps the page compact without redundant heading descriptions' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Schemas\MainWindow.xaml') -Raw

        $xaml | Should -Not -Match '<TextBlock Text="ResidueSweep"'
        $xaml | Should -Not -Match 'Find hidden Windows caches and residual files'
        $xaml | Should -Not -Match 'Nothing changes until you scan, review, and confirm'
        $xaml | Should -Not -Match 'Only paths shown by the latest scan can be cleaned'
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

    It 'provides visual keep-list controls instead of asking for JSON edits' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Schemas\KeepListWindow.xaml') -Raw

        $xaml | Should -Match 'x:Name="AddFolderBtn"'
        $xaml | Should -Match 'x:Name="AddFileBtn"'
        $xaml | Should -Match 'x:Name="RemoveBtn"'
        $xaml | Should -Not -Match 'TextBox|JSON'
    }

    It 'keeps explicit typography styles readable in dark mode' {
        $xaml = Get-ResidueSweepLocalizedXaml -Path (Join-Path $script:RepoRoot 'Schemas\MainWindow.xaml')
        $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($xaml))
        try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
        Set-ResidueSweepThemeResources -Window $window -Theme Dark

        $window.FindName('CleanupSelectedCountText').Foreground.Color.ToString() | Should -Be '#FFFFFFFF'
        $window.Close()
    }

    It 'loads the UTF-8 localized XAML in Windows PowerShell 5.1' {
        $probe = @'
$ErrorActionPreference = 'Stop'
$root = '__ROOT__'
$script:LocalesPath = Join-Path $root 'Config\Locales'
. (Join-Path $root 'Scripts\Localization\Localization.ps1')
Initialize-ResidueSweepLocalization -Language 'zh-TW' | Out-Null
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$xaml = Get-ResidueSweepLocalizedXaml -Path (Join-Path $root 'Schemas\MainWindow.xaml')
$reader = [Xml.XmlReader]::Create([IO.StringReader]::new($xaml))
try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
$window.Close()
'@
        $probe = $probe.Replace('__ROOT__', $script:RepoRoot.Replace("'", "''"))
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))

        & powershell.exe -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $encoded 2>$null | Out-Null

        $LASTEXITCODE | Should -Be 0
    }
}

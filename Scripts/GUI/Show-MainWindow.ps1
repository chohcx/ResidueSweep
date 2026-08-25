function Request-ResidueSweepReload {
    param([Parameter(Mandatory)]$Window)
    $script:ResidueSweepReloadRequested = $true
    $Window.Close()
}

function Show-ResidueSweepWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = Get-ResidueSweepLocalizedXaml -Path $script:MainWindowSchema
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }

    $theme = Get-ResidueSweepTheme
    Set-ResidueSweepThemeResources -Window $window -Theme $theme

    $languageButton = $window.FindName('LanguageBtn')
    $themeButton = $window.FindName('ThemeBtn')
    $currentLanguage = if ($script:ResidueSweepLanguage -eq 'zh-TW') { Get-ResidueSweepText -Text 'Traditional Chinese' } else { 'English' }
    $languageButton.Content = Get-ResidueSweepText -Text 'Language: {0}' -Arguments @($currentLanguage)
    $themeButton.Content = Get-ResidueSweepText -Text 'Theme: {0}' -Arguments @((Get-ResidueSweepText -Text $theme))
    $nextLanguage = if ($script:ResidueSweepLanguage -eq 'zh-TW') { 'en-US' } else { 'zh-TW' }
    $nextTheme = if ($theme -eq 'Dark') { 'Light' } else { 'Dark' }

    $languageButton.Add_Click(({
        Set-ResidueSweepLanguage -Language $nextLanguage
        Request-ResidueSweepReload -Window $window
    }.GetNewClosure()))
    $themeButton.Add_Click(({
        Set-ResidueSweepTheme -Theme $nextTheme
        Request-ResidueSweepReload -Window $window
    }.GetNewClosure()))

    Initialize-ResidueSweepCleanup -Window $window -CatalogPath $script:CleanupCatalogPath -QuarantineRoot $script:QuarantineRoot
    $window.ShowDialog() | Out-Null
}

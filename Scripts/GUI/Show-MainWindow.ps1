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

    $languagePicker = $window.FindName('LanguagePicker')
    $themePicker = $window.FindName('ThemePicker')
    $applySettingsButton = $window.FindName('ApplySettingsBtn')
    $currentLanguage = $script:ResidueSweepLanguage
    $currentTheme = $theme
    $setLanguage = ${function:Set-ResidueSweepLanguage}
    $setTheme = ${function:Set-ResidueSweepTheme}
    $requestReload = ${function:Request-ResidueSweepReload}
    $languagePicker.SelectedValue = $currentLanguage
    $themePicker.SelectedValue = $currentTheme

    $updateApplyState = {
        $applySettingsButton.IsEnabled = ([string]$languagePicker.SelectedValue -ne $currentLanguage -or [string]$themePicker.SelectedValue -ne $currentTheme)
    }.GetNewClosure()
    $languagePicker.Add_SelectionChanged($updateApplyState)
    $themePicker.Add_SelectionChanged($updateApplyState)
    $applySettingsButton.Add_Click(({
        $selectedLanguage = [string]$languagePicker.SelectedValue
        $selectedTheme = [string]$themePicker.SelectedValue
        if ($selectedLanguage -eq $currentLanguage -and $selectedTheme -eq $currentTheme) { return }
        if ($selectedLanguage -ne $currentLanguage) { & $setLanguage -Language $selectedLanguage }
        if ($selectedTheme -ne $currentTheme) { & $setTheme -Theme $selectedTheme }
        & $requestReload -Window $window
    }.GetNewClosure()))

    Initialize-ResidueSweepCleanup -Window $window -CatalogPath $script:CleanupCatalogPath -QuarantineRoot $script:QuarantineRoot
    $window.ShowDialog() | Out-Null
}

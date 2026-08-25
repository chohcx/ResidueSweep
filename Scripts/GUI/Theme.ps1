function Get-ResidueSweepTheme {
    if ($script:ResidueSweepTheme -in @('Light', 'Dark')) { return $script:ResidueSweepTheme }

    if (-not $script:ResidueSweepThemePath) {
        $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResidueSweep'
        $script:ResidueSweepThemePath = Join-Path $root 'theme.json'
    }
    if (Test-Path -LiteralPath $script:ResidueSweepThemePath -PathType Leaf) {
        try {
            $saved = [string](Get-Content -LiteralPath $script:ResidueSweepThemePath -Raw | ConvertFrom-Json).Theme
            if ($saved -in @('Light', 'Dark')) { $script:ResidueSweepTheme = $saved; return $saved }
        }
        catch { }
    }

    $useLight = 1
    try { $useLight = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme }
    catch { }
    $script:ResidueSweepTheme = if ($useLight -eq 0) { 'Dark' } else { 'Light' }
    return $script:ResidueSweepTheme
}

function Set-ResidueSweepTheme {
    param([Parameter(Mandatory)][ValidateSet('Light', 'Dark')][string]$Theme)

    if (-not $script:ResidueSweepThemePath) {
        $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResidueSweep'
        $script:ResidueSweepThemePath = Join-Path $root 'theme.json'
    }
    $directory = Split-Path $script:ResidueSweepThemePath -Parent
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    @{ Theme = $Theme } | ConvertTo-Json | Set-Content -LiteralPath $script:ResidueSweepThemePath -Encoding UTF8
    $script:ResidueSweepTheme = $Theme
}

function Set-ResidueSweepThemeResources {
    param([Parameter(Mandatory)][System.Windows.Window]$Window, [Parameter(Mandatory)][ValidateSet('Light', 'Dark')][string]$Theme)

    $colors = if ($Theme -eq 'Dark') {
        @{ AppBg = '#202020'; CardBg = '#2B2B2B'; Fg = '#FFFFFF'; MutedFg = '#B5B5B5'; Border = '#454545'; Accent = '#0A84FF'; Hover = '#383838'; Disabled = '#777777' }
    }
    else {
        @{ AppBg = '#F3F3F3'; CardBg = '#FFFFFF'; Fg = '#161616'; MutedFg = '#616161'; Border = '#D8D8D8'; Accent = '#0067C0'; Hover = '#EEEEEE'; Disabled = '#9A9A9A' }
    }
    foreach ($entry in $colors.GetEnumerator()) {
        $Window.Resources[$entry.Key] = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($entry.Value))
    }
}

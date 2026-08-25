param(
    [ValidateSet('zh-TW', 'en-US')][string]$Language
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Error 'ResidueSweep requires Windows PowerShell 5.1 (powershell.exe).'
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $arguments = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Language) { $arguments += @('-Language', $Language) }
    try { Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop }
    catch { Write-Error "Administrator approval was not granted: $($_.Exception.Message)"; exit 1 }
    exit 0
}

trap {
    try {
        $failureRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResidueSweep'
        [IO.Directory]::CreateDirectory($failureRoot) | Out-Null
        ($_ | Out-String) | Set-Content -LiteralPath (Join-Path $failureRoot 'startup-error.log') -Encoding UTF8
    } catch {}
    exit 1
}

if (-not ('ResidueSweepDpi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ResidueSweepDpi
{
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
}
'@
}
[void][ResidueSweepDpi]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))

$script:Root = $PSScriptRoot
$script:CleanupCatalogPath = Join-Path $PSScriptRoot 'Config\Cleanup.json'
$script:CleanupExclusionsPath = Join-Path $PSScriptRoot 'Config\CleanupExclusions.json'
$script:LocalesPath = Join-Path $PSScriptRoot 'Config\Locales'
$script:MainWindowSchema = Join-Path $PSScriptRoot 'Schemas\MainWindow.xaml'
$script:KeepListSchema = Join-Path $PSScriptRoot 'Schemas\KeepListWindow.xaml'
$script:QuarantineRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResidueSweep\Quarantine'

. (Join-Path $PSScriptRoot 'Scripts\Localization\Localization.ps1')
. (Join-Path $PSScriptRoot 'Scripts\Cleanup\Cleanup-Core.ps1')
. (Join-Path $PSScriptRoot 'Scripts\Cleanup\Cleanup-Actions.ps1')
. (Join-Path $PSScriptRoot 'Scripts\GUI\Helpers.ps1')
. (Join-Path $PSScriptRoot 'Scripts\GUI\Theme.ps1')
. (Join-Path $PSScriptRoot 'Scripts\GUI\KeepList.ps1')
. (Join-Path $PSScriptRoot 'Scripts\GUI\MainWindow-Cleanup.ps1')
. (Join-Path $PSScriptRoot 'Scripts\GUI\Show-MainWindow.ps1')

Initialize-ResidueSweepLocalization -Language $Language | Out-Null
do {
    $script:ResidueSweepReloadRequested = $false
    Show-ResidueSweepWindow
} while ($script:ResidueSweepReloadRequested)

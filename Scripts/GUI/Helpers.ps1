function Invoke-DoEvents {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [Action]{ }
    )
}

function Show-MessageBox {
    param(
        [System.Windows.Window]$Owner,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('OK', 'YesNo')][string]$Button = 'OK',
        [ValidateSet('Information', 'Warning', 'Error', 'Question', 'Success')][string]$Icon = 'Information',
        [int]$Width
    )

    $buttonValue = [System.Windows.MessageBoxButton]::$Button
    $iconName = if ($Icon -eq 'Success') { 'Information' } else { $Icon }
    $iconValue = [System.Windows.MessageBoxImage]::$iconName
    $localizedTitle = Get-ResidueSweepText -Text $Title
    $localizedMessage = Get-ResidueSweepText -Text $Message

    if ($Owner) {
        return [System.Windows.MessageBox]::Show($Owner, $localizedMessage, $localizedTitle, $buttonValue, $iconValue).ToString()
    }
    return [System.Windows.MessageBox]::Show($localizedMessage, $localizedTitle, $buttonValue, $iconValue).ToString()
}

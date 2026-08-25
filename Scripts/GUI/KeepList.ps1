function Save-ResidueSweepKeepList {
    param([Parameter(Mandatory)][string]$Path, [string[]]$KeepPath, [string[]]$ExcludePattern)

    $payload = [ordered]@{
        Version         = '1.0'
        ExcludePaths    = @($KeepPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        ExcludePatterns = @($ExcludePattern | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    $temporaryPath = "$Path.tmp"
    [IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Show-ResidueSweepKeepList {
    param([Parameter(Mandatory)][System.Windows.Window]$Owner, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$SchemaPath)

    Add-Type -AssemblyName System.Windows.Forms
    $xaml = Get-ResidueSweepLocalizedXaml -Path $SchemaPath
    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($xaml))
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
    $window.Owner = $Owner
    Set-ResidueSweepThemeResources -Window $window -Theme (Get-ResidueSweepTheme)

    $configured = Get-ResidueSweepCleanupExclusions -Path $Path
    $saveKeepList = ${function:Save-ResidueSweepKeepList}
    $paths = [Collections.ObjectModel.ObservableCollection[string]]::new()
    foreach ($item in @($configured.ExcludePaths)) { $paths.Add([string]$item) }
    $list = $window.FindName('KeepList')
    $list.ItemsSource = $paths
    $removeButton = $window.FindName('RemoveBtn')
    $list.Add_SelectionChanged({ $removeButton.IsEnabled = $list.SelectedItems.Count -gt 0 }.GetNewClosure())

    $addPath = {
        param([string]$SelectedPath)
        if ([string]::IsNullOrWhiteSpace($SelectedPath)) { return }
        if (@($paths | Where-Object { $_.Equals($SelectedPath, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { $paths.Add($SelectedPath) }
    }.GetNewClosure()

    $window.FindName('AddFolderBtn').Add_Click({
        $dialog = [Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = Get-ResidueSweepText -Text 'Choose a folder to keep'
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { & $addPath $dialog.SelectedPath }
        $dialog.Dispose()
    }.GetNewClosure())
    $window.FindName('AddFileBtn').Add_Click({
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Title = Get-ResidueSweepText -Text 'Choose files to keep'
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog($window) -eq $true) { foreach ($file in $dialog.FileNames) { & $addPath $file } }
    }.GetNewClosure())
    $removeButton.Add_Click({ foreach ($item in @($list.SelectedItems)) { [void]$paths.Remove([string]$item) } }.GetNewClosure())
    $window.FindName('CancelBtn').Add_Click({ $window.Close() }.GetNewClosure())
    $window.FindName('SaveBtn').Add_Click({
        & $saveKeepList -Path $Path -KeepPath @($paths) -ExcludePattern @($configured.ExcludePatterns)
        $window.DialogResult = $true
    }.GetNewClosure())
    return $window.ShowDialog()
}

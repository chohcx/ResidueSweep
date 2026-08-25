function Format-ResidueSweepByteSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return '{0:N2} GiB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MiB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N1} KiB' -f ($Bytes / 1KB) }
    return '{0:N0} B' -f $Bytes
}

function ConvertTo-ResidueSweepCleanupPreviewGroup {
    param([object[]]$Report, [hashtable]$NameById)

    $buckets = [Collections.Specialized.OrderedDictionary]::new()
    foreach ($summary in @($Report)) {
        $id = [string]$summary.CapabilityId
        $key = if ($id -eq 'RecycleBin') { "$id|$($summary.Path)" } else { $id }
        if (-not $buckets.Contains($key)) { $buckets[$key] = [Collections.Generic.List[object]]::new() }
        $buckets[$key].Add($summary)
    }

    foreach ($key in $buckets.Keys) {
        $summaries = @($buckets[$key])
        $first = $summaries[0]
        $detailItems = @($summaries | ForEach-Object { @($_.Items) } | ForEach-Object {
            [PSCustomObject]@{ Path = $_.Path; SizeText = Format-ResidueSweepByteSize -Bytes ([long]$_.SizeBytes) }
        })
        if ($detailItems.Count -eq 0) {
            $detailItems = @($summaries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Path) } | ForEach-Object {
                [PSCustomObject]@{ Path = $_.Path; SizeText = Format-ResidueSweepByteSize -Bytes ([long]$_.SizeBytes) }
            })
        }
        $fileCount = [long](($summaries | Measure-Object FileCount -Sum).Sum)
        $sizeBytes = [long](($summaries | Measure-Object SizeBytes -Sum).Sum)
        $canSelect = ([string]$first.CapabilityId -eq 'RecycleBin')
        [PSCustomObject]@{
            CapabilityId   = [string]$first.CapabilityId
            CapabilityName = [string]$NameById[[string]$first.CapabilityId]
            IsSelected     = -not $canSelect
            CanSelect      = $canSelect
            Path           = $first.Path
            RawMode        = [string]$first.Mode
            Mode           = [string]$first.Mode
            FileCount      = $fileCount
            CountText      = $null
            SizeBytes      = $sizeBytes
            SizeText       = Format-ResidueSweepByteSize -Bytes $sizeBytes
            DetailItems    = $detailItems
            Exists         = @($summaries | Where-Object Exists).Count -gt 0
            SkippedItems   = [long](($summaries | Measure-Object SkippedItems -Sum).Sum)
            Detail         = $first.Detail
        }
    }
}

function New-ResidueSweepCleanupSessionState {
    [PSCustomObject]@{ LastScanIds = @(); ApprovedPaths = @() }
}

function Test-ResidueSweepCleanupScanCurrent {
    param([Parameter(Mandatory)]$State, [string[]]$SelectedId)

    $scanned = @($State.LastScanIds | Sort-Object -Unique)
    $selected = @($SelectedId | Sort-Object -Unique)
    return $scanned.Count -gt 0 -and ($scanned -join '|') -eq ($selected -join '|')
}

function Start-ResidueSweepCleanupFadeIn {
    param([Parameter(Mandatory)][System.Windows.UIElement]$Element)

    $animation = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, [TimeSpan]::FromMilliseconds(180))
    $animation.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]::new()
    $animation.EasingFunction.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $Element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation)
}

function Initialize-ResidueSweepCleanup {
    param(
        [System.Windows.Window]$Window,
        [string]$CatalogPath,
        [string]$QuarantineRoot
    )

    $capabilityList = $Window.FindName('CleanupCapabilityList')
    $previewList = $Window.FindName('CleanupPreviewList')
    $statusText = $Window.FindName('CleanupStatusText')
    $scanButton = $Window.FindName('CleanupScanBtn')
    $runButton = $Window.FindName('CleanupQuarantineBtn')
    $restoreButton = $Window.FindName('CleanupRestoreBtn')
    $purgeButton = $Window.FindName('CleanupPurgeBtn')
    $exclusionsButton = $Window.FindName('CleanupExclusionsBtn')
    $openQuarantineButton = $Window.FindName('CleanupOpenQuarantineBtn')
    $selectAllButton = $Window.FindName('CleanupSelectAllBtn')
    $clearSelectionButton = $Window.FindName('CleanupClearSelectionBtn')
    $selectedCountText = $Window.FindName('CleanupSelectedCountText')
    $resultCountText = $Window.FindName('CleanupResultCountText')
    $resultSizeText = $Window.FindName('CleanupResultSizeText')
    $historyCountText = $Window.FindName('CleanupHistoryCountText')
    $previewEmptyPanel = $Window.FindName('CleanupPreviewEmptyPanel')
    $previewEmptyText = $Window.FindName('CleanupPreviewEmptyText')
    $catalogById = @{}
    $nameById = @{}
    $sessionState = New-ResidueSweepCleanupSessionState
    $testScanCurrent = ${function:Test-ResidueSweepCleanupScanCurrent}
    $startFadeIn = ${function:Start-ResidueSweepCleanupFadeIn}
    $convertPreviewGroups = ${function:ConvertTo-ResidueSweepCleanupPreviewGroup}
    $showKeepList = ${function:Show-ResidueSweepKeepList}
    $exclusionsPath = $script:CleanupExclusionsPath
    $keepListSchema = $script:KeepListSchema

    $formatSize = ${function:Format-ResidueSweepByteSize}

    $updateHistoryButtons = {
        $history = @(Get-ResidueSweepQuarantineHistory -QuarantineRoot $QuarantineRoot | Sort-Object CreatedAt -Descending)
        $restoreButton.IsEnabled = $history.Count -gt 0
        $purgeButton.IsEnabled = $history.Count -gt 0
        $openQuarantineButton.IsEnabled = $history.Count -gt 0
        $historyCountText.Text = '{0:N0}' -f $history.Count
        return $history
    }.GetNewClosure()

    try {
        $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @($catalog.Capabilities | ForEach-Object {
            $catalogById[[string]$_.Id] = $_
            $localizedName = Get-ResidueSweepLocalizedValue -Section Cleanup -Id ([string]$_.Id) -Property Name -Fallback $_.Name
            $nameById[[string]$_.Id] = $localizedName
            [PSCustomObject]@{
                Id          = [string]$_.Id
                Area        = Get-ResidueSweepLocalizedValue -Section Cleanup -Id ([string]$_.Id) -Property Area -Fallback $_.Area
                Name        = $localizedName
                Status      = Get-ResidueSweepText -Text ([string]$_.Status)
                Safety      = Get-ResidueSweepLocalizedValue -Section Cleanup -Id ([string]$_.Id) -Property Safety -Fallback $_.Safety
                Execution   = Get-ResidueSweepText -Text ([string]$_.Execution)
                IsSelected  = [bool]$_.SelectedByDefault
                CanSelect   = ([string]$_.Execution -notin @('Configuration', 'History'))
            }
        })
        $capabilityList.ItemsSource = $items
        & $startFadeIn -Element $capabilityList
        $availableCount = @($catalog.Capabilities | Where-Object Status -eq 'Available').Count
        $detectionCount = @($catalog.Capabilities | Where-Object Status -eq 'Detection only').Count
        $statusText.Text = Get-ResidueSweepText -Text '{0} cleanup capabilities and {1} detection-only checks are available. Select targets, scan, review, then run.' -Arguments @($availableCount, $detectionCount)
        & $updateHistoryButtons | Out-Null
    }
    catch {
        $statusText.Text = Get-ResidueSweepText -Text 'Unable to load the cleanup catalog: {0}' -Arguments @($_.Exception.Message)
        $scanButton.IsEnabled = $false
        return
    }

    $getSelectedIds = {
        @($capabilityList.ItemsSource | Where-Object { $_.CanSelect -and $_.IsSelected } | ForEach-Object Id)
    }.GetNewClosure()

    $updateSelectionSummary = {
        $selectedCountText.Text = '{0:N0}' -f @(& $getSelectedIds).Count
    }.GetNewClosure()

    $invalidatePreview = {
        $sessionState.LastScanIds = @()
        $sessionState.ApprovedPaths = @()
        $runButton.IsEnabled = $false
        $previewList.ItemsSource = $null
        $previewEmptyPanel.Visibility = 'Visible'
        $previewEmptyText.Text = Get-ResidueSweepText -Text 'Run a scan to see files, records, and estimated space.'
        $resultCountText.Text = '--'
        $resultSizeText.Text = '--'
        & $updateSelectionSummary
    }.GetNewClosure()

    $selectAllButton.Add_Click({
        foreach ($item in @($capabilityList.ItemsSource | Where-Object CanSelect)) { $item.IsSelected = $true }
        $capabilityList.Items.Refresh()
        & $invalidatePreview
        $statusText.Text = Get-ResidueSweepText -Text 'Selection changed. Scan again to refresh the preview.'
    }.GetNewClosure())

    $clearSelectionButton.Add_Click({
        foreach ($item in @($capabilityList.ItemsSource | Where-Object CanSelect)) { $item.IsSelected = $false }
        $capabilityList.Items.Refresh()
        & $invalidatePreview
        $statusText.Text = Get-ResidueSweepText -Text 'Choose one or more cleanup areas to begin.'
    }.GetNewClosure())

    $capabilityClickHandler = {
        & $invalidatePreview
        $statusText.Text = Get-ResidueSweepText -Text 'Selection changed. Scan again to refresh the preview.'
    }.GetNewClosure()
    $capabilityList.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]$capabilityClickHandler
    )
    & $updateSelectionSummary

    $scanSelected = {
        $selectedIds = @(& $getSelectedIds)
        if ($selectedIds.Count -eq 0) {
            Show-MessageBox -Owner $Window -Title 'Nothing Selected' -Message 'Select at least one cleanup capability to scan.' -Button 'OK' -Icon 'Information' | Out-Null
            return
        }

        $scanButton.IsEnabled = $false
        $runButton.IsEnabled = $false
        $statusText.Text = Get-ResidueSweepText -Text 'Scanning selected cleanup targets. Nothing is being changed...'
        $previewList.ItemsSource = $null
        $previewEmptyPanel.Visibility = 'Visible'
        $previewEmptyText.Text = Get-ResidueSweepText -Text 'Scanning selected cleanup targets...'
        $resultCountText.Text = '--'
        $resultSizeText.Text = '--'
        Invoke-DoEvents

        try {
            $report = @(Get-ResidueSweepCleanupDiagnostics -CapabilityId $selectedIds -QuarantineRoot $QuarantineRoot -ExclusionsPath $exclusionsPath)
            $displayReport = @(& $convertPreviewGroups -Report $report -NameById $nameById)
            foreach ($group in $displayReport) {
                $group.Mode = Get-ResidueSweepText -Text $group.RawMode
                $group.CountText = Get-ResidueSweepText -Text '{0:N0} items' -Arguments @($group.FileCount)
            }
            $previewList.ItemsSource = $displayReport
            $sessionState.LastScanIds = @($selectedIds)
            $sessionState.ApprovedPaths = @($report | ForEach-Object { @($_.Items) } | ForEach-Object Path)
            & $startFadeIn -Element $previewList
            $totalFiles = [long](($report | Measure-Object FileCount -Sum).Sum)
            $totalBytes = [long](($report | Measure-Object SizeBytes -Sum).Sum)
            $resultCountText.Text = '{0:N0}' -f $totalFiles
            $resultSizeText.Text = & $formatSize -Bytes $totalBytes
            $previewEmptyPanel.Visibility = if ($displayReport.Count -gt 0) { 'Collapsed' } else { 'Visible' }
            if ($displayReport.Count -eq 0) {
                $previewEmptyText.Text = Get-ResidueSweepText -Text 'No matching files or records were found.'
            }
            $statusText.Text = Get-ResidueSweepText -Text 'Preview: {0:N0} files or records, {1:N2} MiB. No changes were made.' -Arguments @($totalFiles, ($totalBytes / 1MB))
            $runButton.IsEnabled = @($selectedIds | Where-Object { [string]$catalogById[$_].Execution -notin @('Detection only', 'Configuration', 'History') }).Count -gt 0
        }
        catch {
            $statusText.Text = Get-ResidueSweepText -Text 'Scan failed: {0}' -Arguments @($_.Exception.Message)
            $previewEmptyPanel.Visibility = 'Visible'
            $previewEmptyText.Text = Get-ResidueSweepText -Text 'The scan could not be completed.'
            Show-MessageBox -Owner $Window -Title 'Cleanup Scan Failed' -Message $statusText.Text -Button 'OK' -Icon 'Error' | Out-Null
        }
        finally { $scanButton.IsEnabled = $true }
    }.GetNewClosure()
    $scanButton.Add_Click($scanSelected)

    $runButton.Add_Click({
        $selectedIds = @(& $getSelectedIds)
        if (-not (& $testScanCurrent -State $sessionState -SelectedId $selectedIds)) {
            Show-MessageBox -Owner $Window -Title 'Scan Required' -Message 'The selection changed. Scan the selected capabilities again before running cleanup.' -Button 'OK' -Icon 'Information' | Out-Null
            return
        }

        $executableIds = @($selectedIds | Where-Object { [string]$catalogById[$_].Execution -notin @('Detection only', 'Configuration', 'History') })
        $irreversible = @($executableIds | Where-Object { [string]$catalogById[$_].Execution -eq 'Irreversible' })
        $recycleDrives = @($previewList.ItemsSource | Where-Object { $_.CapabilityId -eq 'RecycleBin' -and $_.IsSelected } | ForEach-Object Path)
        if ($executableIds -contains 'RecycleBin' -and $recycleDrives.Count -eq 0) {
            Show-MessageBox -Owner $Window -Title 'Recycle Bin Drive Required' -Message 'Select at least one Recycle Bin drive in the preview list before running cleanup.' -Button 'OK' -Icon 'Information' | Out-Null
            return
        }
        $warning = Get-ResidueSweepText -Text 'ResidueSweep will quarantine recoverable files and run the selected Windows-native actions. Close browsers first. Locked files are skipped.'
        if ($irreversible.Count -gt 0) { $warning += "`n`n" + (Get-ResidueSweepText -Text 'Warning: Recycle Bin cleanup is permanent and cannot be undone.') }
        $confirmation = Show-MessageBox -Owner $Window -Title 'Run Selected Cleanup?' -Message $warning -Button 'YesNo' -Icon 'Warning' -Width 620
        if ($confirmation -ne 'Yes') { return }

        $scanButton.IsEnabled = $false
        $runButton.IsEnabled = $false
        $statusText.Text = Get-ResidueSweepText -Text 'Running selected cleanup actions...'
        Invoke-DoEvents
        try {
            $results = @(Invoke-ResidueSweepCleanupExecution -CapabilityId $executableIds -QuarantineRoot $QuarantineRoot -ExclusionsPath $exclusionsPath -RecycleDrive $recycleDrives -ApprovedPath $sessionState.ApprovedPaths -Confirm:$false)
            $completed = @($results | Where-Object Status -in @('Moved', 'Completed'))
            $failed = @($results | Where-Object Status -eq 'Failed')
            $movedBytes = [long](($completed | Measure-Object SizeBytes -Sum).Sum)
            $statusText.Text = Get-ResidueSweepText -Text 'Completed {0:N0} items or actions ({1:N2} MiB); {2:N0} failed or remained locked.' -Arguments @($completed.Count, ($movedBytes / 1MB), $failed.Count)
            Show-MessageBox -Owner $Window -Title 'Cleanup Complete' -Message $statusText.Text -Button 'OK' -Icon $(if ($failed.Count -gt 0) { 'Warning' } else { 'Success' }) -Width 580 | Out-Null
            & $updateHistoryButtons | Out-Null
            & $scanSelected
        }
        catch {
            $statusText.Text = Get-ResidueSweepText -Text 'Cleanup failed: {0}' -Arguments @($_.Exception.Message)
            Show-MessageBox -Owner $Window -Title 'Cleanup Failed' -Message $statusText.Text -Button 'OK' -Icon 'Error' | Out-Null
        }
        finally { $scanButton.IsEnabled = $true }
    }.GetNewClosure())

    $restoreButton.Add_Click({
        $history = @(& $updateHistoryButtons)
        if ($history.Count -eq 0) { return }
        $latest = $history[0]
        $confirmation = Show-MessageBox -Owner $Window -Title 'Undo Latest Cleanup?' -Message (Get-ResidueSweepText -Text 'Restore {0:N0} quarantined files from {1}?' -Arguments @($latest.ItemCount, $latest.CreatedAt)) -Button 'YesNo' -Icon 'Question' -Width 540
        if ($confirmation -ne 'Yes') { return }
        try {
            $results = @(Restore-ResidueSweepQuarantineRun -RunPath $latest.RunPath -QuarantineRoot $QuarantineRoot -Confirm:$false)
            $restored = @($results | Where-Object Status -eq 'Restored').Count
            $conflicts = @($results | Where-Object Status -in @('Conflict', 'Failed', 'Rejected', 'Missing')).Count
            $statusText.Text = Get-ResidueSweepText -Text 'Restored {0:N0} files; {1:N0} conflicts or failures were left untouched.' -Arguments @($restored, $conflicts)
            & $updateHistoryButtons | Out-Null
        }
        catch { Show-MessageBox -Owner $Window -Title 'Undo Failed' -Message $_.Exception.Message -Button 'OK' -Icon 'Error' | Out-Null }
    }.GetNewClosure())

    $purgeButton.Add_Click({
        $history = @(& $updateHistoryButtons)
        if ($history.Count -eq 0) { return }
        $latest = $history[0]
        $confirmation = Show-MessageBox -Owner $Window -Title 'Permanently Delete Latest Quarantine?' -Message (Get-ResidueSweepText -Text 'This permanently deletes {0:N0} quarantined files ({1:N2} MiB). This cannot be undone.' -Arguments @($latest.ItemCount, $latest.SizeMiB)) -Button 'YesNo' -Icon 'Warning' -Width 580
        if ($confirmation -ne 'Yes') { return }
        try {
            Remove-ResidueSweepQuarantineRun -RunPath $latest.RunPath -QuarantineRoot $QuarantineRoot -Confirm:$false
            $statusText.Text = Get-ResidueSweepText -Text 'Latest quarantine was permanently deleted.'
            & $updateHistoryButtons | Out-Null
        }
        catch { Show-MessageBox -Owner $Window -Title 'Purge Failed' -Message $_.Exception.Message -Button 'OK' -Icon 'Error' | Out-Null }
    }.GetNewClosure())

    $exclusionsButton.Add_Click(({
        if (& $showKeepList -Owner $Window -Path $exclusionsPath -SchemaPath $keepListSchema) {
            & $invalidatePreview
            $statusText.Text = Get-ResidueSweepText -Text 'Keep list saved. Scan again to apply it.'
        }
    }.GetNewClosure()))
    $openQuarantineButton.Add_Click(({
        if (Test-Path -LiteralPath $QuarantineRoot -PathType Container) {
            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"{0}"' -f $QuarantineRoot)
        }
    }.GetNewClosure()))
}

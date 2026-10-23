# Visual adjustment editor. Loaded after the WPF controls and application handlers.
$script:VisualPositionIds = @('theme','center','top','bottom','left','right','top-left','top-right','bottom-left','bottom-right')
$script:VisualPresetIds = @('custom','clear','glass','reading')
foreach ($name in @('VisualExpander','VisualTarget','VisualEditor','VisualPresetLabel','VisualPreset','VisualOpacityLabel','VisualOpacity','VisualOpacityValue','VisualBlurLabel','VisualBlur','VisualBlurValue','VisualPositionLabel','VisualPosition','VisualApplySave','VisualApplySaved','VisualReset','VisualHint')) {
    Set-Variable -Scope Script -Name $name -Value $window.FindName($name)
}

function Get-SkinVisualLabels {
    if ($Cfg.lang -eq 'zh-CN') {
        return @{ title='外观微调'; preset='快捷预设'; opacity='面板不透明度'; blur='背景模糊'; position='壁纸位置'; applySave='应用并保存微调'; applySaved='应用已保存微调'; reset='恢复主题默认'; choose='请先选择主题'; saved='已保存微调'; none='尚未保存微调'; active='当前使用微调'; original='当前使用默认效果'; idle='尚未应用'; hint='普通“应用所选”始终使用主题默认效果；微调按应用和主题保存，点击按钮后生效。'; presets=@('自定义','清晰壁纸','柔和玻璃','阅读优先'); positions=@('跟随主题','居中','顶部','底部','左侧','右侧','左上','右上','左下','右下') }
    }
    if ($Cfg.lang -eq 'zh-TW') {
        return @{ title='外觀微調'; preset='快捷預設'; opacity='面板不透明度'; blur='背景模糊'; position='桌布位置'; applySave='套用並儲存微調'; applySaved='套用已儲存微調'; reset='還原主題預設'; choose='請先選擇主題'; saved='已儲存微調'; none='尚未儲存微調'; active='目前使用微調'; original='目前使用預設效果'; idle='尚未套用'; hint='一般「套用所選」一律使用主題預設效果；微調依應用與主題儲存，點擊按鈕後生效。'; presets=@('自訂','清晰桌布','柔和玻璃','閱讀優先'); positions=@('跟隨主題','置中','頂部','底部','左側','右側','左上','右上','左下','右下') }
    }
    return @{ title='Fine-tune appearance'; preset='Preset'; opacity='Panel opacity'; blur='Background blur'; position='Wallpaper position'; applySave='Apply and save'; applySaved='Apply saved'; reset='Theme default'; choose='Select a theme first'; saved='Saved adjustment'; none='No saved adjustment'; active='Adjustment active'; original='Theme default active'; idle='Not applied'; hint='Apply selected always uses the theme default. Adjustments are saved per app and theme, and take effect only when applied here.'; presets=@('Custom','Clear wallpaper','Soft glass','Reading first'); positions=@('Follow theme','Center','Top','Bottom','Left','Right','Top left','Top right','Bottom left','Bottom right') }
}

function Get-VisualThemeId {
    if ($themeList.SelectedItem) { return [string]$themeList.SelectedItem.Id }
    return ''
}

function Update-SkinVisualAvailability {
    if (-not $script:VisualEditor) { return }
    $id = Get-VisualThemeId
    $enabled = [bool]$id -and -not $State.Busy -and -not $State.QueuedAction
    $VisualEditor.IsEnabled = $enabled
    $VisualApplySave.IsEnabled = $enabled
    $VisualReset.IsEnabled = $enabled
    $VisualApplySaved.IsEnabled = $enabled -and [bool](ConvertTo-SkinVisual $Cfg.themeAdjustments[$id])
}

function Set-SkinVisualDraft($Value) {
    $visual = ConvertTo-SkinVisual $Value
    if (-not $visual) { $visual = Get-SkinVisualPreset clear }
    $VisualOpacity.Value = $visual.panelOpacity
    $VisualBlur.Value = $visual.blur
    $VisualPosition.SelectedIndex = [array]::IndexOf($script:VisualPositionIds, [string]$visual.position)
    $VisualOpacityValue.Text = [string]$visual.panelOpacity + '%'
    $VisualBlurValue.Text = [string]$visual.blur + ' px'
    $index = 0
    foreach ($presetId in @('clear','glass','reading')) {
        $preset = Get-SkinVisualPreset $presetId
        if ($preset.panelOpacity -eq $visual.panelOpacity -and $preset.blur -eq $visual.blur -and $preset.position -eq $visual.position) { $index = [array]::IndexOf($script:VisualPresetIds, $presetId) }
    }
    $VisualPreset.SelectedIndex = $index
}

function Sync-SkinVisualUi {
    if (-not $script:VisualEditor) { return }
    $script:UpdatingVisual = $true
    try {
        $labels = Get-SkinVisualLabels
        $VisualExpander.Header = $labels.title
        $VisualPresetLabel.Text = $labels.preset; $VisualOpacityLabel.Text = $labels.opacity
        $VisualBlurLabel.Text = $labels.blur; $VisualPositionLabel.Text = $labels.position
        $VisualApplySave.Content = $labels.applySave; $VisualApplySaved.Content = $labels.applySaved; $VisualReset.Content = $labels.reset
        $VisualHint.Text = $labels.hint
        $VisualPreset.Items.Clear(); foreach ($text in $labels.presets) { [void]$VisualPreset.Items.Add($text) }
        $VisualPosition.Items.Clear(); foreach ($text in $labels.positions) { [void]$VisualPosition.Items.Add($text) }
        $id = Get-VisualThemeId
        $saved = if ($id) { ConvertTo-SkinVisual $Cfg.themeAdjustments[$id] } else { $null }
        Set-SkinVisualDraft $saved
        if ($id) {
            $status = if ($saved) { $labels.saved } else { $labels.none }
            $current = if ($State.Current -ne $id) { $labels.idle } elseif (Get-SkinVisualAdjustment $Cfg $id) { $labels.active } else { $labels.original }
            $VisualTarget.Text = (Get-SkinApp $Settings.activeApp).Name + ' · ' + $themeList.SelectedItem.Name + ' · ' + $status + ' / ' + $current
        } else { $VisualTarget.Text = $labels.choose }
        Update-SkinVisualAvailability
    } finally { $script:UpdatingVisual = $false }
}

function Get-SkinVisualDraft {
    $index = $VisualPosition.SelectedIndex
    if ($index -lt 0) { $index = 0 }
    return ConvertTo-SkinVisual @{ panelOpacity = [int]$VisualOpacity.Value; blur = [int]$VisualBlur.Value; position = $script:VisualPositionIds[$index] }
}

function Invoke-SkinVisualAction([string]$Action) {
    $id = Get-VisualThemeId
    if (-not $id -or $State.Busy -or $State.QueuedAction) { return }
    $visual = $null
    if ($Action -eq 'save') {
        $visual = Get-SkinVisualDraft
        if (-not $visual) { return }
        $Cfg.themeAdjustments[$id] = @{} + $visual
        Save-Cfg
    } elseif ($Action -eq 'saved') {
        $visual = ConvertTo-SkinVisual $Cfg.themeAdjustments[$id]
        if (-not $visual) { return }
    }
    # Default applies keep saved adjustments; active values change only on success.
    Invoke-ApplyTheme $id $visual
    Update-SkinVisualAvailability
}

$themeList.Add_SelectionChanged({ if (-not $script:RefreshingThemes) { Sync-SkinVisualUi } })
$VisualPreset.Add_SelectionChanged({
    if ($script:UpdatingVisual -or $VisualPreset.SelectedIndex -le 0) { return }
    $script:UpdatingVisual = $true
    try { Set-SkinVisualDraft (Get-SkinVisualPreset $script:VisualPresetIds[$VisualPreset.SelectedIndex]) }
    finally { $script:UpdatingVisual = $false }
})
$VisualOpacity.Add_ValueChanged({
    $VisualOpacityValue.Text = [string][int]$VisualOpacity.Value + '%'
    if (-not $script:UpdatingVisual) { $script:UpdatingVisual = $true; try { $VisualPreset.SelectedIndex = 0 } finally { $script:UpdatingVisual = $false } }
})
$VisualBlur.Add_ValueChanged({
    $VisualBlurValue.Text = [string][int]$VisualBlur.Value + ' px'
    if (-not $script:UpdatingVisual) { $script:UpdatingVisual = $true; try { $VisualPreset.SelectedIndex = 0 } finally { $script:UpdatingVisual = $false } }
})
$VisualPosition.Add_SelectionChanged({
    if (-not $script:UpdatingVisual) { $script:UpdatingVisual = $true; try { $VisualPreset.SelectedIndex = 0 } finally { $script:UpdatingVisual = $false } }
})
$VisualApplySave.Add_Click({ Invoke-SkinVisualAction save })
$VisualApplySaved.Add_Click({ Invoke-SkinVisualAction saved })
$VisualReset.Add_Click({ Invoke-SkinVisualAction default })

function Test-SkinVisualEditor {
    $originalApply = (Get-Item Function:\Invoke-ApplyTheme).ScriptBlock
    $originalRecords = @{}
    foreach ($id in $script:SkinApps.Keys) {
        $originalRecords[$id] = @{ saved = $Settings.apps[$id].themeAdjustments; active = $Settings.apps[$id].activeVisual; theme = $Settings.apps[$id].currentTheme }
    }
    try {
        Set-Item Function:script:Invoke-ApplyTheme -Value { param([string]$themeId, $Visual = $null) $script:VisualApplyProbe = @{ theme = $themeId; visual = (ConvertTo-SkinVisual $Visual) } }
        foreach ($id in $script:SkinApps.Keys) { $Settings.apps[$id].themeAdjustments = @{} + $Settings.apps[$id].themeAdjustments }
        Select-SkinApplication opencode | Out-Null
        $themeList.SelectedItem = @($themeList.Items | Where-Object Id -eq 'aurora')[0]
        $VisualPreset.SelectedIndex = 2
        if ($VisualOpacity.Value -ne 64 -or $VisualBlur.Value -ne 6) { throw 'Visual preset did not populate controls' }
        $VisualOpacity.Value = 41; $VisualBlur.Value = 3; $VisualPosition.SelectedIndex = 9
        $click = [Windows.Controls.Primitives.ButtonBase]::ClickEvent
        $VisualApplySave.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if ($VisualApplyProbe.theme -ne 'aurora' -or $VisualApplyProbe.visual.panelOpacity -ne 41 -or $Cfg.themeAdjustments.aurora.position -ne 'bottom-right') { throw 'Apply/save did not capture draft for the selected theme' }
        $VisualOpacity.Value = 85
        $VisualApplySaved.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if ($VisualApplyProbe.visual.panelOpacity -ne 41) { throw 'Apply saved used an unsaved draft' }
        $VisualReset.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if ($null -ne $VisualApplyProbe.visual -or $Cfg.themeAdjustments.aurora.panelOpacity -ne 41) { throw 'Reset deleted saved adjustment or applied it implicitly' }
        $btnApply.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if ($null -ne $VisualApplyProbe.visual) { throw 'Normal apply used saved adjustments' }
        Select-SkinApplication codex | Out-Null
        $themeList.SelectedItem = @($themeList.Items | Where-Object Id -eq 'aurora')[0]
        $VisualPreset.SelectedIndex = 3
        $VisualApplySave.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if ($Cfg.themeAdjustments.aurora.panelOpacity -ne 88 -or $Settings.apps.opencode.themeAdjustments.aurora.panelOpacity -ne 41) { throw 'Visual UI preferences leaked across applications' }
        Select-SkinApplication opencode | Out-Null
        $themeList.SelectedItem = @($themeList.Items | Where-Object Id -eq 'aurora')[0]
        foreach ($lang in $script:LangCodes) {
            Set-Lang $lang
            if ($VisualOpacity.Value -ne 41 -or -not $VisualApplySaved.IsEnabled -or -not $VisualExpander.Header) { throw 'Visual UI lost saved values after application/language switch' }
        }
        # Exercise the real success/failure callback without starting an app.
        $State._pendingApply = 'aurora'; $State._pendingVisual = $Cfg.themeAdjustments.aurora; $State._pendingRestore = $false
        & $applyDone @(@{ok=$true;message='visual self-test'})
        if ($Cfg.activeVisual.panelOpacity -ne 41 -or $Cfg.activeVisual.themeId -ne 'aurora') { throw 'Successful apply did not activate the saved visual' }
        $Cfg.themeAdjustments.aurora = Get-SkinVisualPreset reading
        $State._pendingApply = 'aurora'; $State._pendingVisual = $Cfg.themeAdjustments.aurora
        & $applyDone @(@{ok=$false;message='expected offline failure'})
        if ($Cfg.activeVisual.panelOpacity -ne 41 -or $Cfg.themeAdjustments.aurora.panelOpacity -ne 88) { throw 'Failed apply replaced active values or deleted saved retry values' }
        $State._pendingApply = 'aurora'; $State._pendingVisual = $null
        & $applyDone @(@{ok=$true;message='default self-test'})
        if ($null -ne $Cfg.activeVisual -or $Cfg.themeAdjustments.aurora.panelOpacity -ne 88) { throw 'Successful default apply failed to retain saved values' }
    } finally {
        Set-Item Function:script:Invoke-ApplyTheme -Value $originalApply
        foreach ($id in $script:SkinApps.Keys) {
            $Settings.apps[$id].themeAdjustments = $originalRecords[$id].saved
            $Settings.apps[$id].activeVisual = $originalRecords[$id].active
            $Settings.apps[$id].currentTheme = $originalRecords[$id].theme
        }
        $State.Current = [string]$Cfg.currentTheme
        $State.Bootstrap = Get-CurrentBootstrap
        Refresh-ThemeList
    }
}

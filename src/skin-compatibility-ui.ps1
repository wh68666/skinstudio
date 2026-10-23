# Explicit human acceptance checklist; automatic snapshots cannot mark a scene passed.
$script:CompatibilityStore=Join-Path $AppDir 'compatibility.json'
function Get-SkinCompatibilityLabels {
    if ($Cfg.lang -like 'zh*') { return @{
        title='兼容性验收'; checking='正在检测版本'; unknown='版本待检测'; untested='尚未实机验收'; partial='部分页面已验收'; verified='当前版本已实机验收'; issues='已发现兼容问题'; updated='应用已更新，需重新验收'; adapter_changed='适配已变化，需重新验收'; evidence_error='验收记录无法读取'
        scenes=@('长对话与滚动','代码块与横向滚动','输入框与按钮','分栏与调整宽度','上下文面板','菜单与浮层','设置窗口'); mode=@('浅色','深色'); pending='待验收'; pass='通过'; fail='未通过'; inspect='检查当前页面'; preview='查看截图'; accept='人工确认通过'; reject='记录问题'; report='查看报告'; close='关闭'; note='验收备注（必填）：'; detected='已发现'; absent='当前页未发现'; screenshot='截图与检测数据仅保存在本机。自动检查不会标记人工验收通过。'; needConnection='请先连接目标应用，再打开对应工作页面。'; hint='先检查当前页面，再选中对应场景。目视检查文字、按钮、遮挡、滚动、焦点及浅深色一致性后记录结果。'; noVersion='未检测到应用版本，请等待状态刷新。'; noCapture='请先检查当前页面并取得截图。'; needSkin='请先应用当前版本的皮肤，再检查和验收。'; wrongMode='当前页面模式与所选行不一致，请切换目标应用的浅/深色后重新检查。'; success='结果已保存；应用或适配版本变化后需要重新验收。'; changed='应用文件已变化，请关闭验收窗口，等待检测新版本后重新验收。'
    } }
    return @{title='Compatibility acceptance';checking='Checking version';unknown='Version not checked';untested='Not tested on device';partial='Partially reviewed';verified='Current build reviewed';issues='Compatibility issues found';updated='App updated; review required';adapter_changed='Adapter changed; review required';evidence_error='Cannot read review evidence';scenes=@('Long conversation / scroll','Code / horizontal scroll','Composer / controls','Split panes / resize','Context panel','Menus / overlays','Settings window');mode=@('Light','Dark');pending='Not reviewed';pass='Passed';fail='Failed';inspect='Inspect current page';preview='View screenshot';accept='Confirm visual pass';reject='Record issue';report='View report';close='Close';note='Review note (required):';detected='Present';absent='Not found on current page';screenshot='Screenshots and observations stay on this device. Automatic inspection never marks a human review passed.';needConnection='Connect the app and open the work page first.';hint='Inspect the page, select a scenario, then visually review text, buttons, occlusion, scrolling, focus and appearance before recording.';noVersion='App build not detected yet. Wait for status refresh.';noCapture='Inspect a page and capture evidence first.';needSkin='Apply the current adapter skin before inspecting and accepting this page.';wrongMode='Page appearance differs from this row. Switch the target app appearance and inspect again.';success='Review saved. Changed app or adapter builds need a new review.';changed='App files changed. Close this window and wait for a new build check.'}
}
function Update-SkinCompatibilityUi {
    $labels=Get-SkinCompatibilityLabels
    $window.FindName('BtnCompatibility').Content=$labels.title
    foreach ($id in $script:SkinApps.Keys) {
        $health=$State.Health[$id]; $compat=if ($health) {$health.compatibility} else {$null}
        $compatKind=if ($compat) {$compat.state} else {'unknown'}
        $text=$labels[$compatKind]
        if ($compat -and $compat.identity) {$text=$compat.identity.version+' · '+$text+' ('+$compat.passed+'/'+$compat.total+')'}
        $card=$script:AppStatusCards[$id]; $card.compat.Text=$text; $card.compat.ToolTip=$text
        if($compat -and $compat.error){$card.compat.ToolTip=$text+"`n"+$compat.error}
        Set-SkinManagerBrush $card.compat Foreground $(if ($compatKind -eq 'verified') {'Success'} elseif ($compatKind -eq 'issues') {'Danger'} elseif ($compatKind -in @('updated','adapter_changed')) {'Warning'} else {'Muted'})
    }
}
function Show-SkinCompatibilityDialog([switch]$Test) {
    if ($State.Busy -or $State.QueuedAction) {return}
    $appId=[string]$Settings.activeApp; $health=$State.Health[$appId]; $identity=$health.identity
    $compatStore=$script:CompatibilityStore; $auditLib=$script:LibPath; $evidenceDir=Join-Path $AppDir 'logs\compatibility'
    $labels=Get-SkinCompatibilityLabels
    $dialog=New-Object Windows.Window; if($window.IsVisible){$dialog.Owner=$window}; $dialog.Title=(Get-SkinApp $appId).Name+' · '+$labels.title
    Initialize-SkinManagerWindow $dialog
    $dialog.Width=810; $dialog.Height=720; $dialog.MinWidth=700; $dialog.MinHeight=620; $dialog.WindowStartupLocation='CenterOwner'
    $panel=New-Object Windows.Controls.DockPanel; $panel.Margin='14'; Set-SkinManagerBrush $panel Background Window; $dialog.Content=$panel
    $header=New-Object Windows.Controls.TextBlock; $header.TextWrapping='Wrap'; $header.Margin='0,0,0,10'
    $header.Text=if ($identity) {$identity.version+' · '+$labels[$health.compatibility.state]+' ('+$health.compatibility.passed+'/14)'+"`n"+$labels.hint} else {$labels.noVersion}
    [Windows.Controls.DockPanel]::SetDock($header,'Top'); [void]$panel.Children.Add($header)
    $bottom=New-Object Windows.Controls.StackPanel; [Windows.Controls.DockPanel]::SetDock($bottom,'Bottom'); [void]$panel.Children.Add($bottom)
    $hint=New-Object Windows.Controls.TextBlock; $hint.Text=$labels.screenshot; $hint.TextWrapping='Wrap'; $hint.Margin='0,8,0,8'; [void]$bottom.Children.Add($hint)
    $noteLabel=New-Object Windows.Controls.TextBlock; $noteLabel.Text=$labels.note; [void]$bottom.Children.Add($noteLabel)
    $note=New-Object Windows.Controls.TextBox; $note.Height=44; $note.TextWrapping='Wrap'; $note.AcceptsReturn=$true; $note.Margin='0,4,0,8'; [void]$bottom.Children.Add($note)
    $actions=New-Object Windows.Controls.WrapPanel; [void]$bottom.Children.Add($actions)
    $buttons=@{}
    foreach ($key in @('inspect','preview','accept','reject','report','close')) { $button=New-Object Windows.Controls.Button; $button.Content=$labels[$key]; $button.Padding='9,5'; $button.Margin='0,0,7,5'; [void]$actions.Children.Add($button); $buttons[$key]=$button }
    $message=New-Object Windows.Controls.TextBlock; $message.TextWrapping='Wrap'; Set-SkinManagerBrush $message Foreground Muted; [void]$bottom.Children.Add($message)
    $grid=New-Object Windows.Controls.DataGrid; $grid.IsReadOnly=$true; $grid.AutoGenerateColumns=$false; $grid.CanUserAddRows=$false; $grid.SelectionMode='Single'; $grid.HeadersVisibility='Column'
    foreach ($col in @(@('Mode','Mode',65),@('Scene','Scene',170),@('Result','Review',110),@('Observation','Automatic observation',180),@('Note','Note',200))) {
        $column=New-Object Windows.Controls.DataGridTextColumn; $column.Header=$col[1]; $column.Binding=New-Object Windows.Data.Binding($col[0]); $column.Width=$col[2]; [void]$grid.Columns.Add($column)
    }
    if ($Cfg.lang -like 'zh*') { $i=0; foreach ($title in @('模式','固定检查项','人工验收','自动观察','备注')) {$grid.Columns[$i].Header=$title;$i++} }
    [void]$panel.Children.Add($grid)
    $rows=New-Object Collections.ObjectModel.ObservableCollection[object]
    foreach ($mode in @('light','dark')) { $i=0; foreach ($scene in $script:SkinCompatibilityScenes) {
        $record=@($health.compatibility.records | Where-Object {$_.mode -eq $mode -and $_.scene -eq $scene} | Select-Object -Last 1)
        [void]$rows.Add([pscustomobject]@{Mode=$labels.mode[[array]::IndexOf(@('light','dark'),$mode)];Scene=$labels.scenes[$i];Result=$(if ($record.Count) {$labels[[string]$record[0].result]}else{$labels.pending});Observation=$labels.absent;Note=$(if($record.Count){$record[0].note}else{''});ModeId=$mode;SceneId=$scene})
        $i++
    } }
    $grid.ItemsSource=$rows
    $compatDialogState=@{snapshot=$null;busy=$false;identity=$identity}
    $buttons.inspect.IsEnabled=[bool]$identity
    $buttons.preview.IsEnabled=$false
    $captureDone={
        param($out)
        $compatDialogState.busy=$false; if(-not $dialog.IsVisible -and -not $Test){return}; $buttons.inspect.IsEnabled=$true
        $result=$out | Select-Object -Last 1
        if(-not $result.ok){$compatDialogState.snapshot=$null; $buttons.preview.IsEnabled=$false; $message.Text=$labels.needConnection+"`n"+$result.error;return}
        $compatDialogState.snapshot=$result.snapshot
        $buttons.preview.IsEnabled=$true
        foreach($row in $rows){$found=@($result.snapshot.pages | Where-Object {$_.audit.mode -eq $row.ModeId -and $_.audit.scenes.($row.SceneId).present}); $row.Observation=if($found.Count){$labels.detected}else{$labels.absent}}
        $grid.Items.Refresh(); $message.Text=$labels.hint
    }.GetNewClosure()
    $inspect={
        if ($compatDialogState.busy) {return}; $compatDialogState.busy=$true; $buttons.inspect.IsEnabled=$false; $message.Text=$labels.checking
        $exe=$health.exe; if(-not $exe){$exe=$Settings.apps[$appId].appExe}
        try { Start-BackgroundJob {
            param($spec)
            try { . $spec.lib; $current=Get-SkinAppIdentity $spec.app $spec.exe $null; if($current.fingerprint -ne $spec.identity.fingerprint){throw 'APP_BUILD_CHANGED'}; $snapshot=Get-SkinWorkPageAudit $spec.app $spec.exe $spec.port $spec.dir; return @{ok=$true;snapshot=$snapshot} }
            catch {return @{ok=$false;error=$_.Exception.Message}}
        } @{lib=$auditLib;app=$appId;exe=$exe;port=$Settings.apps[$appId].port;identity=$identity;dir=$evidenceDir} $captureDone }
        catch { & $captureDone @(@{ok=$false;error=$_.Exception.Message}) }
    }.GetNewClosure()
    $buttons.inspect.Add_Click($inspect)
    $buttons.preview.Add_Click({
        if(-not $compatDialogState.snapshot){return}
        $page=$compatDialogState.snapshot.pages | Select-Object -First 1
        if($grid.SelectedItem){$row=$grid.SelectedItem;$match=$compatDialogState.snapshot.pages | Where-Object {$_.audit.mode -eq $row.ModeId -and $_.audit.scenes.($row.SceneId).present} | Select-Object -First 1;if($match){$page=$match}}
        if($page -and (Test-Path -LiteralPath $page.screenshot)){[void](Start-Process -FilePath $page.screenshot)}
    }.GetNewClosure())
    $recordAction={
        param($sender,$e)
        if($compatDialogState.busy -or -not $grid.SelectedItem){return}
        $row=$grid.SelectedItem
        if(-not $compatDialogState.snapshot){$message.Text=$labels.noCapture;return}
        $page=@($compatDialogState.snapshot.pages | Where-Object {$_.audit.mode -eq $row.ModeId -and $_.audit.scenes.($row.SceneId).present} | Select-Object -First 1)
        if(-not $page.Count){$message.Text=$labels.wrongMode+' '+$labels.absent;return}
        try{
            $result=if($sender -eq $buttons.accept){'pass'}else{'fail'}
            if($result -eq 'pass' -and (-not $page[0].audit.styleActive -or ([string]$page[0].audit.marker).IndexOf('#'+$identity.adapter+':',[StringComparison]::Ordinal) -lt 0)){$message.Text=$labels.needSkin;return}
            $theme=[string]$page[0].audit.marker
            $saved=Save-SkinCompatibilityReview $compatStore $identity $row.SceneId $row.ModeId $result $note.Text $page[0].screenshot $theme
            $row.Result=$labels[$result]; $row.Note=$saved.note; $grid.Items.Refresh(); $message.Text=$labels.success
            if($State.Health[$appId].identity.fingerprint -eq $identity.fingerprint){$State.Health[$appId].compatibility=Get-SkinCompatibilityStatus $identity $compatStore}
            Update-SkinCompatibilityUi
        }catch{$message.Text=$_.Exception.Message}
    }.GetNewClosure()
    $buttons.accept.Add_Click($recordAction); $buttons.reject.Add_Click($recordAction)
    $buttons.report.Add_Click({if(Test-Path -LiteralPath $script:CompatibilityStore){[void](Start-Process notepad.exe -ArgumentList ('"'+$script:CompatibilityStore+'"'))}})
    $buttons.close.Add_Click({$dialog.Close()}.GetNewClosure())
    if($Test){return @{dialog=$dialog;grid=$grid;buttons=$buttons;message=$message;note=$note;box=$compatDialogState}}
    [void]$dialog.ShowDialog()
}
$window.FindName('BtnCompatibility').Add_Click({Show-SkinCompatibilityDialog})
function Test-SkinCompatibilityUi {
    $oldHealth=$State.Health; $oldLang=$Cfg.lang
    $originalJob=(Get-Item Function:\Start-BackgroundJob).ScriptBlock
    $oldStore=$script:CompatibilityStore
    $script:CompatibilityStore=Join-Path $AppDir 'logs\compatibility-selftest.json'
    $shot=Join-Path $AppDir 'logs\compatibility-selftest.png'
    try {
        [IO.File]::WriteAllBytes($shot,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6WQAAAABJRU5ErkJggg=='))
        $State.Health=@{}
        $State.Health[$Settings.activeApp]=@{identity=@{application=$Settings.activeApp;version='QA build';fingerprint=('a'*64);adapter=(Get-SkinAdapterRevision $Settings.activeApp);suite=$script:SkinCompatibilitySuite};compatibility=@{state='untested';records=@()}}
        foreach($lang in $script:LangCodes){$Cfg.lang=$lang;Update-SkinCompatibilityUi;$ui=Show-SkinCompatibilityDialog -Test
            if($ui.grid.Items.Count -ne 14){throw 'Compatibility checklist must contain seven scenes in both modes'}
            $ui.grid.SelectedIndex=0
            $ui.buttons.accept.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            if(-not $ui.message.Text){throw 'Acceptance without page evidence was not rejected'}
            $ui.dialog.Close()
        }
        $Cfg.lang='zh-CN';$ui=Show-SkinCompatibilityDialog -Test
        $script:CompatUiProbeSnapshot=@{pages=@(@{audit=@{mode='light';scenes=@{'long-chat'=@{present=$true}};marker=('fixture@1#'+(Get-SkinAdapterRevision $Settings.activeApp)+':r1:a1');styleActive=$true};screenshot=$shot})}
        Set-Item Function:script:Start-BackgroundJob -Value {param($Work,$Argument,$Done) & $Done @(@{ok=$true;snapshot=$script:CompatUiProbeSnapshot})}
        $click=[Windows.Controls.Primitives.ButtonBase]::ClickEvent
        $ui.buttons.inspect.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if(-not $ui.box.snapshot -or -not $ui.buttons.preview.IsEnabled){throw 'Compatibility page inspection callback failed'}
        $ui.grid.SelectedIndex=0; $ui.note.Text='Synthetic UI fixture; not a device review'
        $ui.buttons.accept.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if(@(Read-SkinCompatibilityRecords $script:CompatibilityStore).Count -ne 1){throw 'Manual compatibility review was not saved'}
        $ui.grid.SelectedIndex=7; $ui.buttons.accept.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if(@(Read-SkinCompatibilityRecords $script:CompatibilityStore).Count -ne 1){throw 'Light snapshot incorrectly accepted as dark evidence'}
        $ui.grid.SelectedIndex=0; $ui.buttons.reject.RaiseEvent([Windows.RoutedEventArgs]::new($click))
        if((Read-SkinCompatibilityRecords $script:CompatibilityStore)[0].result -ne 'fail'){throw 'Compatibility issue record did not replace prior pass'}
        $ui.dialog.Content.Measure([Windows.Size]::new(780,660));$ui.dialog.Content.Arrange([Windows.Rect]::new(0,0,780,660));$ui.dialog.Content.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(780,660,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($ui.dialog.Content)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $AppDir 'logs\selftest-compatibility-ui.png'))
        try{$encoder.Save($stream)}finally{$stream.Dispose()};$ui.dialog.Close()
    }finally{
        Set-Item Function:script:Start-BackgroundJob -Value $originalJob
        foreach($file in @($script:CompatibilityStore,$shot)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}}
        $script:CompatibilityStore=$oldStore;$State.Health=$oldHealth;$Cfg.lang=$oldLang;Update-SkinCompatibilityUi
    }
}

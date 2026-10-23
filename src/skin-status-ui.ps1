# Operation progress and application cards; all process/network probes run off the dispatcher.
foreach ($name in @('AppCards','OperationPanel','OperationTarget','OperationSteps','OperationProgress','OperationDetail','OperationActions','BtnRetryOperation','BtnOperationLog')) { Set-Variable -Scope Script -Name $name -Value $window.FindName($name) }
$script:AppStatusCards=@{}
$State.Operations=@{}; $State.Health=@{}; $State.HealthBusy=$false
$script:LastHealthScan=[DateTime]::MinValue; $script:LastDiscovery=[DateTime]::MinValue
foreach ($id in $script:SkinApps.Keys) {
    $button=New-Object Windows.Controls.Button
    $button.Tag=$id; $button.Margin='0,0,5,0'; $button.Padding='9,5'; $button.HorizontalContentAlignment='Left'
    $button.Template=[Windows.Markup.XamlReader]::Parse('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource Manager.Accent}"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource Manager.Accent}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.65"/></Trigger></ControlTemplate.Triggers></ControlTemplate>')
    $stack=New-Object Windows.Controls.StackPanel
    $name=New-Object Windows.Controls.TextBlock; $name.Text=$script:SkinApps[$id].Name; $name.FontWeight='SemiBold'
    $stateLabel=New-Object Windows.Controls.TextBlock; $stateLabel.FontSize=11; $stateLabel.Margin='0,2,0,0'
    $compatLabel=New-Object Windows.Controls.TextBlock; $compatLabel.FontSize=10; Set-SkinManagerBrush $compatLabel Foreground Muted; $compatLabel.TextTrimming='CharacterEllipsis'
    [void]$stack.Children.Add($name); [void]$stack.Children.Add($stateLabel); [void]$stack.Children.Add($compatLabel); $button.Content=$stack
    $button.Add_Click({ param($sender,$e) [void](Select-SkinApplication ([string]$sender.Tag)) })
    [void]$AppCards.Children.Add($button)
    $script:AppStatusCards[$id]=@{button=$button;label=$stateLabel;compat=$compatLabel}
}
$script:OperationStepLabels=@()
foreach ($i in 0..3) { $step=New-Object Windows.Controls.TextBlock; $step.FontSize=11; [void]$OperationSteps.Children.Add($step); $script:OperationStepLabels += $step }

function Get-SkinStatusLabels {
    if ($Cfg.lang -eq 'zh-CN') { return @{
        steps=@('启动应用','等待连接','应用皮肤','验证效果'); restoreSteps=@('启动应用','等待启动','恢复外观','验证启动')
        checking='检测中…'; missing='未安装'; stopped='未运行'; connected='已连接'; restart='需要重启'; unknown='检测失败'
        retry='重试'; logs='查看日志'; queued='等待后台任务结束'; queuedDetail='正在结束当前的自动补注，随后开始换肤。'
        running='{0} · {1}（已用 {2} 秒）'; failed='{0}失败 · {1}'; apply='换肤'; restore='恢复外观'; done='已完成 · {0}'; success='已确认 {0} 个页面的主题、样式及壁纸生效。'; official='已使用官方方式重新启动，并确认应用进程正在运行。'
        restartTip='应用正在运行，但未建立换肤连接；应用皮肤时将重启，请先保存工作。'; missingTip='未检测到桌面应用。可安装后重试，或在“程序 / 端口”手动指定。'; stoppedTip='桌面应用已安装，应用皮肤时将启动。'; connectedTip='已识别应用进程、调试连接和兼容页面，可直接换肤。'; unknownTip='状态检测失败，查看详情后可重试。'
        debug_disabled='尚未启用调试连接'; port_busy_hint='调试端口被其他程序占用，请在“程序 / 端口”更换'; no_renderer='尚未发现兼容页面，应用可能正在启动或不支持当前连接方式'
        checkingDetail='正在检查桌面程序和连接，已连接时会跳过启动。'; starting='正在启动应用并启用换肤连接。'; restarting='正在重启应用以启用换肤连接。'; reused='已连接，跳过启动与重启。'; renderer='等待应用的兼容页面就绪（最长 40 秒）。'; injecting='正在将所选皮肤应用到页面。'; checking_style='正在检查主题标记、样式和壁纸解码。'
        APP_NOT_FOUND='未找到有效的桌面应用。请先安装，或在“程序 / 端口”选择正确的桌面程序。'
        APP_ACCESS_DENIED='无法访问 WorkBuddy 进程。请让 SkinStudio 和 WorkBuddy 以相同权限运行后重试。'; process_access_denied='WorkBuddy 进程不可访问，可能以管理员权限运行；请让两个应用使用相同权限。'
        PORT_BUSY='端口 {0} 被其他程序占用。请在“程序 / 端口”更换端口后重试。'
        THEME_INVALID='主题包无法读取或生成样式。请检查主题文件，或重新导入主题。'
        START_FAILED='应用启动或重启失败。请检查程序位置和系统错误详情，关闭应用后可重试。'
        CONNECTION_TIMEOUT='等待连接超时。未发现兼容页面；应用可能未接受调试参数、已退出或版本暂不兼容。请检查程序与端口后重试。'
        APPLY_FAILED='皮肤脚本未能执行成功。可重试；若仍失败，请查看日志中的页面执行错误。'
        VERIFY_FAILED='效果验证未通过，部分页面的主题、样式或壁纸未正确生效。请重试，或查看日志定位不兼容的页面。'
        SETTINGS_SAVE_FAILED='外观操作已完成，但配置未能保存。请检查软件目录的写入权限和磁盘空间后重试。'; UNEXPECTED='操作未完成。请查看下面的错误原因，修正后重试。'; reason='错误详情：'
    } }
    if ($Cfg.lang -eq 'zh-TW') { return @{
        steps=@('啟動應用','等待連線','套用主題','驗證效果'); restoreSteps=@('啟動應用','等待啟動','還原外觀','驗證啟動')
        checking='偵測中…'; missing='未安裝'; stopped='未執行'; connected='已連線'; restart='需要重啟'; unknown='偵測失敗'; retry='重試'; logs='查看記錄'; queued='等待背景工作結束'; queuedDetail='正在結束自動補注，隨後開始套用主題。'
        running='{0} · {1}（已用 {2} 秒）'; failed='{0}失敗 · {1}'; apply='套用主題'; restore='還原外觀'; done='已完成 · {0}'; success='已確認 {0} 個頁面的主題、樣式及桌布生效。'; official='已以官方方式重新啟動，並確認應用程式正在執行。'
        restartTip='應用正在執行但未連線；套用主題時會重啟，請先儲存工作。'; missingTip='未偵測到桌面應用，可安裝或在「程式 / 連接埠」手動指定。'; stoppedTip='已安裝，套用主題時會啟動。'; connectedTip='已識別程序、調試連線與相容頁面，可直接套用。'; unknownTip='狀態偵測失敗，可修正後重試。'
        debug_disabled='尚未啟用調試連線'; port_busy_hint='連接埠被其他程序佔用，請更換'; no_renderer='尚未發現相容頁面，應用可能正在啟動或版本不相容'
        checkingDetail='正在檢查程式與連線；已連線時會略過啟動。'; starting='正在啟動應用並啟用連線。'; restarting='正在重啟應用以啟用連線。'; reused='已連線，略過啟動與重啟。'; renderer='等待相容頁面就緒（最長 40 秒）。'; injecting='正在將主題套用到頁面。'; checking_style='正在檢查主題標記、樣式與桌布解碼。'
        APP_ACCESS_DENIED='無法存取 WorkBuddy 程序，請讓兩個應用以相同權限執行後重試。'; process_access_denied='WorkBuddy 程序不可存取，請讓兩個應用使用相同權限。'; APP_NOT_FOUND='未找到有效的桌面應用。請先安裝或指定正確的程式位置。'; PORT_BUSY='連接埠 {0} 被其他程序佔用，請更換後重試。'; THEME_INVALID='無法讀取主題或產生樣式，請檢查檔案或重新匯入。'; START_FAILED='啟動或重啟失敗。請檢查程式位置及系統錯誤。'; CONNECTION_TIMEOUT='等待連線逾時。未發現相容頁面；應用可能拒絕調試參數、已結束或版本不相容。'; APPLY_FAILED='主題腳本執行失敗，請重試或查看頁面執行記錄。'; VERIFY_FAILED='效果驗證失敗，部分頁面的主題、樣式或桌布未生效。請重試或查看記錄。'; SETTINGS_SAVE_FAILED='外觀操作已完成，但無法儲存設定。請檢查資料夾寫入權限和磁碟空間後重試。'; UNEXPECTED='操作未完成，請依錯誤詳情修正後重試。'; reason='錯誤詳情：'
    } }
    return @{
        steps=@('Launch app','Wait for connection','Apply skin','Verify result'); restoreSteps=@('Launch app','Wait for app','Restore appearance','Verify launch')
        checking='Checking…'; missing='Not installed'; stopped='Not running'; connected='Connected'; restart='Restart required'; unknown='Check failed'; retry='Retry'; logs='View log'; queued='Waiting for background task'; queuedDetail='Finishing automatic reinjection before starting this operation.'
        running='{0} · {1} ({2}s elapsed)'; failed='{0} failed · {1}'; apply='Apply skin'; restore='Restore'; done='Completed · {0}'; success='Verified theme, stylesheet and wallpaper on {0} page(s).'; official='Relaunched normally and confirmed the application process is running.'
        restartTip='Running without a skin connection. Applying a skin will restart the app; save your work first.'; missingTip='Desktop app not detected. Install it or select its executable in App / Port.'; stoppedTip='Installed. Applying a skin will launch the app.'; connectedTip='App process, debug connection and compatible page detected. Ready to apply.'; unknownTip='Could not check the app. Review the details and retry.'
        debug_disabled='Debug connection is disabled'; port_busy_hint='Debug port belongs to another process; change it in App / Port'; no_renderer='No compatible page found; app may be starting or incompatible'
        checkingDetail='Checking executable and connection. Connected apps skip launch.'; starting='Launching the app with a skin connection.'; restarting='Restarting the app to enable its skin connection.'; reused='Already connected; launch and restart skipped.'; renderer='Waiting for a compatible page (up to 40 seconds).'; injecting='Applying the selected skin to the page.'; checking_style='Checking theme marker, stylesheet and wallpaper decoding.'
        APP_ACCESS_DENIED='Cannot access the WorkBuddy process. Run SkinStudio and WorkBuddy at the same privilege level and retry.'; process_access_denied='WorkBuddy process is inaccessible, possibly elevated. Run both apps at the same privilege level.'; APP_NOT_FOUND='Valid desktop app not found. Install it or select the correct executable in App / Port.'; PORT_BUSY='Port {0} belongs to another process. Change it in App / Port and retry.'; THEME_INVALID='Cannot read the theme or build its stylesheet. Check the files or import it again.'; START_FAILED='Could not start or restart the app. Check its location and the system error below.'; CONNECTION_TIMEOUT='Connection timed out: no compatible page. The app may reject debugging arguments, have exited, or be incompatible.'; APPLY_FAILED='The skin script failed. Retry or inspect the page execution error in the log.'; VERIFY_FAILED='Verification failed: the theme, stylesheet or wallpaper did not take effect on every page. Retry or inspect the log.'; SETTINGS_SAVE_FAILED='Appearance changed, but settings could not be saved. Check folder write permissions and free disk space, then retry.'; UNEXPECTED='Operation did not complete. Review the error below, correct it and retry.'; reason='Error details: '
    }
}

function New-SkinUiOperation([string]$ThemeId, $Visual, [bool]$Restore) {
    return @{application=[string]$Settings.activeApp;themeId=$ThemeId;visual=(ConvertTo-SkinVisual $Visual);restore=$Restore;state='running';stage='launch';detail='checking';started=[DateTime]::UtcNow;port=$Cfg.port;queue=(New-Object 'Collections.Concurrent.ConcurrentQueue[object]');code='';raw='';targets=0}
}
function Initialize-SkinOperationUi($Spec) {
    $operation=New-SkinUiOperation $Spec.ThemeId $Spec.Options.visual ([bool]$Spec.Restore)
    $State.Operations[$Settings.activeApp]=$operation
    $Spec.Progress=$operation.queue
    Update-SkinStatusUi
}
function Start-SkinUiOperationJob($Spec) {
    Initialize-SkinOperationUi $Spec
    try { Start-BackgroundJob $applyWork $Spec $applyDone }
    catch { & $applyDone @(@{ok=$false;code='UNEXPECTED';stage='launch';message=$_.Exception.Message}) }
}
function Set-SkinQueuedStatus([string]$ThemeId, $Visual, [bool]$Restore) {
    $operation=New-SkinUiOperation $ThemeId $Visual $Restore
    $operation.state='queued'; $State.Operations[$Settings.activeApp]=$operation
    Update-SkinStatusUi
}
function Set-SkinPreparationFailure([string]$ThemeId, $Visual, [bool]$Restore, [string]$Message) {
    $State.Operations[$Settings.activeApp]=New-SkinUiOperation $ThemeId $Visual $Restore
    Complete-SkinOperationUi @{ok=$false;code='UNEXPECTED';stage='launch';message=$Message}
}
function Set-SkinMissingFailure([string]$ThemeId, $Visual, [bool]$Restore) {
    $State.Operations[$Settings.activeApp]=New-SkinUiOperation $ThemeId $Visual $Restore
    $State.Health[$Settings.activeApp]=@{state='missing';reason='not_found';port=$Cfg.port;exe=''}
    Complete-SkinOperationUi @{ok=$false;code='APP_NOT_FOUND';stage='launch';message='Desktop executable not selected or detected.'}
}
function Receive-SkinOperationProgress {
    $operation=$State.Operations[$Settings.activeApp]
    if (-not $operation -or $operation.state -ne 'running') { return }
    $event=$null
    while ($operation.queue.TryDequeue([ref]$event)) { $operation.stage=[string]$event.stage; $operation.detail=[string]$event.detail }
}
function Complete-SkinOperationUi($Result) {
    $operation=$State.Operations[$Settings.activeApp]
    if (-not $operation) { return }
    Receive-SkinOperationProgress
    if ($Result -and $Result.ok) {
        $operation.state='success'; $operation.stage='verify'; $operation.targets=[int]$Result.targets
    } else {
        $operation.state='failed'
        $operation.code=if ($Result -and $Result.code) { [string]$Result.code } else { 'UNEXPECTED' }
        $operation.raw=if ($Result -and $Result.message) { [string]$Result.message } else { 'Background worker did not return a result.' }
        if ($Result.stage) { $operation.stage=[string]$Result.stage }
        Write-AppLog ('UI OPERATION FAILED ['+$operation.application+'/'+$operation.stage+'/'+$operation.code+'] '+$operation.raw)
    }
    Update-SkinStatusUi
    if (-not $SelfTest) { Start-SkinHealthScan }
}
function Update-SkinStatusUi {
    if (-not $script:AppCards) { return }
    $labels=Get-SkinStatusLabels
    if (Get-Command Update-SkinCompatibilityUi -ErrorAction SilentlyContinue) { Update-SkinCompatibilityUi }
    foreach ($id in $script:SkinApps.Keys) {
        $card=$script:AppStatusCards[$id]; $health=$State.Health[$id]
        $key=if ($health) { [string]$health.state } else { 'checking' }
        $card.label.Text='● '+$labels[$key]
        Set-SkinManagerBrush $card.label Foreground $(switch ($key) { 'connected' {'Success'} 'restart' {'Warning'} 'unknown' {'Danger'} default {'Muted'} })
        Set-SkinManagerBrush $card.button Background $(if ($id -eq $Settings.activeApp) { 'AccentSoft' } else { 'Surface' })
        Set-SkinManagerBrush $card.button BorderBrush $(if ($id -eq $Settings.activeApp) { 'Accent' } else { 'Border' })
        $card.button.IsEnabled=-not $State.Busy -and -not $State.QueuedAction
        $tip=$labels[$key+'Tip']
        if ($health) {
            $reason=if ($labels.ContainsKey(([string]$health.reason).Replace('port_busy','port_busy_hint'))) { $labels[([string]$health.reason).Replace('port_busy','port_busy_hint')] } else { [string]$health.reason }
            if ($health.reason -notin @('ready','not_found','not_running')) { $tip += "`n"+$reason }
            $tip += "`nCDP "+$health.port
            if ($health.exe) { $tip += "`n"+$health.exe }
        }
        $card.button.ToolTip=$tip
    }
    $operation=$State.Operations[$Settings.activeApp]
    $OperationPanel.Visibility=if ($operation) { 'Visible' } else { 'Collapsed' }
    if (-not $operation) { return }
    $action=if ($operation.restore) { $labels.restore } else { $labels.apply }
    $OperationTarget.Text=(Get-SkinApp $operation.application).Name+' · '+$(if ($operation.restore) { $labels.restore } else { $operation.themeId })
    $steps=if ($operation.restore) { $labels.restoreSteps } else { $labels.steps }
    $index=[array]::IndexOf(@('launch','connect','apply','verify'),[string]$operation.stage)
    if ($index -lt 0) { $index=0 }
    $elapsed=[int]([DateTime]::UtcNow-$operation.started).TotalSeconds
    foreach ($i in 0..3) {
        $step=$script:OperationStepLabels[$i]; $step.Text=([string]($i+1)+'. '+$steps[$i])
        Set-SkinManagerBrush $step Foreground $(if ($i -eq $index -and $operation.state -eq 'failed') { 'Danger' } elseif ($i -le $index) { 'Accent' } else { 'Muted' })
        $step.FontWeight=if ($i -eq $index) { 'SemiBold' } else { 'Normal' }
    }
    $OperationProgress.Value=if ($operation.state -eq 'success') { 4 } else { $index }
    Set-SkinManagerBrush $OperationProgress Foreground $(if ($operation.state -eq 'failed') { 'Danger' } elseif ($operation.state -eq 'success') { 'Success' } else { 'Accent' })
    Set-SkinManagerBrush $OperationPanel Background $(if ($operation.state -eq 'failed') { 'DangerSoft' } elseif ($operation.state -eq 'success') { 'SuccessSoft' } else { 'AccentSoft' })
    $OperationActions.Visibility=if ($operation.state -eq 'failed') { 'Visible' } else { 'Collapsed' }
    $BtnRetryOperation.Content=$labels.retry; $BtnOperationLog.Content=$labels.logs
    $BtnRetryOperation.IsEnabled=-not $State.Busy -and -not $State.QueuedAction
    $OperationDetail.ToolTip=$null
    switch ($operation.state) {
        'queued' { $statusText.Text=$labels.queued; $OperationDetail.Text=$labels.queuedDetail }
        'failed' {
            $statusText.Text=$labels.failed -f $action,$steps[$index]
            $reason=if ($labels.ContainsKey($operation.code)) { $labels[$operation.code] -f $operation.port } else { $labels.UNEXPECTED }
            $OperationDetail.Text=$reason
            if ($operation.raw) {
                $raw=$operation.raw -replace '\s+',' '
                if ($raw.Length -gt 260) { $raw=$raw.Substring(0,260)+'…' }
                $OperationDetail.Text += "`n"+$labels.reason+$raw
                $OperationDetail.ToolTip=$operation.raw
            }
        }
        'success' {
            $statusText.Text=$labels.done -f $action
            $OperationDetail.Text=if ($operation.restore) { $labels.official } else { $labels.success -f $operation.targets }
        }
        default {
            $statusText.Text=$labels.running -f $action,$steps[$index],$elapsed
            $detail=if ($operation.detail -eq 'checking') { 'checkingDetail' } else { $operation.detail }
            $OperationDetail.Text=if ($detail -eq 'official') { $labels.official } elseif ($labels.ContainsKey($detail)) { $labels[$detail] } else { $steps[$index] }
        }
    }
}

function Start-SkinHealthScan([switch]$Discover) {
    if ($SelfTest -or $State.HealthBusy -or $State.Busy -or $State.QueuedAction) { return }
    $State.HealthBusy=$true; $script:LastHealthScan=[DateTime]::UtcNow
    if ($Discover) { $script:LastDiscovery=[DateTime]::UtcNow }
    $profiles=@()
    foreach ($id in $script:SkinApps.Keys) {
        $profile=$Settings.apps[$id]; $exe=$profile.appExe
        if (-not $exe -and $State.Health[$id]) { $exe=$State.Health[$id].exe }
        $profiles += @{id=$id;exe=$exe;configured=$profile.appExe;port=$profile.port;identity=$State.Health[$id].identity}
    }
    Start-BackgroundJob {
        param($spec)
        . $spec.lib
        $results=@{}
        foreach ($profile in $spec.profiles) {
            $health=Get-SkinApplicationState $profile.id $profile.exe $profile.port -Discover:$spec.discover
            try { $health.identity=Get-SkinAppIdentity $profile.id $health.exe $profile.identity; Update-SkinCompatibilityObservation (Join-Path (Split-Path $spec.store) 'compatibility-versions.json') $health.identity; $health.compatibility=Get-SkinCompatibilityStatus $health.identity $spec.store }
            catch { $health.compatibility=@{state='evidence_error';passed=0;total=14;error=$_.Exception.Message} }
            $health.configured=$profile.configured; $results[$profile.id]=$health
        }
        return $results
    } @{lib=$script:LibPath;profiles=$profiles;discover=[bool]$Discover;store=(Join-Path $AppDir 'compatibility.json')} {
        param($out)
        $State.HealthBusy=$false
        $results=$out | Select-Object -Last 1
        if ($results -is [hashtable] -and -not $State.Busy) {
            foreach ($id in $script:SkinApps.Keys) {
                $health=$results[$id]
                if ($health -and $Settings.apps[$id].port -eq $health.port -and $Settings.apps[$id].appExe -eq $health.configured) {
                    if (-not $State.Health[$id] -or $State.Health[$id].state -ne $health.state -or $State.Health[$id].reason -ne $health.reason) { Write-AppLog ('APP STATUS '+$id+': '+$health.state+' ('+$health.reason+')') }
                    if (-not $State.Health[$id] -or $State.Health[$id].compatibility.state -ne $health.compatibility.state -or $State.Health[$id].identity.fingerprint -ne $health.identity.fingerprint) { Write-AppLog ('COMPATIBILITY '+$id+': '+$health.compatibility.state+' '+$health.identity.version+' '+$health.compatibility.error) }
                    $State.Health[$id]=$health
                }
            }
        }
        Update-SkinStatusUi
    }
}

function Invoke-RetrySkinOperation {
    if ($State.Busy -or $State.QueuedAction) { return }
    $request=$State.Operations[$Settings.activeApp]
    if (-not $request -or $request.state -ne 'failed') { return }
    if ($request.restore) { Invoke-RestoreOfficial } else { Invoke-ApplyTheme $request.themeId (ConvertTo-SkinVisual $request.visual) }
}
$BtnRetryOperation.Add_Click({ Invoke-RetrySkinOperation })
$BtnOperationLog.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $LogPath)) { Write-AppLog 'Log opened from operation details.' }
        [void](Start-Process notepad.exe -ArgumentList ('"'+$LogPath+'"'))
    } catch { $OperationDetail.Text += "`n"+$_.Exception.Message }
})
$script:StatusTimer=New-Object Windows.Threading.DispatcherTimer
$script:StatusTimer.Interval=[TimeSpan]::FromMilliseconds(200)
$script:StatusTimer.Add_Tick({
    Receive-SkinOperationProgress
    $operation=$State.Operations[$Settings.activeApp]
    if ($operation -and $operation.state -in @('running','queued')) { Update-SkinStatusUi }
    if (-not $SelfTest -and ([DateTime]::UtcNow-$script:LastHealthScan).TotalSeconds -ge 10) { Start-SkinHealthScan -Discover:(([DateTime]::UtcNow-$script:LastDiscovery).TotalSeconds -ge 60) }
})
if (-not $SelfTest) { $script:StatusTimer.Start() }

function Test-SkinStatusUi {
    $originalApply=(Get-Item Function:\Invoke-ApplyTheme).ScriptBlock
    $originalRestore=(Get-Item Function:\Invoke-RestoreOfficial).ScriptBlock
    $oldHealth=$State.Health; $oldOperations=$State.Operations
    $originalSave=(Get-Item Function:\Save-Cfg).ScriptBlock
    $oldCurrent=$State.Current; $oldConfiguredTheme=$Cfg.currentTheme; $oldVisual=$Cfg.activeVisual
    try {
        $State.Health=@{}; $State.Operations=@{}
        $states=@('missing','stopped','connected','restart','unknown'); $i=0
        foreach ($id in $script:SkinApps.Keys) { $State.Health[$id]=@{state=$states[$i % $states.Count];reason='ready';port=$Settings.apps[$id].port}; $i++ }
        $spec=@{ThemeId='aurora';Options=@{visual=@{panelOpacity=43;blur=2;position='center'}};Restore=$false}
        Initialize-SkinOperationUi $spec
        if ($spec.Progress -isnot [Collections.Concurrent.ConcurrentQueue[object]]) { throw 'Operation progress queue missing' }
        $delivery=@{done=$false;seen=$false}
        Start-BackgroundJob {
            param($queue)
            $queue.Enqueue(@{stage='connect';detail='renderer'})
            Start-Sleep -Milliseconds 400
            return @{ok=$true}
        } $spec.Progress { param($out) $delivery.done=$true }.GetNewClosure()
        $frame=New-Object Windows.Threading.DispatcherFrame; $deadline=(Get-Date).AddSeconds(10)
        $timer=New-Object Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromMilliseconds(25)
        $timer.Add_Tick({
            Receive-SkinOperationProgress
            if ($State.Operations[$Settings.activeApp].stage -eq 'connect') { $delivery.seen=$true }
            if ($delivery.done -or (Get-Date) -ge $deadline) { $frame.Continue=$false }
        }.GetNewClosure())
        $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame); $timer.Stop()
        if (-not $delivery.done -or -not $delivery.seen) { throw 'Live runspace progress never reached the dispatcher' }
        foreach ($stage in @('launch','connect','apply','verify')) {
            $spec.Progress.Enqueue(@{stage=$stage;detail='checking_style'})
            Receive-SkinOperationProgress; Update-SkinStatusUi
            if ($State.Operations[$Settings.activeApp].stage -ne $stage) { throw 'Operation progress was not delivered' }
        }
        Complete-SkinOperationUi @{ok=$false;code='PORT_BUSY';stage='connect';message='fixture port conflict'}
        if ($OperationActions.Visibility -ne 'Visible' -or -not $BtnRetryOperation.IsEnabled -or $OperationDetail.Text -notmatch [string]$Cfg.port) { throw 'Actionable failure details missing' }
        # Unrelated gallery messages must not replace the operation error.
        Update-UiState 'gallery loaded'
        if ($statusText.Text -eq 'gallery loaded') { throw 'Operation failure was overwritten' }
        Set-Lang 'zh-CN'
        $window.Content.Measure([Windows.Size]::new(760,740)); $window.Content.Arrange([Windows.Rect]::new(0,0,760,740)); $window.Content.UpdateLayout()
        $preview=[Windows.Media.Imaging.RenderTargetBitmap]::new(760,740,96,96,[Windows.Media.PixelFormats]::Pbgra32); $preview.Render($window.Content)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($preview))
        $stream=[IO.File]::Create((Join-Path $AppDir 'logs\selftest-status-failure.png'))
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
        Set-Item Function:script:Invoke-ApplyTheme -Value { param($themeId,$Visual) $script:StatusRetryProbe=@{id=$themeId;visual=$Visual} }
        $themeList.SelectedIndex=-1
        $BtnRetryOperation.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($StatusRetryProbe.id -ne 'aurora' -or $StatusRetryProbe.visual.panelOpacity -ne 43) { throw 'Retry lost the original theme or visual values' }
        $State.Operations[$Settings.activeApp].restore=$true
        Set-Item Function:script:Invoke-RestoreOfficial -Value { $script:StatusRestoreProbe=$true }
        Invoke-RetrySkinOperation
        if (-not $StatusRestoreProbe) { throw 'Restore retry applied a theme' }
        $State.Operations[$Settings.activeApp].restore=$false
        foreach ($lang in $script:LangCodes) {
            Set-Lang $lang
            foreach ($card in $script:AppStatusCards.Values) { if ($card.label.Text.Length -lt 3) { throw 'Application health label is missing' } }
            if (-not $BtnRetryOperation.Content -or -not $BtnOperationLog.Content) { throw 'Failure action translation missing' }
        }
        Complete-SkinOperationUi @{ok=$true;targets=1}
        if ($OperationProgress.Value -ne 4 -or $OperationActions.Visibility -ne 'Collapsed') { throw 'Successful operation still shows retry' }
        Initialize-SkinOperationUi $spec
        Set-Item Function:script:Save-Cfg -Value { throw 'fixture settings permission denied' }
        $State._pendingApply='aurora'; $State._pendingVisual=$null; $State._pendingRestore=$false
        & $applyDone @(@{ok=$true;targets=1;message='fixture successful injection'})
        if ($State.Operations[$Settings.activeApp].state -ne 'failed' -or $State.Operations[$Settings.activeApp].code -ne 'SETTINGS_SAVE_FAILED') { throw 'Settings save failure left operation running' }
        $State.Busy=$true; Update-SkinStatusUi
        if (@($script:AppStatusCards.Values | Where-Object {$_.button.IsEnabled}).Count) { throw 'Application switch allowed during operation' }
    } finally {
        $State.Busy=$false; $State.Health=$oldHealth; $State.Operations=$oldOperations
        $State.Current=$oldCurrent; $Cfg.currentTheme=$oldConfiguredTheme; $Cfg.activeVisual=$oldVisual
        Set-Item Function:script:Save-Cfg -Value $originalSave
        Set-Item Function:script:Invoke-ApplyTheme -Value $originalApply
        Set-Item Function:script:Invoke-RestoreOfficial -Value $originalRestore
        Update-SkinStatusUi
    }
}

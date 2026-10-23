# SkinStudio's own palette. This never injects styles into managed applications.
$script:ManagerPalettes=[ordered]@{
    pearl=@{Window='#F4F6FA';Surface='#FFFFFF';Raised='#EAEFF6';Input='#FFFFFF';Text='#1D2B40';Muted='#52647B';Border='#CED7E4';Accent='#315FC4';OnAccent='#FFFFFF';AccentSoft='#DFE9FF';Hover='#ECF1FA';Success='#247045';SuccessSoft='#E5F4EA';Danger='#B12F46';DangerSoft='#FDEAF0';Warning='#865B0D';Mode='light'}
    midnight=@{Window='#111722';Surface='#192232';Raised='#212D40';Input='#202C3E';Text='#E5EDF9';Muted='#ADBDD3';Border='#3D506B';Accent='#A6C3FF';OnAccent='#152441';AccentSoft='#2B4265';Hover='#293B55';Success='#89DBAC';SuccessSoft='#203E32';Danger='#FFA7B5';DangerSoft='#492B38';Warning='#F0CE85';Mode='dark'}
    iris=@{Window='#F3F0FA';Surface='#FFFCFF';Raised='#ECE5F6';Input='#FFFCFF';Text='#352947';Muted='#6E5B82';Border='#D6CAE5';Accent='#7546A7';OnAccent='#FFFFFF';AccentSoft='#EBDDF9';Hover='#F0E8FA';Success='#316C4B';SuccessSoft='#E4F1E7';Danger='#A83350';DangerSoft='#FAE5EB';Warning='#805A14';Mode='light'}
    pine=@{Window='#101D1B';Surface='#182B27';Raised='#223832';Input='#20342F';Text='#E1F1E9';Muted='#A9C6B9';Border='#3E6054';Accent='#97DCB8';OnAccent='#123326';AccentSoft='#2B4B3E';Hover='#2A4239';Success='#9AE2B4';SuccessSoft='#244336';Danger='#FFB0BA';DangerSoft='#4A3038';Warning='#EDD197';Mode='dark'}
}
$script:ManagerThemeIds=@('system','pearl','midnight','iris','pine')
$script:ManagerResources=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $AppDir 'skin-manager-theme.xaml')))
$script:ManagerThemeUpdating=$false
$script:ManagerWindows=New-Object 'Collections.Generic.List[WeakReference]'
function Get-SkinManagerLabels {
    switch ($Cfg.lang) {
        'zh-CN' { return @{title='SkinStudio 界面';hint='选择管理器自己的皮肤';names=@('跟随系统','云白','暮夜','鸢尾','松林')} }
        'zh-TW' { return @{title='SkinStudio 介面';hint='選擇管理器自己的面板';names=@('跟隨系統','雲白','暮夜','鳶尾','松林')} }
        default { return @{title='SkinStudio appearance';hint='Choose a skin for this manager';names=@('Follow system','Cloud','Midnight','Iris','Pine')} }
    }
}
function Get-SkinManagerEffectiveTheme([string]$Id) {
    if ($Id -eq 'system') {
        $key=$null
        try { $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'); if($key -and $key.GetValue('AppsUseLightTheme',1) -eq 0){return 'midnight'} }
        catch {} finally {if($key){$key.Dispose()}}
        return 'pearl'
    }
    if ($script:ManagerPalettes.Contains($Id)) { return $Id }
    return 'pearl'
}
function Set-SkinManagerBrush($Element,[string]$Property,[string]$Role) {
    $field=$Element.GetType().GetField(($Property+'Property'),[Reflection.BindingFlags]'Public,Static,FlattenHierarchy')
    if(-not $field){throw ('Missing WPF brush property: '+$Property)}
    $Element.SetResourceReference($field.GetValue($null),('Manager.'+$Role))
}
function Set-SkinManagerTitleBar($Target) {
    if (-not ('SkinStudioWindowTheme' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SkinStudioWindowTheme {
 [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd,int attribute,ref int value,int size);
}
'@
    }
    try { $handle=([Windows.Interop.WindowInteropHelper]::new($Target)).Handle; if($handle -ne [IntPtr]::Zero){$dark=[int]($script:ManagerPalettes[$script:ManagerEffectiveTheme].Mode -eq 'dark');[void][SkinStudioWindowTheme]::DwmSetWindowAttribute($handle,20,[ref]$dark,4)} } catch {}
}
function Initialize-SkinManagerWindow($Target) {
    if(-not $Target.Resources.MergedDictionaries.Contains($script:ManagerResources)){$Target.Resources.MergedDictionaries.Add($script:ManagerResources)}
    Set-SkinManagerBrush $Target Background Window
    Set-SkinManagerBrush $Target Foreground Text
    $script:ManagerWindows.Add([WeakReference]::new($Target))
    $Target.Add_SourceInitialized({param($sender,$event) Set-SkinManagerTitleBar $sender})
    Set-SkinManagerTitleBar $Target
}
function Set-SkinManagerTheme([string]$Id) {
    $effective=Get-SkinManagerEffectiveTheme $Id
    $palette=$script:ManagerPalettes[$effective]
    foreach($role in $palette.Keys){if($role -ne 'Mode'){$brush=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($palette[$role]));$brush.Freeze();$script:ManagerResources['Manager.'+$role]=$brush}}
    # Stock WPF surfaces (slider, selection and focus) also use the current palette.
    foreach($entry in @(@('Window','Window'),@('WindowText','Text'),@('Control','Raised'),@('ControlText','Text'),@('GrayText','Muted'),@('Highlight','AccentSoft'),@('HighlightText','Text'),@('InactiveSelectionHighlight','Hover'),@('InactiveSelectionHighlightText','Text'))) {
        $key=[Windows.SystemColors].GetProperty(($entry[0]+'BrushKey')).GetValue($null,$null)
        $script:ManagerResources[$key]=$script:ManagerResources['Manager.'+$entry[1]]
    }
    $script:ManagerEffectiveTheme=$effective
    foreach($reference in @($script:ManagerWindows.ToArray())) {if($reference.IsAlive){Set-SkinManagerTitleBar $reference.Target}else{[void]$script:ManagerWindows.Remove($reference)}}
}
function Sync-SkinManagerThemeUi {
    $script:ManagerThemeUpdating=$true
    try {
        $labels=Get-SkinManagerLabels
        $ManagerThemeLabel.Text=$labels.title; $ManagerThemeBox.ToolTip=$labels.hint
        $ManagerThemeBox.Items.Clear()
        for($i=0;$i -lt $script:ManagerThemeIds.Count;$i++) {
            $id=$script:ManagerThemeIds[$i];$item=New-Object Windows.Controls.ComboBoxItem;$item.Tag=$id
            $row=New-Object Windows.Controls.StackPanel;$row.Orientation='Horizontal'
            $swatch=New-Object Windows.Shapes.Ellipse;$swatch.Width=10;$swatch.Height=10;$swatch.Margin='0,0,8,0';$swatch.VerticalAlignment='Center'
            $swatch.Fill=[Windows.Media.BrushConverter]::new().ConvertFromString($script:ManagerPalettes[(Get-SkinManagerEffectiveTheme $id)].Accent)
            [void]$row.Children.Add($swatch)
            $name=New-Object Windows.Controls.TextBlock;$name.Text=$labels.names[$i];[void]$row.Children.Add($name)
            $item.Content=$row;[void]$ManagerThemeBox.Items.Add($item)
        }
        $ManagerThemeBox.SelectedIndex=[array]::IndexOf($script:ManagerThemeIds,$Settings.managerTheme)
    } finally {$script:ManagerThemeUpdating=$false}
}
Set-SkinManagerTheme $Settings.managerTheme
Initialize-SkinManagerWindow $window
$script:ManagerThemeBox=$window.FindName('ManagerThemeBox');$script:ManagerThemeLabel=$window.FindName('ManagerThemeLabel')
$ManagerThemeBox.Add_SelectionChanged({
    if($script:ManagerThemeUpdating -or -not $ManagerThemeBox.SelectedItem){return}
    $old=$Settings.managerTheme; $Settings.managerTheme=[string]$ManagerThemeBox.SelectedItem.Tag
    try {Save-Cfg;Set-SkinManagerTheme $Settings.managerTheme;Write-AppLog ('MANAGER THEME '+$Settings.managerTheme)}
    catch {$Settings.managerTheme=$old;Set-SkinManagerTheme $old;Sync-SkinManagerThemeUi;$statusText.Text=$_.Exception.Message;Write-AppLog ('Manager theme save failed: '+$_.Exception.Message)}
})
$script:ManagerThemeTimer=New-Object Windows.Threading.DispatcherTimer
$ManagerThemeTimer.Interval=[TimeSpan]::FromSeconds(3)
$ManagerThemeTimer.Add_Tick({if($Settings.managerTheme -eq 'system' -and (Get-SkinManagerEffectiveTheme 'system') -ne $script:ManagerEffectiveTheme){Set-SkinManagerTheme 'system'}})
if(-not $SelfTest){$ManagerThemeTimer.Start()}
$window.Add_Closed({$script:ManagerThemeTimer.Stop()})

function Test-SkinManagerThemeUi {
    $savedTheme=$Settings.managerTheme; $savedLang=$Cfg.lang
    $profilesBefore=$Settings.apps|ConvertTo-Json -Depth 12 -Compress
    function Get-TestLuminance([Windows.Media.Color]$Color) {
        $channels=@($Color.R,$Color.G,$Color.B)|ForEach-Object {$v=$_/255.0;if($v -le 0.04045){$v/12.92}else{[Math]::Pow(($v+0.055)/1.055,2.4)}}
        return 0.2126*$channels[0]+0.7152*$channels[1]+0.0722*$channels[2]
    }
    function Get-TestContrast($A,$B) {
        $aLum=Get-TestLuminance $A; $bLum=Get-TestLuminance $B
        return ([Math]::Max($aLum,$bLum)+0.05)/([Math]::Min($aLum,$bLum)+0.05)
    }
    function Save-ManagerTestImage($Visual,[string]$Name,[int]$Width=760,[int]$Height=710) {
        $Visual.Measure([Windows.Size]::new($Width,$Height));$Visual.Arrange([Windows.Rect]::new(0,0,$Width,$Height));$Visual.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($Width,$Height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($Visual)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $AppDir ('logs\'+$Name+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
    try {
        foreach($language in $script:LangCodes){$Cfg.lang=$language;Sync-SkinManagerThemeUi;if($ManagerThemeBox.Items.Count -ne 5){throw 'Manager appearance choices missing'}}
        $Cfg.lang='zh-CN';Sync-SkinManagerThemeUi
        $VisualExpander.IsExpanded=$true
        foreach($id in $script:ManagerPalettes.Keys) {
            $ManagerThemeBox.SelectedIndex=[array]::IndexOf($script:ManagerThemeIds,$id)
            if($Settings.managerTheme -ne $id -or $script:ManagerEffectiveTheme -ne $id){throw 'Manager theme selection did not apply'}
            $window.Content.Measure([Windows.Size]::new(760,850));$window.Content.Arrange([Windows.Rect]::new(0,0,760,850));$window.Content.UpdateLayout()
            $expected=$script:ManagerResources['Manager.Window'].Color
            if($window.Content.Background.Color -ne $expected -or $window.Background.Color -ne $expected){throw 'Window palette did not update live'}
            if($ThemeSearch.Foreground.Color -ne $script:ManagerResources['Manager.Text'].Color -or $ThemeSearch.Background.Color -ne $script:ManagerResources['Manager.Input'].Color){throw 'Search control did not adopt manager palette'}
            foreach($pair in @(@('Text','Surface'),@('Muted','Surface'),@('Muted','Raised'),@('Text','AccentSoft'),@('OnAccent','Accent'),@('Success','Surface'),@('Danger','Surface'),@('Warning','Surface'))) {
                if((Get-TestContrast $script:ManagerResources['Manager.'+$pair[0]].Color $script:ManagerResources['Manager.'+$pair[1]].Color) -lt 4.5){throw ('Unreadable manager palette '+$id+' '+($pair -join '/'))}
            }
            Save-ManagerTestImage $window.Content ('selftest-manager-'+$id) 760 850
            $popup=$ManagerThemeBox.Template.FindName('PART_Popup',$ManagerThemeBox)
            if(-not $popup -or $popup.Child.Background.Color -ne $script:ManagerResources['Manager.Input'].Color){throw 'Theme dropdown retained a native light background'}
            Save-ManagerTestImage $popup.Child ('selftest-manager-dropdown-'+$id) 190 185
            $ui=Show-SkinCompatibilityDialog -Test
            if($ui.dialog.Background.Color -ne $expected){throw 'Compatibility dialog did not adopt manager palette'}
            Save-ManagerTestImage $ui.dialog.Content ('selftest-manager-dialog-'+$id) 780 660
            $ui.dialog.Close()
        }
        # Reapply without recreating a dialog: already-open secondary windows must follow.
        $ui=Show-SkinCompatibilityDialog -Test;Set-SkinManagerTheme 'midnight'
        if($ui.dialog.Background.Color -ne $script:ManagerResources['Manager.Window'].Color){throw 'Open dialog retained old palette'}
        $ui.dialog.Close()
        $ManagerThemeBox.SelectedIndex=0
        if($Settings.managerTheme -ne 'system' -or $script:ManagerEffectiveTheme -ne (Get-SkinManagerEffectiveTheme 'system')){throw 'System appearance did not resolve'}
        $originalSave=(Get-Item Function:\Save-Cfg).ScriptBlock
        try {
            Set-Item Function:script:Save-Cfg -Value {throw 'Fixture: preference write denied'}
            $ManagerThemeBox.SelectedIndex=2
            if($Settings.managerTheme -ne 'system' -or $ManagerThemeBox.SelectedIndex -ne 0){throw 'Theme write failure lost previous selection'}
        } finally {Set-Item Function:script:Save-Cfg -Value $originalSave}
        $Cfg.lang=$savedLang
        if(($Settings.apps|ConvertTo-Json -Depth 12 -Compress) -ne $profilesBefore){throw 'Manager theme altered managed application settings'}
    } finally {
        $VisualExpander.IsExpanded=$false;$Settings.managerTheme=$savedTheme;$Cfg.lang=$savedLang
        Set-SkinManagerTheme $savedTheme;Sync-SkinManagerThemeUi
    }
}

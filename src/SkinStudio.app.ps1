# SkinStudio.app.ps1 - tray UI app for ZCode skinning (PS 5.1)
# Features: installed theme list + zip import + dreamskin.cc gallery + tray switcher
# Run dev: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1
# Build: scripts/build.ps1 (single-file EXE in build/)
param(
    [switch]$SelfTest,
    [string]$DataDirectory,
    [string]$LegacyDirectory
)
# self-unblock: double-clicked exes have no Bypass env; loading companion .ps1
# files is blocked under the default Restricted policy - fix at process scope
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch {
    # A group policy may prohibit scripts; do not change persistent user policy.
}
$ErrorActionPreference = 'Stop'

# ---- resources are immutable; data survives moving/upgrading the executable ----
$script:ResourceDir = $PSScriptRoot
if (-not $ResourceDir) { throw 'Program resource directory unavailable' }
. (Join-Path $ResourceDir 'skin-storage.ps1')
if(-not $DataDirectory){$DataDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SkinStudio\data'}
$builtinRoot=$ResourceDir
if(-not (Test-Path -LiteralPath (Join-Path $builtinRoot 'themes\aurora'))){$builtinRoot=Join-Path (Split-Path $ResourceDir) 'resources'}
$script:AppDir=Initialize-SkinDataDirectory $DataDirectory $builtinRoot $LegacyDirectory -SelfTest:$SelfTest

$libPath = Join-Path $ResourceDir 'skin-lib.ps1'
if (-not (Test-Path $libPath)) { $libPath = Join-Path (Split-Path -Parent $AppDir) 'skin-lib.ps1' }
if (-not (Test-Path $libPath)) { throw 'skin-lib.ps1 not found next to the app' }
. $libPath
$script:LibPath = $libPath

# app version + update check endpoint (GitHub Release, public repo required)
$script:AppVersion = '2.8.6'
$script:UpdateApiUrl = 'https://api.github.com/repos/wh68666/skinstudio/releases/latest'
$script:NotifiedTag = ''

$script:ThemesDir = Join-Path $AppDir 'themes'
$script:ImportsDir = Join-Path $AppDir 'imports'
$script:LogPath = Join-Path $AppDir 'logs\app.log'
[void](New-Item $script:ThemesDir -ItemType Directory -Force | Out-Null)
[void](New-Item (Join-Path $AppDir 'logs') -ItemType Directory -Force | Out-Null)

# ---- single instance ----
Add-Type -AssemblyName System.Windows.Forms
$script:Mutex = New-Object Threading.Mutex($false, 'Local\SkinStudioTray')
if (-not $script:Mutex.WaitOne(0)) {
    if($SelfTest){throw 'Close the running SkinStudio instance before SelfTest.'}
    [System.Windows.Forms.MessageBox]::Show('SkinStudio is already running.', 'SkinStudio') | Out-Null
    exit 0
}

# ---- config ----
$script:CfgPath = Join-Path $AppDir 'config.json'
$script:Settings = Read-SkinSettings $CfgPath
$script:Cfg = $Settings.apps[$Settings.activeApp]
$Cfg.lang = $Settings.lang
$script:WatchCache = @{}
function Save-Cfg {
    if ($SelfTest) { return }
    $Settings.lang = $Cfg.lang
    Write-SkinSettings $CfgPath $Settings
}

function Write-AppLog([string]$msg) {
    # NoHost: this app runs as ps2exe -noConsole where Write-Host becomes a popup MessageBox
    try { Write-ZcLog -Path $LogPath -Message $msg -NoHost } catch { }
}

# ---- state ----
$script:State = @{
    Themes    = @()          # installed theme infos
    Current   = [string]$Cfg.currentTheme
    Busy      = $false
    GalleryBusy = $false
    WatchBusy = $false
    QueuedAction = $null
    Bootstrap = $null       # cached bootstrap js for current theme
    Marker    = ''          # window.__ZC_SKIN value expected for the current theme
    Watch     = $null       # seen target urls
    Gallery   = @()
    GalleryOffset = 0
    GalleryTotal = 0
}

function Get-InstalledThemes {
    $list = @()
    Get-ChildItem $ThemesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $pack = Get-ThemePack -ThemeDir $_.FullName
            $list += @{
                Id = [string]$pack.Meta.id; Name = [string]$pack.Meta.name; Version = [string]$pack.Version
                Imported = [bool]($pack.Meta.PSObject.Properties['imported'])
                Dir = $_.FullName; BgPath = $pack.BgPath; Appearance = [string]$pack.Meta.appearance
            }
        } catch { }
    }
    return $list
}

function Get-CurrentBootstrap {
    if (-not $State.Current) { return $null }
    $dir = Join-Path $ThemesDir $State.Current
    if (-not (Test-Path $dir)) { return $null }
    try {
        $pack = Get-ThemePack -ThemeDir $dir
        $State.Marker = Get-SkinMarker $pack $Cfg $Settings.activeApp
        return (New-SkinBootstrapJs -Application $Settings.activeApp -ThemePack $pack -Options $Cfg)
    } catch { Write-AppLog ("bootstrap build failed: " + $_.Exception.Message); return $null }
}

# ---- background work helper (runspace -> dispatcher callback) ----
function Start-BackgroundJob([scriptblock]$Work, [object]$Argument, [scriptblock]$Done) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Work.ToString()).AddArgument($Argument)
    $iar = $ps.BeginInvoke()
    # poll via WPF dispatcher timer to keep UI responsive
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $box = @{ PS = $ps; IAR = $iar; Done = $Done; Timer = $timer }
    $timer.Add_Tick({
        try {
            if ($box.IAR.IsCompleted) {
                $box.Timer.Stop()
                $out = $null
                try { $out = $box.PS.EndInvoke($box.IAR) } catch { $out = @('ERR: ' + $_.Exception.Message) }
                $rs = $box.PS.Runspace; $box.PS.Dispose(); $rs.Dispose()
                try { & $box.Done $out } catch { Write-AppLog ('ui-callback error: ' + $_.Exception.Message) }
            }
        } catch { Write-AppLog ('poll error: ' + $_.Exception.Message); try { $box.Timer.Stop() } catch { } }
    }.GetNewClosure())
    $timer.Start()
}

# ---- apply / restore (work runs in background job) ----
$applyWork = {
    param($spec)
    $ErrorActionPreference = 'Stop'
    try {
        . $spec.Lib
        return Invoke-SkinOperation -Application $spec.Application -AppExe $spec.AppExe -Port $spec.Port -ThemeDir $spec.ThemeDir -LogPath $spec.LogPath -Restore:$spec.Restore -Options $spec.Options -Progress { param($event) $spec.Progress.Enqueue($event) }
    } catch { return @{ ok = $false; message = $_.Exception.Message; code = [string]$_.Exception.Data['SkinCode']; stage = [string]$_.Exception.Data['SkinStage'] } }
}

$applyDone = {
    param($out)
    $State.Busy = $false
    $appBox.IsEnabled = $true; $btnSettings.IsEnabled = $true
    $r = $null
    try { $r = $out | Select-Object -Last 1 } catch { }
    if ($r -is [string]) { $r=@{ok=$false;code='UNEXPECTED';message=[string]$r} }
    if ($r -and $r.ok) {
        if ($State._pendingRestore) { $State.Current = ''; $script:Cfg.currentTheme = ''; $Cfg.activeVisual = $null; $State.Marker = '' }
        else {
            $State.Current = $State._pendingApply; $script:Cfg.currentTheme = $State._pendingApply
            $Cfg.activeVisual = ConvertTo-SkinVisual $State._pendingVisual
            if ($Cfg.activeVisual) { $Cfg.activeVisual.themeId = $State.Current }
        }
        $State.Bootstrap = Get-CurrentBootstrap
        try { Save-Cfg; Update-UiState (($L.ok) -f $r.message) }
        catch { $r=@{ok=$false;code='SETTINGS_SAVE_FAILED';stage='verify';message=$_.Exception.Message} }
    } else {
        $raw = if ($r) { [string]$r.message } else { 'unknown' }
        if ($raw -eq 'CDP_FAIL') { $raw = $L.cdpFail } elseif ($raw -eq 'PUSH_FAIL') { $raw = $L.pushFail }
        Update-UiState (($L.fail) -f $raw)
    }
    $State._pendingApply = ''; $State._pendingRestore = $false
    $State._pendingVisual = $null
    Complete-SkinOperationUi $r
    Refresh-ThemeList
}

# resolve ZCode exe for apply/restore: config -> running process -> scan;
# last resort: file picker once, remembered in config. $null when still unknown.
# Auto-detected paths are persisted too, so later runs keep working even when
# ZCode is not running at that moment.
function Resolve-ZcodeExeUi {
    $app = Get-SkinApp $Settings.activeApp
    # Discovery runs in the health worker; never scan installation trees on the dispatcher.
    $found = $null
    if (Test-SkinDesktopExe $Settings.activeApp $Cfg.appExe) { $found=$Cfg.appExe }
    elseif ($State.Health[$Settings.activeApp] -and (Test-SkinDesktopExe $Settings.activeApp $State.Health[$Settings.activeApp].exe)) { $found=$State.Health[$Settings.activeApp].exe }
    else {
        foreach ($process in @(Get-Process ([IO.Path]::GetFileNameWithoutExtension($app.Exe)) -ErrorAction SilentlyContinue)) {
            if (Test-SkinDesktopExe $Settings.activeApp $process.Path) { $found=$process.Path; break }
        }
    }
    if ($found) { $Cfg.appExe = $found; return $found }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $L.pickTitle -f $app.Name
    $dlg.Filter = $app.Exe + '|' + $app.Exe
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-SkinDesktopExe $Settings.activeApp $dlg.FileName)) {
        $Cfg.appExe = $dlg.FileName; return $dlg.FileName
    }
    return $null
}

function Invoke-ApplyTheme([string]$themeId, $Visual = $null) {
    if ($State.Busy) { Update-UiState $L.busy; return }
    if ($State.WatchBusy) {
        $State.QueuedAction = { Invoke-ApplyTheme $themeId $Visual }.GetNewClosure()
        $appBox.IsEnabled = $false; $btnSettings.IsEnabled = $false
        Update-UiState ($L.applying -f $themeId)
        Set-SkinQueuedStatus $themeId $Visual $false
        return
    }
    try { $appExe = Resolve-ZcodeExeUi }
    catch { Set-SkinPreparationFailure $themeId $Visual $false $_.Exception.Message; return }
    if (-not $appExe) { Set-SkinMissingFailure $themeId $Visual $false; return }
    $appBox.IsEnabled = $false; $btnSettings.IsEnabled = $false
    $State.Busy = $true
    $State._pendingApply = $themeId
    $State._pendingVisual = ConvertTo-SkinVisual $Visual
    $State._pendingRestore = $false
    Update-UiState (($L.applying) -f $themeId)
    $spec = @{
        Application = $Settings.activeApp; Options = @{ readability = $Cfg.readability; syncAppearance = $Cfg.syncAppearance; visual = (ConvertTo-SkinVisual $Visual) }
        Lib = $script:LibPath; LogPath = $LogPath
        ThemeId = $themeId; ThemeDir = (Join-Path $ThemesDir $themeId)
        ProcName = [IO.Path]::GetFileNameWithoutExtension($appExe); AppExe = $appExe
        Port = $Cfg.port; Restore = $false
    }
    Start-SkinUiOperationJob $spec
}

function Invoke-RestoreOfficial {
    if ($State.Busy) { Update-UiState $L.busy; return }
    if ($State.WatchBusy) {
        $State.QueuedAction = { Invoke-RestoreOfficial }
        $appBox.IsEnabled = $false; $btnSettings.IsEnabled = $false
        Update-UiState $L.restoring
        Set-SkinQueuedStatus '' $null $true
        return
    }
    try { $appExe = Resolve-ZcodeExeUi }
    catch { Set-SkinPreparationFailure '' $null $true $_.Exception.Message; return }
    if (-not $appExe) { Set-SkinMissingFailure '' $null $true; return }
    $appBox.IsEnabled = $false; $btnSettings.IsEnabled = $false
    $State.Busy = $true
    $State._pendingRestore = $true
    $State._pendingApply = ''
    Update-UiState $L.restoring
    $spec = @{
        Application = $Settings.activeApp; Options = @{ readability = $Cfg.readability; syncAppearance = $Cfg.syncAppearance }
        Lib = $script:LibPath; LogPath = $LogPath
        ThemeId = ''; ThemeDir = ''; Restore = $true
        ProcName = [IO.Path]::GetFileNameWithoutExtension($appExe); AppExe = $appExe; Port = $Cfg.port
    }
    Start-SkinUiOperationJob $spec
}

# ---- delete ----
function Invoke-DeleteTheme([string]$themeId) {
    if ($State.Busy -or $State.WatchBusy) { Update-UiState $L.busy; return }
    $dir = Join-Path $ThemesDir $themeId
    # guard: only ever remove folders directly under themes\
    $rootFull = [IO.Path]::GetFullPath($ThemesDir).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($dir).TrimEnd('\')
    if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $full -eq $rootFull) { return }
    if (-not (Test-Path $full)) { return }
    $extra = ''
    if ($State.Current -eq $themeId) { $extra = $L.dlgActiveNote }
    $res = [System.Windows.MessageBox]::Show($window, (($L.dlgDeleteBody) -f $themeId, $extra), $L.dlgDeleteTitle, 'YesNo', 'Warning')
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }
    try {
        foreach ($id in $script:SkinApps.Keys) {
            if ($Settings.apps[$id].currentTheme -eq $themeId) { $Settings.apps[$id].currentTheme = ''; $WatchCache.Remove($id) }
            [void]$Settings.apps[$id].themeAdjustments.Remove($themeId)
            if ($Settings.apps[$id].activeVisual.themeId -eq $themeId) { $Settings.apps[$id].activeVisual = $null }
        }
        Remove-Item -LiteralPath $full -Recurse -Force
        Save-Cfg
        if ($State.Current -eq $themeId) {
            $State.Current = ''
            $script:Cfg.currentTheme = ''
            $State.Bootstrap = $null
            $State.Marker = ''
            Save-Cfg
        }
        Update-UiState (($L.deleted) -f $themeId)
    } catch {
        Update-UiState (($L.deleteFailed) -f $_.Exception.Message)
    }
    Refresh-ThemeList
}

# ---- import ----
function Import-ZipFile([string]$zipPath) {
    try {
        $r = Import-CodexThemePack -ZipPath $zipPath -ThemesRoot $ThemesDir -Force
        Update-UiState (($L.imported) -f $r.Id, $r.Name)
        Refresh-ThemeList
        return $true
    } catch {
        Update-UiState (($L.importFailed) -f $_.Exception.Message)
        return $false
    }
}

# ---- gallery (api.dreamskin.cc, shared with MonkeyCodeSkin) ----
$galleryWork = {
    param($g)
    $ErrorActionPreference = 'Continue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $items = @()
    foreach ($p in $g.Pages) {
        try {
            $limit = if ($g.Limit) { [int]$g.Limit } else { 12 }
            $url = 'https://api.dreamskin.cc/v1/themes?limit=' + $limit + '&offset=' + $g.Offset
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
            $j = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
            $g.Total = [int]$j.total
            $g.Offset += [int]$j.limit
            foreach ($it in $j.items) {
                $app = ''
                if ($it.displayMeta -and $it.displayMeta.appearance) { $app = [string]$it.displayMeta.appearance }
                $bytes = 0.0
                if ($it.packageBytes) { $bytes = [double]$it.packageBytes }
                $items += @{
                    Id = [string]$it.id; ThemeId = [string]$it.themeId; Name = [string]$it.name
                    Author = [string]$it.authorDisplayName; License = [string]$it.license
                    Version = [string]$it.version; Downloads = [int]$it.downloadCount
                    SizeMB = [math]::Round($bytes / 1MB, 2)
                    Appearance = $app
                }
            }
            if ($g.Offset -ge $g.Total) { break }
        } catch { return @{ items = $items; total = $g.Total; offset = $g.Offset; error = $_.Exception.Message } }
    }
    return @{ items = $items; total = $g.Total; offset = $g.Offset; error = '' }
}

# ---- appearance icons (sun=light / moon=dark, embedded base64 png) ----
$script:IconSunB64 = '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'
$script:IconMoonB64 = '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'
$script:IconSunPath = $null
$script:IconMoonPath = $null

function Initialize-ZcIconAssets {
    # extract embedded icons to disk; WPF binds Image.Source to path strings reliably
    # (PSObject-wrapped BitmapImage NoteProperties fail to coerce in DataTemplate bindings)
    try {
        $dir = Join-Path $AppDir 'assets'
        [void](New-Item $dir -ItemType Directory -Force)
        foreach ($pair in @(@('sun', $script:IconSunB64), @('moon', $script:IconMoonB64))) {
            $p = Join-Path $dir ($pair[0] + '.png')
            if (-not (Test-Path $p)) { [IO.File]::WriteAllBytes($p, [Convert]::FromBase64String($pair[1])) }
        }
        $script:IconSunPath = Join-Path $dir 'sun.png'
        $script:IconMoonPath = Join-Path $dir 'moon.png'
    } catch {
        try { Write-AppLog ('icon assets unavailable: ' + $_.Exception.Message) } catch { }
    }
}

function ConvertTo-GalleryRow($it) {
    $row = New-Object PSObject
    $disp = [string]$it.Name
    $disp = $disp -replace '\s*\[(light|dark)\]\s*$', ''
    $mode = if ($it.Appearance) { [string]$it.Appearance } else { '' }
    $row | Add-Member NoteProperty Name $disp
    $row | Add-Member NoteProperty Mode $mode
    $row | Add-Member NoteProperty Meta ($it.Author + ' | v' + $it.Version + ' | ' + $it.SizeMB + ' MB | DL ' + $it.Downloads + ' | ' + $it.License)
    $row | Add-Member NoteProperty Id $it.Id
    $row | Add-Member NoteProperty ThemeId $it.ThemeId
    return $row
}

$galleryDone = {
    param($out)
    $r = $out | Select-Object -Last 1
    $State.GalleryBusy = $false
    $State.GalleryTotal = $r.total
    $State.GalleryOffset = $r.offset
    foreach ($it in $r.items) { if (-not ($State.Gallery | Where-Object Id -eq $it.Id)) { $State.Gallery += $it } }
    Refresh-GalleryCards
    if ($r.error) { if (-not $State.Busy -and -not $State.QueuedAction) { Update-UiState (($L.galleryError) -f $r.error) }; return }
    if (-not $State.Busy -and -not $State.QueuedAction) { Update-UiState (($L.galleryLoaded) -f $State.Gallery.Count, $State.GalleryTotal) }
    if (-not $SelfTest -and ($GallerySearch.Text.Trim() -or $GalleryFavoritesOnly.IsChecked) -and $State.GalleryOffset -lt $State.GalleryTotal) { Start-GalleryLoad 1 -All }
}

function Start-GalleryLoad([int]$pages, [switch]$All) {
    if ($State.GalleryBusy) { return }
    $State.GalleryBusy = $true
    $btnMore.IsEnabled = $false
    if ($GalleryEmpty) { $GalleryEmpty.Text=(Get-ThemeBrowserLabels).searching }
    if (-not $State.Busy -and -not $State.QueuedAction) { Update-UiState $L.loadingGallery }
    $limit = if ($All) { 24 } else { 12 }
    if ($All) { $pages = [Math]::Max(1,[Math]::Min(4,[Math]::Ceiling(($State.GalleryTotal-$State.GalleryOffset)/24.0))) }
    $g = @{ Pages = 1..$pages; Limit = $limit; Offset = $State.GalleryOffset; Total = $State.GalleryTotal }
    Start-BackgroundJob $galleryWork $g $galleryDone
}

$dlWork = {
    param($d)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    . $d.Lib
    $tmp = Join-Path $env:TEMP ('dreamskin-' + $d.Id + '.zip')
    Invoke-WebRequest -Uri ('https://api.dreamskin.cc/v1/themes/' + $d.Id + '/download') -OutFile $tmp -UseBasicParsing -TimeoutSec 180
    $len = (Get-Item $tmp).Length
    if ($len -lt 10240) { throw 'downloaded file too small' }
    $r = Import-CodexThemePack -ZipPath $tmp -ThemesRoot $d.ThemesDir -Force
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return @{ ok = $true; id = $r.Id; name = $r.Name }
}

$dlDone = {
    param($out)
    $State.Busy = $false
    $r = $out | Select-Object -Last 1
    if ($r -and $r.ok) {
        Update-UiState (($L.installed) -f $r.id, $r.name)
        Refresh-ThemeList
        Refresh-TrayMenu
    } else {
        Update-UiState $L.installFailed
    }
}

function Invoke-GalleryInstall($it) {
    if ($State.Busy -or $State.WatchBusy) { Update-UiState $L.busy; return }
    $State.Busy = $true
    Update-UiState (($L.downloading) -f $it.Name)
    $d = @{ Lib = $script:LibPath; ThemesDir = $ThemesDir; Id = $it.Id; Name = $it.Name }
    Start-BackgroundJob $dlWork $d $dlDone
}

# ---- marquee announcement (weiyun note share, fetched + cached) ----
$script:AnnCachePath = Join-Path $AppDir 'logs\announcement.txt'
$annWork = {
    param($a)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
    $r = Invoke-WebRequest -Uri 'https://share.weiyun.com/5NSFzCXr' -UserAgent $ua -UseBasicParsing -TimeoutSec 25
    $m = [regex]::Match($r.Content, 'window\.syncData\s*=\s*(\{[\s\S]*?\});\s*</script>')
    if (-not $m.Success) { throw 'syncData not found in share page' }
    $j = $m.Groups[1].Value | ConvertFrom-Json
    $txt = ''
    foreach ($n in @($j.shareInfo.note_list)) { if ($n.html_content) { $txt += [string]$n.html_content + ' ' } }
    $txt = $txt -replace '<br\s*/?>', ' ' -replace '</p>', ' ' -replace '<[^>]+>', ''
    $txt = [Net.WebUtility]::HtmlDecode($txt)
    $txt = ($txt -replace '\s+', ' ').Trim()
    if (-not $txt) { throw 'announcement is empty' }
    return @{ ok = $true; text = $txt }
}
$annDone = {
    param($out)
    $r = $out | Select-Object -Last 1
    try {
        if ($r -and $r.ok -and $r.text) {
            $marqueeText.Text = $r.text
            if ($script:mqTf) { $script:mqTf.X = $marqueeCanvas.ActualWidth + 10 }
            try { [IO.File]::WriteAllText($script:AnnCachePath, $r.text, (New-Object Text.UTF8Encoding($false))) } catch { }
        }
    } catch { }
}

# ---- update check (github release, silent fail) ----
function Compare-ZcVersions([string]$a, [string]$b) {
    try {
        $pa = @([string]$a).Split('.'); $pb = @([string]$b).Split('.')
        for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
            $xa = if ($i -lt $pa.Count) { [int]($pa[$i] -replace '\D', '') } else { 0 }
            $xb = if ($i -lt $pb.Count) { [int]($pb[$i] -replace '\D', '') } else { 0 }
            if ($xa -ne $xb) { return ($xa - $xb) }
        }
        return 0
    } catch { return 0 }
}

$updWork = {
    param($u)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $err = $null
    foreach ($i in 1..2) {
        try {
            $resp = Invoke-WebRequest -Uri $u.ApiUrl -UseBasicParsing -Headers @{ 'User-Agent' = 'SkinStudio' } -TimeoutSec 20
            $j = $resp.Content | ConvertFrom-Json
            return @{ ok = $true; tag = [string]$j.tag_name; url = [string]$j.html_url }
        } catch { $err = $_.Exception.Message; Start-Sleep -Seconds 5 }
    }
    throw $err
}

$updDone = {
    param($out)
    $r = $out | Select-Object -Last 1
    try {
        if ($r -is [string]) {
            # runspace exception surfaces as 'ERR: ...' string -> log it, retried every 30 min
            Write-AppLog ('update check failed: ' + ($r -replace '^ERR: ', ''))
            return
        }
        if ($r -and $r.ok -and $r.tag) {
            $remote = ([string]$r.tag).TrimStart('v')
            if ((Compare-ZcVersions $remote $script:AppVersion) -gt 0) {
                if ($script:NotifiedTag -ne $remote) {
                    $script:NotifiedTag = $remote
                    $script:UpdateUrl = [string]$r.url
                    $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
                    $notify.BalloonTipTitle = $L.updateTitle
                    $notify.BalloonTipText = (($L.updateText) -f $remote)
                    $notify.ShowBalloonTip(8000)
                    Write-AppLog ('update available: local=' + $script:AppVersion + ' remote=' + $remote + ' (balloon shown)')
                }
            } else {
                Write-AppLog ('update check: up to date (remote ' + $remote + ')')
            }
        } else {
            Write-AppLog 'update check failed: no data'
        }
    } catch { Write-AppLog ('update check error: ' + $_.Exception.Message) }
}

# ---- UI ----
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# extract icons BEFORE parsing the XAML: resources are declared natively in XAML
# (PS-side assignments of BitmapImage reach WPF as PSObject wrappers and break coercion)
Initialize-ZcIconAssets
$resXaml = ''
if ($script:IconSunPath -and $script:IconMoonPath) {
    $sunUri = ($script:IconSunPath -replace '\\', '/')
    $moonUri = ($script:IconMoonPath -replace '\\', '/')
    $resXaml = @"
  <Window.Resources>
    <BitmapImage x:Key="ZcSunIcon" UriSource="$sunUri" CacheOption="OnLoad"/>
    <BitmapImage x:Key="ZcMoonIcon" UriSource="$moonUri" CacheOption="OnLoad"/>
    <Style x:Key="ZcModeIcon" TargetType="Image">
      <Setter Property="Visibility" Value="Collapsed"/>
      <Style.Triggers>
        <DataTrigger Binding="{Binding Mode}" Value="light">
          <Setter Property="Source" Value="{StaticResource ZcSunIcon}"/>
          <Setter Property="Visibility" Value="Visible"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Mode}" Value="dark">
          <Setter Property="Source" Value="{StaticResource ZcMoonIcon}"/>
          <Setter Property="Visibility" Value="Visible"/>
        </DataTrigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>
"@
} else {
    $resXaml = @"
  <Window.Resources>
    <Style x:Key="ZcModeIcon" TargetType="Image">
      <Setter Property="Visibility" Value="Collapsed"/>
    </Style>
  </Window.Resources>
"@
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SkinStudio" Width="780" Height="780" MinWidth="680" MinHeight="640" WindowStartupLocation="CenterScreen">
__ZC_ICON_RESOURCES__
  <Grid Margin="10" Background="{DynamicResource Manager.Window}">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="{DynamicResource Manager.Raised}" CornerRadius="4" Height="24" Margin="0,0,0,8" ClipToBounds="True">
      <Canvas x:Name="MarqueeCanvas">
        <TextBlock x:Name="MarqueeText" Canvas.Top="4" Foreground="{DynamicResource Manager.Muted}" Text=""/>
      </Canvas>
    </Border>
    <Border Grid.Row="1" Background="{DynamicResource Manager.Raised}" CornerRadius="6" Padding="10" Margin="0,0,0,8">
      <StackPanel>
      <DockPanel Margin="0,0,0,9">
        <ComboBox x:Name="ManagerThemeBox" DockPanel.Dock="Right" Width="165"/>
        <TextBlock x:Name="ManagerThemeLabel" VerticalAlignment="Center" FontWeight="SemiBold"/>
      </DockPanel>
      <DockPanel Margin="0,0,0,8">
        <Button x:Name="BtnSettings" DockPanel.Dock="Right" Content="App / Port" Margin="8,0,0,0" Padding="8,2"/>
        <Button x:Name="BtnCompatibility" DockPanel.Dock="Right" Content="Compatibility" Margin="8,0,0,0" Padding="8,2"/>
        <ComboBox x:Name="AppBox" DockPanel.Dock="Left" Width="135" Height="26" Margin="0,0,10,0" Visibility="Collapsed"/>
        <ComboBox x:Name="LangBox" DockPanel.Dock="Right" Width="110" Height="24" VerticalContentAlignment="Center"/>
        <TextBlock x:Name="StatusText" Text="ready" FontWeight="Bold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
      <UniformGrid x:Name="AppCards" Columns="5"/>
      <Border x:Name="OperationPanel" Visibility="Collapsed" Background="{DynamicResource Manager.AccentSoft}" CornerRadius="6" Padding="10" Margin="0,8,0,0">
        <StackPanel>
          <TextBlock x:Name="OperationTarget" FontWeight="SemiBold" Foreground="{DynamicResource Manager.Text}" Margin="0,0,0,6" TextTrimming="CharacterEllipsis"/>
          <UniformGrid x:Name="OperationSteps" Columns="4" Margin="0,0,0,6"/>
          <ProgressBar x:Name="OperationProgress" Minimum="0" Maximum="4" Height="3" Margin="0,0,0,6"/>
          <TextBlock x:Name="OperationDetail" TextWrapping="Wrap" Foreground="{DynamicResource Manager.Muted}"/>
          <WrapPanel x:Name="OperationActions" Margin="0,7,0,0" Visibility="Collapsed">
            <Button x:Name="BtnRetryOperation" Padding="10,3" Margin="0,0,8,0"/>
            <Button x:Name="BtnOperationLog" Padding="10,3"/>
          </WrapPanel>
        </StackPanel>
      </Border>
      </StackPanel>
    </Border>
    <TabControl Grid.Row="2">
      <TabItem x:Name="TabMy" Header="My Themes">
        <DockPanel Margin="8">
          <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
            <CheckBox x:Name="ThemeFavoritesOnly" DockPanel.Dock="Right" VerticalAlignment="Center" Margin="12,0,0,0"/>
            <TextBlock x:Name="ThemeCount" DockPanel.Dock="Right" VerticalAlignment="Center" Foreground="{DynamicResource Manager.Muted}" Margin="10,0,0,0"/>
            <Button x:Name="ThemeSearchClear" DockPanel.Dock="Right" Content="×" Width="25" Margin="4,0,0,0"/>
            <Grid><TextBox x:Name="ThemeSearch" Height="28" Padding="7,3"/><TextBlock x:Name="ThemeSearchHint" Margin="9,5,0,0" Foreground="{DynamicResource Manager.Muted}" IsHitTestVisible="False"/></Grid>
          </DockPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
            <Button x:Name="BtnApply" Content="Apply selected" Style="{DynamicResource Manager.PrimaryButton}" Width="120" Height="30" Margin="0,0,8,0"/>
            <Button x:Name="BtnImport" Content="Import zip..." Width="110" Height="30" Margin="0,0,8,0"/>
            <Button x:Name="BtnRestore" Content="Official look" Width="110" Height="30"/>
            <Button x:Name="BtnDelete" Content="Delete theme" Width="110" Height="30" Margin="8,0,0,0"/>
          </StackPanel>
          <Grid>
            <ListBox x:Name="ThemeList" AllowDrop="True"/>
            <TextBlock x:Name="ThemeEmpty" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource Manager.Muted}" TextWrapping="Wrap" Margin="18" IsHitTestVisible="False"/>
          </Grid>
        </DockPanel>
      </TabItem>
      <TabItem x:Name="TabGallery" Header="主题仓库(远程)">
        <DockPanel Margin="8">
          <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
            <CheckBox x:Name="GalleryFavoritesOnly" DockPanel.Dock="Right" VerticalAlignment="Center" Margin="12,0,0,0"/>
            <TextBlock x:Name="GalleryCount" DockPanel.Dock="Right" VerticalAlignment="Center" Foreground="{DynamicResource Manager.Muted}" Margin="10,0,0,0"/>
            <Button x:Name="GallerySearchClear" DockPanel.Dock="Right" Content="×" Width="25" Margin="4,0,0,0"/>
            <Grid><TextBox x:Name="GallerySearch" Height="28" Padding="7,3"/><TextBlock x:Name="GallerySearchHint" Margin="9,5,0,0" Foreground="{DynamicResource Manager.Muted}" IsHitTestVisible="False"/></Grid>
          </DockPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
            <Button x:Name="BtnInstall" Content="Download and install selected" Width="200" Height="30" Margin="0,0,8,0"/>
            <Button x:Name="BtnMore" Content="Load more" Width="100" Height="30" Margin="0,0,8,0"/>
            <Button x:Name="BtnOpenWeb" Content="Open in browser" Width="120" Height="30"/>
          </StackPanel>
          <Grid>
            <ListBox x:Name="GalleryList"/>
            <TextBlock x:Name="GalleryEmpty" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource Manager.Muted}" TextWrapping="Wrap" Margin="18" IsHitTestVisible="False"/>
          </Grid>
        </DockPanel>
      </TabItem>
    </TabControl>
    <StackPanel Grid.Row="3">
    <Expander x:Name="VisualExpander" Header="外观调节" IsExpanded="False" Margin="0,8,0,0">
      <Border Background="{DynamicResource Manager.Raised}" CornerRadius="6" Padding="10" Margin="0,5,0,0">
        <StackPanel>
          <TextBlock x:Name="VisualTarget" TextWrapping="Wrap" Foreground="{DynamicResource Manager.Muted}" Margin="0,0,0,6"/>
          <Grid x:Name="VisualEditor">
            <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/><ColumnDefinition Width="55"/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBlock x:Name="VisualPresetLabel" Grid.Row="0" VerticalAlignment="Center"/>
            <ComboBox x:Name="VisualPreset" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,6"/>
            <TextBlock x:Name="VisualOpacityLabel" Grid.Row="1" VerticalAlignment="Center"/>
            <Slider x:Name="VisualOpacity" Grid.Row="1" Grid.Column="1" Minimum="0" Maximum="100" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,4,8,6"/>
            <TextBlock x:Name="VisualOpacityValue" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center"/>
            <TextBlock x:Name="VisualBlurLabel" Grid.Row="2" VerticalAlignment="Center"/>
            <Slider x:Name="VisualBlur" Grid.Row="2" Grid.Column="1" Minimum="0" Maximum="20" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,4,8,6"/>
            <TextBlock x:Name="VisualBlurValue" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center"/>
            <TextBlock x:Name="VisualPositionLabel" Grid.Row="3" VerticalAlignment="Center"/>
            <ComboBox x:Name="VisualPosition" Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2"/>
          </Grid>
          <WrapPanel Margin="0,8,0,4">
            <Button x:Name="VisualApplySave" Padding="9,4" Margin="0,0,8,0"/>
            <Button x:Name="VisualApplySaved" Padding="9,4" Margin="0,0,8,0"/>
            <Button x:Name="VisualReset" Padding="9,4"/>
          </WrapPanel>
          <TextBlock x:Name="VisualHint" Foreground="{DynamicResource Manager.Muted}" TextWrapping="Wrap"/>
        </StackPanel>
      </Border>
    </Expander>
    <CheckBox x:Name="SyncAppearanceBox" Content="Match app appearance to skin" Margin="0,8,0,0"/>
    <CheckBox x:Name="ReadabilityBox" Content="Improve readability" Margin="0,8,0,0"/>
    <TextBlock x:Name="HintText" Text="" TextWrapping="Wrap" Foreground="{DynamicResource Manager.Muted}" Margin="0,6,0,0"/>
    </StackPanel>
    <DockPanel Grid.Row="4" Margin="0,6,0,0">
      <Button x:Name="BtnDataFolder" DockPanel.Dock="Left" Content="Data folder" Padding="8,3" HorizontalAlignment="Left" Margin="0,0,8,0"/>
      <TextBlock DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center">
        <Hyperlink x:Name="RepoLink" NavigateUri="https://github.com/wh68666/skinstudio" Foreground="{DynamicResource Manager.Accent}" TextDecorations="None">
          <Run x:Name="VerRun" Text="v"/><Run Text="  |  github.com/wh68666/skinstudio"/>
        </Hyperlink>
      </TextBlock>
    </DockPanel>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml.Replace('__ZC_ICON_RESOURCES__', $resXaml))
$marqueeText = $window.FindName('MarqueeText')
$marqueeCanvas = $window.FindName('MarqueeCanvas')
$statusText = $window.FindName('StatusText')
$hintText = $window.FindName('HintText')
$themeList = $window.FindName('ThemeList')
$galleryList = $window.FindName('GalleryList')
$langBox = $window.FindName('LangBox')
$appBox = $window.FindName('AppBox')
$btnSettings = $window.FindName('BtnSettings')
$readabilityBox = $window.FindName('ReadabilityBox')
$syncAppearanceBox = $window.FindName('SyncAppearanceBox')
$tabMy = $window.FindName('TabMy')
$tabGallery = $window.FindName('TabGallery')
$btnImport = $window.FindName('BtnImport')
$btnRestore = $window.FindName('BtnRestore')
$btnDelete = $window.FindName('BtnDelete')
$btnInstall = $window.FindName('BtnInstall')
$btnMore = $window.FindName('BtnMore')
$btnOpenWeb = $window.FindName('BtnOpenWeb')
$repoLink = $window.FindName('RepoLink')
$verRun = $window.FindName('VerRun')
# footer: live version + repo link (opens in browser)
try { $verRun.Text = 'v' + $script:AppVersion } catch { }
$repoLink.Add_RequestNavigate({ param($s, $e) try { [void][Diagnostics.Process]::Start($e.Uri.AbsoluteUri) } catch { }; $e.Handled = $true })
. (Join-Path $ResourceDir 'skin-manager-theme.ps1')
$window.FindName('BtnDataFolder').Add_Click({
    try {
        [void][Diagnostics.Process]::Start((New-SkinDataFolderStartInfo $script:AppDir))
    } catch {
        Write-AppLog ('DATA FOLDER OPEN ERROR: '+$script:AppDir+' | '+$_.Exception.Message)
        $message=if($Cfg.lang -eq 'zh-CN'){'无法打开数据文件夹。请检查目录是否可访问。'}elseif($Cfg.lang -eq 'zh-TW'){'無法開啟資料夾。請檢查目錄是否可存取。'}else{'Cannot open the data folder. Check that the directory is accessible.'}
        [void][Windows.Forms.MessageBox]::Show(($message+"`n`n"+$script:AppDir+"`n`n"+$_.Exception.Message),'SkinStudio')
    }
})

# ---- language (en / zh-CN / zh-TW) ----
$script:LangCodes = @('en', 'zh-CN', 'zh-TW')
$script:LangDisplay = @('English', '简体中文', '繁體中文')

function Get-LangTable([string]$lang) {
    if ($lang -eq 'zh-CN') {
        return @{
            winTitle = 'SkinStudio'; official = '（官方）'
            tabMy = '我的主题'; tabGallery = '主题仓库(远程)'
            btnApply = '应用所选'; btnImport = '导入 zip...'; btnRestore = '恢复官方外观'; btnDelete = '删除主题'
            btnInstall = '下载并安装所选'; btnMore = '加载更多'; btnOpenWeb = '在浏览器打开'
            ready = '就绪'; busy = '处理中...'
            applying = '正在应用 {0} ...'; restoring = '正在恢复官方外观 ...'
            loadingGallery = '正在加载图库 ...'; downloading = '正在下载 {0} ...'
            imported = '导入成功: {0} ({1})'; importFailed = '导入失败: {0}'
            installed = '安装成功: {0} ({1})'; installFailed = '下载/导入失败（详见日志）'
            galleryError = '图库错误: {0}'; galleryLoaded = '图库: 已加载 {0} / {1}'
            deleted = '已删除: {0}'; deleteFailed = '删除失败: {0}'
            ok = '成功 ({0})'; fail = '失败: {0}'
            currentSkin = '当前皮肤: {0}   |   将 .zip 拖入列表即可导入'
            updateTitle = 'SkinStudio 更新'; updateText = '发现新版本 {0}，点击托盘气泡打开下载页'
            pickTitle = '选择 {0} 桌面端'; appSettings = '程序 / 端口'; syncAppearance = '随皮肤自动切换浅色 / 深色外观'; readabilityZcode = '轻柔可读性（玻璃面板 / 清晰图标）'; readability = '轻柔可读性（玻璃导航 / 清晰图标）'; restartHint = '首次换肤和恢复外观会重启所选应用，请先保存工作。'
            noZcodeApp = '未找到 {0} 桌面端，请先安装官方程序'
            cdpFail = '无法启动 ZCode（程序未找到或调试端口未就绪）'
            pushFail = '主题推送失败（页面未就绪，请重试）'
            srcGallery = '图库'; srcLocal = '本地'
            trayOfficial = '官方外观（无皮肤）'; trayOpenWindow = '打开窗口'; trayExit = '退出'
            dlgDeleteTitle = '删除主题'
            dlgDeleteBody = "确定永久删除主题「{0}」吗？{1}`n`n主题包文件夹将被移除，此操作无法撤销。"
            dlgActiveNote = "`n`n注意：这是当前使用中的皮肤。"
            annDefault = '欢迎使用 SkinStudio'
            exitMsg = '已退出SkinStudio，皮肤将持续运行'
        }
    }
    if ($lang -eq 'zh-TW') {
        return @{
            winTitle = 'SkinStudio'; official = '（官方）'
            tabMy = '我的主題'; tabGallery = '主題倉庫(遠端)'
            btnApply = '套用所選'; btnImport = '匯入 zip...'; btnRestore = '還原官方外觀'; btnDelete = '刪除主題'
            btnInstall = '下載並安裝所選'; btnMore = '載入更多'; btnOpenWeb = '在瀏覽器開啟'
            ready = '就緒'; busy = '處理中...'
            applying = '正在套用 {0} ...'; restoring = '正在還原官方外觀 ...'
            loadingGallery = '正在載入圖庫 ...'; downloading = '正在下載 {0} ...'
            imported = '匯入成功: {0} ({1})'; importFailed = '匯入失敗: {0}'
            installed = '安裝成功: {0} ({1})'; installFailed = '下載/匯入失敗（詳見日誌）'
            galleryError = '圖庫錯誤: {0}'; galleryLoaded = '圖庫: 已載入 {0} / {1}'
            deleted = '已刪除: {0}'; deleteFailed = '刪除失敗: {0}'
            ok = '成功 ({0})'; fail = '失敗: {0}'
            currentSkin = '目前面板: {0}   |   將 .zip 拖入清單即可匯入'
            updateTitle = 'SkinStudio 更新'; updateText = '發現新版本 {0}，點擊托盤氣泡開啟下載頁'
            pickTitle = '選擇 {0} 桌面端'; appSettings = '程式 / 連接埠'; syncAppearance = '隨皮膚自動切換淺色 / 深色外觀'; readabilityZcode = '輕柔可讀性（玻璃面板 / 清晰圖示）'; readability = '輕柔可讀性（玻璃導覽 / 清晰圖示）'; restartHint = '首次換膚和恢復外觀會重啟所選應用，請先儲存工作。'
            noZcodeApp = '未找到 {0} 桌面端，請先安裝官方程式'
            cdpFail = '無法啟動 ZCode（程式未找到或除錯連接埠未就緒）'
            pushFail = '主題推送失敗（頁面未就緒，請重試）'
            srcGallery = '圖庫'; srcLocal = '本機'
            trayOfficial = '官方外觀（無面板）'; trayOpenWindow = '開啟視窗'; trayExit = '結束'
            dlgDeleteTitle = '刪除主題'
            dlgDeleteBody = "確定永久刪除主題「{0}」嗎？{1}`n`n主題包資料夾將被移除，此操作無法復原。"
            dlgActiveNote = "`n`n注意：這是目前使用中的面板。"
            annDefault = '歡迎使用 SkinStudio'
            exitMsg = '已結束 SkinStudio，面板將持續運行'
        }
    }
    return @{
        winTitle = 'SkinStudio'; official = '(official)'
        tabMy = 'My Themes'; tabGallery = 'Repository (Remote)'
        btnApply = 'Apply selected'; btnImport = 'Import zip...'; btnRestore = 'Official look'; btnDelete = 'Delete theme'
        btnInstall = 'Download and install selected'; btnMore = 'Load more'; btnOpenWeb = 'Open in browser'
        ready = 'ready'; busy = 'busy...'
        applying = 'applying {0} ...'; restoring = 'restoring official ...'
        loadingGallery = 'loading gallery ...'; downloading = 'downloading {0} ...'
        imported = 'imported: {0} ({1})'; importFailed = 'import failed: {0}'
        installed = 'installed: {0} ({1})'; installFailed = 'download/import failed (see log)'
        galleryError = 'gallery error: {0}'; galleryLoaded = 'gallery: {0} / {1} loaded'
        deleted = 'deleted: {0}'; deleteFailed = 'delete failed: {0}'
        ok = 'OK ({0})'; fail = 'FAIL: {0}'
        currentSkin = 'current skin: {0}   |   drop a .zip into the list to import'
        updateTitle = 'SkinStudio update'; updateText = 'New version {0} available - click the tray balloon to open the download page'
        pickTitle = 'Select the {0} desktop app'; appSettings = 'App / Port'; syncAppearance = 'Match app light / dark mode to skin'; readabilityZcode = 'Soft readability (glass panels / clear icons)'; readability = 'Soft readability (glass navigation / clearer icons)'; restartHint = 'First apply and restore restart the selected app. Save your work first.'
        noZcodeApp = '{0} desktop app not found. Please install the official app first'
        cdpFail = 'failed to start ZCode (app not found or debug port not ready)'
        pushFail = 'theme push failed (page not ready, please retry)'
        srcGallery = 'gallery'; srcLocal = 'local'
        trayOfficial = 'Official look (no skin)'; trayOpenWindow = 'Open window'; trayExit = 'Exit'
        dlgDeleteTitle = 'Delete theme'
        dlgDeleteBody = "Delete theme '{0}' permanently?{1}`n`nThe theme pack folder will be removed and cannot be undone."
        dlgActiveNote = "`n`nNOTE: this is the currently active skin."
        annDefault = 'Welcome to SkinStudio'
        exitMsg = 'SkinStudio exited. The skin will keep running.'
    }
}

function Set-Lang([string]$lang) {
    if ($script:LangCodes -notcontains $lang) { $lang = 'en' }
    $script:Cfg.lang = $lang
    $script:L = Get-LangTable $lang
    $window.Title = $L.winTitle
    $window.FindName('BtnDataFolder').Content=if($lang -eq 'zh-CN'){'打开数据文件夹'}elseif($lang -eq 'zh-TW'){'開啟資料夾'}else{'Open data folder'}
    $folderHint=if($lang -eq 'zh-CN'){'保存主题、收藏、外观微调和日志的位置'}elseif($lang -eq 'zh-TW'){'儲存主題、收藏、外觀微調與日誌的位置'}else{'Stores themes, favorites, appearance adjustments and logs'}
    $window.FindName('BtnDataFolder').ToolTip=$folderHint+"`n"+$script:AppDir
    Sync-SkinManagerThemeUi
    $btnSettings.Content = $L.appSettings
    Sync-ReadabilityControl
    Sync-SkinVisualUi
    $tabMy.Header = $L.tabMy
    $tabGallery.Header = $L.tabGallery
    $btnApply.Content = $L.btnApply
    $btnImport.Content = $L.btnImport
    $btnRestore.Content = $L.btnRestore
    $btnDelete.Content = $L.btnDelete
    $btnInstall.Content = $L.btnInstall
    $btnMore.Content = $L.btnMore
    $btnOpenWeb.Content = $L.btnOpenWeb
    # refresh hint line (uses current $L) + theme list Meta tags; Update-UiState also refreshes tray menu
    Update-UiState $L.ready
    Refresh-ThemeList
}

function Update-UiState([string]$msg) {
    $window.Dispatcher.Invoke([action] {
        $statusText.Text = $msg
        Update-SkinVisualAvailability
        $cur = if ($State.Current) { $State.Current } else { $L.official }
        $hintText.Text = (Get-SkinApp $Settings.activeApp).Name + ' | ' + (($L.currentSkin) -f $cur) + ' | CDP ' + $Cfg.port + "`n" + $L.restartHint
        try { $notify.Text = 'SkinStudio v' + $script:AppVersion + ' - ' + $cur } catch { }
        Refresh-TrayMenu
        Update-SkinStatusUi
    })
}

function Refresh-ThemeList([switch]$PreserveDraft) {
    $State.Themes = Get-InstalledThemes
    Refresh-LocalThemeCards -PreserveDraft:$PreserveDraft
    Refresh-GalleryCards
}

# ---- tray icon ----
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
$notify.Text = 'SkinStudio'
$bmp = New-Object System.Drawing.Bitmap(32, 32)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0,0)), (New-Object System.Drawing.Point(32,32)), [System.Drawing.Color]::FromArgb(255,34,38,68), [System.Drawing.Color]::FromArgb(255,124,92,255))
$g.FillRectangle($brush, 2, 2, 28, 28)
$g.DrawString('S', (New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, 7, 1)
$g.Dispose()
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$notify.Icon = $icon

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$notify.ContextMenuStrip = $trayMenu
$notify.Add_DoubleClick({ Show-MainWindow })
$notify.Add_BalloonTipClicked({ try { if ($script:UpdateUrl) { Start-Process $script:UpdateUrl } } catch { } })

function Refresh-TrayMenu {
    $trayMenu.Items.Clear()
    foreach ($id in $script:SkinApps.Keys) {
        $appItem = $trayMenu.Items.Add($script:SkinApps[$id].Name)
        $appItem.Checked = ($id -eq $Settings.activeApp)
        $selectedId = $id
        $appIds = @($script:SkinApps.Keys)
        $appItem.Add_Click({ $appBox.SelectedIndex = [array]::IndexOf($appIds, $selectedId) }.GetNewClosure())
    }
    [void]$trayMenu.Items.Add('-')
    foreach ($t in $State.Themes) {
        $mi = $trayMenu.Items.Add($t.Name)
        $mi.Checked = ($t.Id -eq $State.Current)
        $id = $t.Id
        $mi.Add_Click({ Invoke-ApplyTheme $id }.GetNewClosure())
    }
    [void]$trayMenu.Items.Add('-')
    $mi2 = $trayMenu.Items.Add($L.trayOfficial)
    $mi2.Checked = (-not $State.Current)
    $mi2.Add_Click({ Invoke-RestoreOfficial })
    [void]$trayMenu.Items.Add('-')
    [void]($trayMenu.Items.Add($L.trayOpenWindow).Add_Click({ Show-MainWindow }))
    $miX = $trayMenu.Items.Add($L.trayExit)
    $miX.Add_Click({ $window.Close() })
}

function Show-MainWindow {
    $window.Show()
    $window.Activate()
    $window.WindowState = 'Normal'
}

# ---- events ----
$window.Add_Closing({ try { $notify.Visible = $false; $notify.Dispose(); $watchTimer.Stop(); $script:StatusTimer.Stop(); $script:Mutex.ReleaseMutex() } catch { } })
$window.Add_StateChanged({
    if ($window.WindowState -eq 'Minimized') { $window.Hide() }
})

$btnApply = $window.FindName('BtnApply')
$btnApply.Add_Click({
    $sel = $themeList.SelectedItem
    if ($sel) { Invoke-ApplyTheme $sel.Id }
})
$window.FindName('BtnImport').Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Theme package (*.zip)|*.zip'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [void](Import-ZipFile $dlg.FileName) }
})
$window.FindName('BtnRestore').Add_Click({ Invoke-RestoreOfficial })
$window.FindName('BtnDelete').Add_Click({
    $sel = $themeList.SelectedItem
    if ($sel) { Invoke-DeleteTheme ([string]$sel.Id) }
})
$langBox.Add_SelectionChanged({
    try {
        $i = $langBox.SelectedIndex
        if ($i -ge 0 -and $i -lt $script:LangCodes.Count) {
            $code = $script:LangCodes[$i]
            if ($script:Cfg.lang -ne $code) { Set-Lang $code; Save-Cfg }
        }
    } catch { }
})
$themeList.Add_Drop({
    $files = $_.Data.GetData([Windows.DataFormats]::FileDrop)
    foreach ($f in $files) { if ($f -like '*.zip') { [void](Import-ZipFile $f) } }
    $_.Handled = $true
})
$themeList.Add_DragOver({ $_.Effects = [Windows.DragDropEffects]::Copy; $_.Handled = $true })
$themeList.Add_MouseDoubleClick({ param($sender,$e) if (Test-ThemeFavoriteOrigin $e) { $e.Handled=$true; return }; if ($themeList.SelectedItem) { Invoke-ApplyTheme $themeList.SelectedItem.Id } })

$galleryList.Add_MouseDoubleClick({
    param($sender,$e)
    if (Test-ThemeFavoriteOrigin $e) { $e.Handled=$true; return }
    $sel = $galleryList.SelectedItem
    if ($sel) { Invoke-GalleryInstall ($State.Gallery | Where-Object { $_.Id -eq $sel.Id } | Select-Object -First 1) }
})
$window.FindName('BtnInstall').Add_Click({
    $sel = $galleryList.SelectedItem
    if ($sel) { Invoke-GalleryInstall ($State.Gallery | Where-Object { $_.Id -eq $sel.Id } | Select-Object -First 1) }
})
$window.FindName('BtnMore').Add_Click({ Show-MoreGalleryCards })
$window.FindName('BtnOpenWeb').Add_Click({ [Diagnostics.Process]::Start('https://dreamskin.cc/gallery') })

function Complete-SkinWatch {
    $State.WatchBusy = $false
    $action = $State.QueuedAction
    $State.QueuedAction = $null
    if ($action) {
        $appBox.IsEnabled = $true; $btnSettings.IsEnabled = $true
        & $action
    }
}

# Watch every configured application, including profiles not selected in the UI.
# One background job at a time avoids blocking the WPF dispatcher on CDP calls.
$State.WatchBusy = $false
$watchWork = {
    param($spec)
    . $spec.Lib
    foreach ($profile in $spec.Profiles) {
        try {
            $pages = @(Get-SkinTargets $profile.Application $profile.AppExe $profile.Port)
            if (-not $pages.Count) { continue }
            $pack = Get-ThemePack $profile.ThemeDir
            $marker = Get-SkinMarker $pack $profile.Options $profile.Application
            $js = $null
            foreach ($target in $pages) {
                if ((Get-TargetSkinMarker $target) -eq $marker) { continue }
                if (-not $js) { $js = New-SkinBootstrapJs $profile.Application $pack $profile.Options }
                [void](Push-ThemeToTarget $target $js $spec.LogPath)
            }
        } catch { }
    }
}
$watchTimer = New-Object System.Windows.Threading.DispatcherTimer
$watchTimer.Interval = [TimeSpan]::FromSeconds(5)
$watchTimer.Add_Tick({
    if ($State.Busy -or $State.WatchBusy) { return }
    $profiles = @()
    foreach ($id in $script:SkinApps.Keys) {
        $profile = $Settings.apps[$id]
        if ($profile.currentTheme -and $profile.appExe) {
            $profiles += @{ Application = $id; Options = (Get-SkinThemeOptions $profile $profile.currentTheme); AppExe = $profile.appExe; Port = $profile.port; ThemeDir = (Join-Path $ThemesDir $profile.currentTheme) }
        }
    }
    if (-not $profiles.Count) { return }
    $State.WatchBusy = $true
    Start-BackgroundJob $watchWork @{ Lib = $script:LibPath; Profiles = $profiles; LogPath = $LogPath } { param($out) Complete-SkinWatch }
})
$watchTimer.Start()


# ---- self test mode (no UI, for CI-ish verification) ----
function Select-SkinApplication([string]$id) {
    if ($State.Busy -or $State.QueuedAction) { return $false }
    $lang = $Cfg.lang
    $Settings.activeApp = $id
    $script:Cfg = $Settings.apps[$id]
    # Keep programmatic selection (including self-tests) in sync with the combo.
    $script:SelectingApp = $true
    try { $appBox.SelectedIndex = [array]::IndexOf(@($script:SkinApps.Keys), $id) }
    finally { $script:SelectingApp = $false }
    $Cfg.lang = $lang
    $State.Current = [string]$Cfg.currentTheme
    $State.Marker = ''; $State.Bootstrap = $null; $State.Watch = @()
    $State.Bootstrap = Get-CurrentBootstrap
    Sync-ReadabilityControl
    Save-Cfg
    Refresh-ThemeList
    Update-UiState $L.ready
    if (-not $SelfTest) { Start-SkinHealthScan }
    return $true
}
function Sync-ReadabilityControl {
    $script:UpdatingReadability = $true
    try {
        $readabilityBox.Content = if ($Settings.activeApp -eq 'zcode') { $L.readabilityZcode } else { $L.readability }
        $syncAppearanceBox.Content = $L.syncAppearance
        $syncAppearanceBox.IsChecked = Test-SkinAppearanceSync $Cfg
        $readabilityBox.Visibility = if ($Settings.activeApp -in @('codex','zcode','opencode','workbuddy')) { 'Visible' } else { 'Collapsed' }
        $readabilityBox.IsChecked = Test-SkinReadability $Cfg
    } finally { $script:UpdatingReadability = $false }
}
$syncAppearanceBox.Add_Click({
    if ($script:UpdatingReadability) { return }
    if ($State.Busy -or $State.QueuedAction) { Sync-ReadabilityControl; return }
    $Cfg.syncAppearance = [bool]$syncAppearanceBox.IsChecked
    Save-Cfg
    $State.Bootstrap = Get-CurrentBootstrap
    if (-not $SelfTest -and $State.Current -and (Test-SkinCdpOwner $Settings.activeApp $Cfg.appExe $Cfg.port)) { Invoke-ApplyTheme $State.Current (Get-SkinVisualAdjustment $Cfg $State.Current) }
})
$readabilityBox.Add_Click({
    if ($script:UpdatingReadability) { return }
    if ($State.Busy -or $State.QueuedAction) { Sync-ReadabilityControl; return }
    $Cfg.readability = [bool]$readabilityBox.IsChecked
    Save-Cfg
    $State.Bootstrap = Get-CurrentBootstrap
    if (-not $SelfTest -and $State.Current -and (Test-SkinCdpOwner $Settings.activeApp $Cfg.appExe $Cfg.port)) { Invoke-ApplyTheme $State.Current (Get-SkinVisualAdjustment $Cfg $State.Current) }
})

$appBox.Add_SelectionChanged({
    if ($script:SelectingApp) { return }
    $id = @($script:SkinApps.Keys)[$appBox.SelectedIndex]
    if (-not (Select-SkinApplication $id)) {
        $script:SelectingApp = $true
        $appBox.SelectedIndex = [array]::IndexOf(@($script:SkinApps.Keys), $Settings.activeApp)
        $script:SelectingApp = $false
    }
})
$btnSettings.Add_Click({
    if ($State.Busy -or $State.WatchBusy) { return }
    $app = Get-SkinApp $Settings.activeApp
    $appIds = @($script:SkinApps.Keys)
    $dialog = New-Object Windows.Window
    Initialize-SkinManagerWindow $dialog
    $dialog.Title = $app.Name + ' - ' + $L.appSettings
    $dialog.Owner = $window; $dialog.Width = 560; $dialog.Height = 285; $dialog.WindowStartupLocation = 'CenterOwner'
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '16'
    $label = New-Object Windows.Controls.TextBlock; $label.Text = $app.Exe; $panel.Children.Add($label) | Out-Null
    $path = New-Object Windows.Controls.TextBox; $path.Text = $Cfg.appExe; $path.Margin = '0,6,0,8'; $panel.Children.Add($path) | Out-Null
    $browse = New-Object Windows.Controls.Button; $browse.Content = '...'; $browse.HorizontalAlignment = 'Right'
    $browse.Add_Click({
        $picker = New-Object System.Windows.Forms.OpenFileDialog; $picker.Filter = $app.Exe + '|' + $app.Exe
        if ($picker.ShowDialog() -eq 'OK') { $path.Text = $picker.FileName }
    }.GetNewClosure()); $panel.Children.Add($browse) | Out-Null
    $portLabel = New-Object Windows.Controls.TextBlock; $portLabel.Text = 'CDP (1024-65535)'; $panel.Children.Add($portLabel) | Out-Null
    $port = New-Object Windows.Controls.TextBox; $port.Text = [string]$Cfg.port; $port.Margin = '0,8,0,8'; $panel.Children.Add($port) | Out-Null
    $validation = New-Object Windows.Controls.TextBlock; Set-SkinManagerBrush $validation Foreground Danger; $validation.TextWrapping = 'Wrap'; $panel.Children.Add($validation) | Out-Null
    $save = New-Object Windows.Controls.Button; $save.Content = 'OK'; $save.Width = 90; $save.HorizontalAlignment = 'Right'
    $save.Add_Click({
        $number = 0
        if (-not [int]::TryParse($port.Text, [ref]$number) -or $number -lt 1024 -or $number -gt 65535) { $validation.Text = 'CDP: 1024-65535'; return }
        foreach ($otherId in $appIds) { if ($otherId -ne $Settings.activeApp -and $Settings.apps[$otherId].port -eq $number) { $validation.Text = 'CDP ' + $number + ': ' + $otherId; return } }
        if ($path.Text -and -not (Test-SkinDesktopExe $Settings.activeApp $path.Text)) { $validation.Text = $L.noZcodeApp -f $app.Name; return }
        $Cfg.appExe = $path.Text; $Cfg.port = $number; Save-Cfg; Update-UiState $L.ready; $dialog.Close(); Start-SkinHealthScan -Discover
    }.GetNewClosure()); $panel.Children.Add($save) | Out-Null
    $dialog.Content = $panel; [void]$dialog.ShowDialog()
})

# ---- boot ----
. (Join-Path $ResourceDir 'skin-theme-browser.ps1')
. (Join-Path $ResourceDir 'skin-visual-ui.ps1')
. (Join-Path $ResourceDir 'skin-status-ui.ps1')
. (Join-Path $ResourceDir 'skin-compatibility-ui.ps1')
if (-not $Cfg.lang) {
    $c = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if (@('zh-TW', 'zh-HK', 'zh-MO', 'zh-Hant') -contains $c) { $Cfg.lang = 'zh-TW' } elseif ($c -like 'zh*') { $Cfg.lang = 'zh-CN' } else { $Cfg.lang = 'en' }
}
$script:SelectingApp = $true
foreach ($app in $script:SkinApps.Values) { [void]$appBox.Items.Add($app.Name) }
$appBox.SelectedIndex = [array]::IndexOf(@($script:SkinApps.Keys), $Settings.activeApp)
$script:SelectingApp = $false
Set-Lang $Cfg.lang
foreach ($n in $script:LangDisplay) { [void]$langBox.Items.Add($n) }
$langBox.SelectedIndex = [array]::IndexOf($script:LangCodes, $Cfg.lang)
if ($Cfg.currentTheme -and (Test-Path (Join-Path $ThemesDir $Cfg.currentTheme))) {
    $State.Current = $Cfg.currentTheme
    $State.Bootstrap = Get-CurrentBootstrap
}
if ($SelfTest) {
    $watchTimer.Stop(); $notify.Visible = $false
    $probe = @{ Done = $false; Ok = $false }
    Start-BackgroundJob { param($value) return @{ answer = $value } } 'ok' { param($out) $probe.Ok = ($out[-1].answer -eq 'ok'); $probe.Done = $true }.GetNewClosure()
    $frame = New-Object Windows.Threading.DispatcherFrame
    $timeout = (Get-Date).AddSeconds(10)
    $probeTimer = New-Object Windows.Threading.DispatcherTimer
    $probeTimer.Interval = [TimeSpan]::FromMilliseconds(30)
    $probeTimer.Add_Tick({ if ($probe.Done -or (Get-Date) -gt $timeout) { $frame.Continue = $false } }.GetNewClosure())
    $probeTimer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    $probeTimer.Stop()
    if (-not $probe.Ok) { throw 'Background runspace / UI callback self-test failed' }
    $State.WatchBusy = $true
    $queueProbe = @{ Ran = $false }
    $State.QueuedAction = { $queueProbe.Ran = $true }.GetNewClosure()
    Complete-SkinWatch
    if ($State.WatchBusy -or $State.QueuedAction -or -not $queueProbe.Ran) { throw 'Queued action was lost after watcher completion' }
    $lines = @('SkinStudio ' + $script:AppVersion)
    $lines += @(('resources='+$ResourceDir),('data='+$AppDir))
    foreach ($id in $script:SkinApps.Keys) {
        $pack = Get-ThemePack (Join-Path $ThemesDir 'aurora')
        $js = New-SkinBootstrapJs $id $pack
        $lines += $id + ': bootstrap bytes=' + [Text.Encoding]::UTF8.GetByteCount($js)
    }
    $lines | Out-File (Join-Path $AppDir 'logs\selftest.txt') -Encoding UTF8
    foreach ($id in $script:SkinApps.Keys) {
        if (-not (Select-SkinApplication $id)) { throw 'Profile selection failed' }
        foreach ($lang in $script:LangCodes) { Set-Lang $lang }
    }
    Select-SkinApplication 'codex' | Out-Null
    $readabilityBox.IsChecked = $false
    $readabilityBox.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if ($Cfg.readability -or $readabilityBox.Visibility -ne 'Visible') { throw 'Readability toggle failed' }
    $readabilityBox.IsChecked = $true
    $readabilityBox.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if (-not $Cfg.readability) { throw 'Readability toggle failed to re-enable' }
    $appBox.SelectedIndex = [array]::IndexOf(@($script:SkinApps.Keys), 'opencode')
    if ($Settings.activeApp -ne 'opencode' -or $readabilityBox.Visibility -ne 'Visible' -or $appBox.Items.Count -ne $script:SkinApps.Count) { throw 'OpenCode application option missing' }
    $readabilityBox.IsChecked = $false
    $readabilityBox.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if ($Cfg.readability -or -not $Settings.apps.codex.readability) { throw 'OpenCode readability profile is not isolated' }
    $readabilityBox.IsChecked = $true
    $readabilityBox.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if ($readabilityBox.Visibility -ne 'Visible') { throw 'OpenCode readability option missing' }
    $syncAppearanceBox.IsChecked = $false
    $syncAppearanceBox.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if ($Cfg.syncAppearance) { throw 'Appearance sync option failed to disable' }
    $syncAppearanceBox.IsChecked = $true
    $syncAppearanceBox.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if (-not $Cfg.syncAppearance) { throw 'Appearance sync option failed to enable' }
    Select-SkinApplication 'workbuddy' | Out-Null
    if ($Settings.activeApp -ne 'workbuddy' -or $readabilityBox.Visibility -ne 'Visible') { throw 'WorkBuddy application option missing' }
    Test-SkinVisualEditor
    Test-ThemeBrowser
    Test-SkinStatusUi
    Test-SkinCompatibilityUi
    Test-SkinManagerThemeUi
    Set-Lang 'zh-CN'
    $window.Content.Measure([Windows.Size]::new(760,660))
    $window.Content.Arrange([Windows.Rect]::new(0,0,760,660))
    $window.Content.UpdateLayout()
    $diagnostics = @('list=' + $themeList.ActualWidth + 'x' + $themeList.ActualHeight)
    $walk = New-Object Collections.Queue; $walk.Enqueue($themeList)
    while ($walk.Count) {
        $node = $walk.Dequeue()
        if ($node -is [Windows.Controls.WrapPanel] -or $node -is [Windows.Controls.ListBoxItem]) { $diagnostics += $node.GetType().Name + ': actual=' + $node.ActualWidth + 'x' + $node.ActualHeight + ' desired=' + $node.DesiredSize + ' min=' + $node.MinWidth + ' alignment=' + $node.HorizontalAlignment }
        if ($node -is [Windows.Media.Visual]) { for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$i++) { $walk.Enqueue([Windows.Media.VisualTreeHelper]::GetChild($node,$i)) } }
    }
    $diagnostics += @($script:LocalCards | ForEach-Object { $_.Id + ': card=' + $_.CardWidth + ' thumb=' + $_.Thumbnail.PixelWidth + 'x' + $_.Thumbnail.PixelHeight })
    $diagnostics | Out-File (Join-Path $AppDir 'logs\cards-layout.txt') -Encoding UTF8
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(760,660,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window.Content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create((Join-Path $AppDir 'logs\selftest-ui.png'))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    $notify.Dispose(); $script:Mutex.ReleaseMutex()
    exit 0
}

# marquee: cached text first, then refresh from weiyun share
try { if (Test-Path $script:AnnCachePath) { $c = [IO.File]::ReadAllText($script:AnnCachePath, [Text.Encoding]::UTF8); if ($c.Trim()) { $marqueeText.Text = $c.Trim() } } } catch { }
if (-not $marqueeText.Text) { $marqueeText.Text = $L.annDefault }
$script:mqTf = New-Object System.Windows.Media.TranslateTransform
$marqueeText.RenderTransform = $script:mqTf
$mqTimer = New-Object System.Windows.Threading.DispatcherTimer
$mqTimer.Interval = [TimeSpan]::FromMilliseconds(30)
$mqTimer.Add_Tick({
    try {
        $w = $marqueeCanvas.ActualWidth; $tw = $marqueeText.ActualWidth
        if ($w -lt 2 -or $tw -lt 2) { return }
        $nx = $script:mqTf.X - 2
        if ($nx -lt (-$tw)) { $nx = $w + 10 }
        $script:mqTf.X = $nx
    } catch { }
})
$mqTimer.Start()
Start-BackgroundJob $annWork $null $annDone
Start-BackgroundJob $updWork @{ ApiUrl = $script:UpdateApiUrl } $updDone
$updTimer = New-Object System.Windows.Threading.DispatcherTimer
$updTimer.Interval = [TimeSpan]::FromMinutes(30)
$updTimer.Add_Tick({ Start-BackgroundJob $updWork @{ ApiUrl = $script:UpdateApiUrl } $updDone })
$updTimer.Start()
$annTimer = New-Object System.Windows.Threading.DispatcherTimer
$annTimer.Interval = [TimeSpan]::FromMinutes(30)
$annTimer.Add_Tick({ Start-BackgroundJob $annWork $null $annDone })
$annTimer.Start()
# extract appearance icons (sun=light / moon=dark) for the gallery list
Refresh-ThemeList
Start-GalleryLoad 2
Update-UiState $L.ready
$State.Watch = @()
if (-not [System.Windows.Application]::Current) { [void](New-Object System.Windows.Application) }
$window.Show()
Start-SkinHealthScan -Discover
# void Run()：否则其返回值（退出码 0）会成为脚本输出，ps2exe -noConsole 会在退出时把它弹成内容为“0”的对话框
[void]([System.Windows.Application]::Current.Run($window))
[System.Windows.Forms.MessageBox]::Show($L.exitMsg, $L.winTitle) | Out-Null

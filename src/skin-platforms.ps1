# Application adapters and versioned configuration. Windows PowerShell 5.1.
$script:SkinRuntimeRevision = '2.6.0'
$script:SkinPlatformsDir = $PSScriptRoot
. (Join-Path $PSScriptRoot 'skin-opencode.ps1')
. (Join-Path $PSScriptRoot 'skin-workbuddy.ps1')
. (Join-Path $PSScriptRoot 'skin-visuals.ps1')

function Test-SkinAppearanceSync {
    param($Options)
    if ($null -ne $Options -and $null -ne $Options.syncAppearance) { return [bool]$Options.syncAppearance }
    return $true
}

function Test-SkinReadability {
    param($Options)
    if ($null -ne $Options -and $null -ne $Options.readability) { return [bool]$Options.readability }
    return $true
}

function Get-SkinAdapterRevision {
    param([string]$Application)
    if ($Application -eq 'workbuddy') { return '2.8.5' }
    if ($Application -eq 'zcode') { return '2.8.7' }
    return $script:SkinRuntimeRevision
}

function Get-SkinMarker {
    param($ThemePack, $Options, [string]$Application)
    $marker = [string]$ThemePack.Meta.id + '@' + [string]$ThemePack.Meta.version + '#' + (Get-SkinAdapterRevision $Application) + ':r' + [int](Test-SkinReadability $Options) + ':a' + [int](Test-SkinAppearanceSync $Options)
    $visual = Get-SkinVisualAdjustment $Options ([string]$ThemePack.Meta.id)
    if ($visual) { $marker += ':v' + $visual.panelOpacity + '-' + $visual.blur + '-' + $visual.position }
    return $marker
}
$script:SkinApps = [ordered]@{
    zcode = @{ Id = 'zcode'; Name = 'ZCode'; Exe = 'ZCode.exe'; Port = 9223; Engine = 'electron' }
    monkeycode = @{ Id = 'monkeycode'; Name = 'MonkeyCode'; Exe = 'monkeycode-desktop.exe'; Port = 9224; Engine = 'webview2' }
    codex = @{ Id = 'codex'; Name = 'Codex'; Exe = 'ChatGPT.exe'; Port = 9335; Engine = 'electron' }
    opencode = @{ Id = 'opencode'; Name = 'OpenCode'; Exe = 'OpenCode.exe'; Port = 9336; Engine = 'electron' }
    workbuddy = @{ Id = 'workbuddy'; Name = 'WorkBuddy'; Exe = 'WorkBuddy.exe'; Port = 9337; Engine = 'electron' }
}

function Get-SkinApp {
    param([ValidateSet('zcode','monkeycode','codex','opencode','workbuddy')][string]$Application = 'zcode')
    return $script:SkinApps[$Application]
}

function Read-SkinSettings {
    param([string]$Path)
    $settings = @{ schemaVersion = 4; activeApp = 'zcode'; lang = ''; apps = @{}; favorites = @(); managerTheme = 'pearl' }
    foreach ($id in $script:SkinApps.Keys) {
        $settings.apps[$id] = @{ appExe = ''; currentTheme = ''; port = $script:SkinApps[$id].Port; readability = $true; syncAppearance = $true; themeAdjustments = @{}; activeVisual = $null }
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $settings }
    $old = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($old.schemaVersion -and [int]$old.schemaVersion -gt 4) { throw 'This configuration was written by a newer SkinStudio.' }
    $settings.lang = [string]$old.lang
    if ([string]$old.managerTheme -in @('system','pearl','midnight','iris','pine')) { $settings.managerTheme = [string]$old.managerTheme }
    $settings.favorites = @($old.favorites | Where-Object { $_ -is [string] -and $_ -match '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$' } | Select-Object -Unique)
    if ($old.apps) {
        if ($script:SkinApps.Contains([string]$old.activeApp)) { $settings.activeApp = [string]$old.activeApp }
        foreach ($id in $script:SkinApps.Keys) {
            $entry = $old.apps.$id
            if (-not $entry) { continue }
            $settings.apps[$id].appExe = [string]$entry.appExe
            $settings.apps[$id].currentTheme = [string]$entry.currentTheme
            if ($null -ne $entry.readability) { $settings.apps[$id].readability = [bool]$entry.readability }
            if ($null -ne $entry.syncAppearance) { $settings.apps[$id].syncAppearance = [bool]$entry.syncAppearance }
            if ($entry.port) { $settings.apps[$id].port = [int]$entry.port }
            if ($entry.themeAdjustments) {
                foreach ($saved in $entry.themeAdjustments.PSObject.Properties) {
                    $visual = ConvertTo-SkinVisual $saved.Value
                    if ($saved.Name -match '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$' -and $visual) { $settings.apps[$id].themeAdjustments[$saved.Name] = $visual }
                }
            }
            if ($entry.activeVisual -and $entry.activeVisual.themeId -eq $entry.currentTheme) {
                $visual = ConvertTo-SkinVisual $entry.activeVisual
                if ($visual) { $visual.themeId = [string]$entry.currentTheme; $settings.apps[$id].activeVisual = $visual }
            }
        }
    } else {
        # Old ZCode config becomes the ZCode profile; other apps start clean.
        $settings.apps.zcode.appExe = [string]$old.appExe
        $settings.apps.zcode.currentTheme = [string]$old.currentTheme
        if ($old.port) { $settings.apps.zcode.port = [int]$old.port }
    }
    $used = @{}
    foreach ($id in $script:SkinApps.Keys) {
        $port = [int]$settings.apps[$id].port
        if ($port -lt 1024 -or $port -gt 65535 -or $used.ContainsKey($port)) {
            $port = $script:SkinApps[$id].Port
            while ($used.ContainsKey($port)) { $port++ }
        }
        $settings.apps[$id].port = $port
        $used[$port] = $true
        $theme = $settings.apps[$id].currentTheme
        if ($theme -and $theme -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { $settings.apps[$id].currentTheme = '' }
    }
    return $settings
}

function Write-SkinSettings {
    param([string]$Path, $Settings)
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, ($Settings | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Test-SkinDesktopExe {
    param([string]$Application, [string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $app = Get-SkinApp $Application
    if ([IO.Path]::GetFileName($Path) -ine $app.Exe) { return $false }
    if ($Application -eq 'codex') {
        # Codex CLI codex.exe must never be treated as the desktop application.
        return $Path -match '(?i)OpenAI[\\.]Codex' -and [bool](Test-Path -LiteralPath (Join-Path (Split-Path $Path) 'resources\app.asar') -PathType Leaf)
    }
    if ($Application -in @('opencode','workbuddy')) {
        # The terminal CLI has a similar filename but no Electron resources.
        return [bool](Test-Path -LiteralPath (Join-Path (Split-Path $Path) 'resources\app.asar') -PathType Leaf)
    }
    return $true
}

function Resolve-SkinAppExe {
    param([string]$Application = 'zcode', [string]$Configured)
    if (Test-SkinDesktopExe $Application $Configured) { return $Configured }
    $app = Get-SkinApp $Application
    $running = Get-Process ([IO.Path]::GetFileNameWithoutExtension($app.Exe)) -ErrorAction SilentlyContinue
    foreach ($p in $running) {
        if ($Application -eq 'codex' -and $p.Path -notmatch 'OpenAI[\\.]Codex') { continue }
        if (Test-SkinDesktopExe $Application $p.Path) { return $p.Path }
    }
    if ($Application -eq 'zcode') { return Resolve-ZcodeExe '' }
    if ($Application -eq 'codex') {
        foreach ($pkg in @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
            $candidate = Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'
            if (Test-SkinDesktopExe $Application $candidate) { return $candidate }
        }
    }
    $roots = @("$env:LOCALAPPDATA\Programs\@opencodedesktop", "$env:LOCALAPPDATA\Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)}, 'D:\MonkeyCode', 'D:\PCSoftware\MonkeyCode', 'D:\PCSoftware\WorkBuddy', "$env:LOCALAPPDATA\Programs\WorkBuddy", 'C:\MonkeyCode')
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($row in @(Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like ('*' + $app.Name + '*') })) {
            if ($row.InstallLocation) { $roots += ([string]$row.InstallLocation).Trim('"') }
            if ($row.DisplayIcon) { $roots += Split-Path (([string]$row.DisplayIcon).Trim('"') -replace ',\d+$','') }
        }
    }
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter $app.Exe -Recurse -Depth 3 -ErrorAction SilentlyContinue)) {
            if (Test-SkinDesktopExe $Application $file.FullName) { return $file.FullName }
        }
    }
    return $null
}

function Get-SkinAppProcesses {
    param([string]$AppExe)
    return @(Get-Process ([IO.Path]::GetFileNameWithoutExtension($AppExe)) -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq $AppExe })
}

function Test-SkinAppAccessDenied {
    param([string]$Application, [string]$AppExe)
    if ($Application -ne 'workbuddy' -or @(Get-SkinAppProcesses $AppExe).Count) { return $false }
    return [bool]@(Get-Process WorkBuddy -ErrorAction SilentlyContinue | Where-Object { -not $_.Path }).Count
}

function Stop-SkinApp {
    param([string]$Application, [string]$AppExe)
    if (Test-SkinAppAccessDenied $Application $AppExe) { throw 'WorkBuddy process access denied. Run both applications at the same privilege level.' }
    $procs = @(Get-SkinAppProcesses $AppExe)
    foreach ($p in $procs) { [void]$p.CloseMainWindow() }
    if ($procs.Count) { $procs | Wait-Process -Timeout 4 -ErrorAction SilentlyContinue }
    Get-SkinAppProcesses $AppExe | Stop-Process -Force -ErrorAction Stop
    # WebView2 child processes may retain the single-instance profile lock.
    if ($Application -eq 'monkeycode') {
        Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match '(?i)[\\/]monkeycode[^\\/]*[\\/]' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    if ($procs.Count) { Start-Sleep -Milliseconds 700 }
}

function New-SkinAppStartInfo {
    param([string]$Application, [string]$AppExe, [int]$Port, [switch]$Official)
    if (-not (Test-SkinDesktopExe $Application $AppExe)) { throw "Invalid $Application desktop executable: $AppExe" }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AppExe
    $info.WorkingDirectory = Split-Path $AppExe
    $info.UseShellExecute = $false
    $info.EnvironmentVariables.Remove('WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS')
    $info.EnvironmentVariables.Remove('ELECTRON_RUN_AS_NODE')
    $info.EnvironmentVariables.Remove('WORKBUDDY_REMOTE_DEBUGGING_PORT')
    if (-not $Official) {
        if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Invalid debugging port' }
        $flags = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=$Port"
        if ($Application -eq 'monkeycode') { $info.EnvironmentVariables['WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'] = $flags }
        else { $info.Arguments = $flags }
        if ($Application -eq 'workbuddy') { $info.EnvironmentVariables['WORKBUDDY_REMOTE_DEBUGGING_PORT'] = [string]$Port }
    }
    return $info
}

function Start-SkinApp {
    param([string]$Application, [string]$AppExe, [int]$Port, [switch]$Official)
    if (Test-SkinAppAccessDenied $Application $AppExe) { throw 'WorkBuddy process access denied. Run both applications at the same privilege level.' }
    $info = New-SkinAppStartInfo $Application $AppExe $Port -Official:$Official
    $proc = [Diagnostics.Process]::Start($info)
    try { return $proc.Id } finally { $proc.Dispose() }
}

function Get-SkinPortListeners {
    param([int]$Port)
    return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Test-SkinCdpOwner {
    param([string]$Application, [string]$AppExe, [int]$Port)
    $listeners = @(Get-SkinPortListeners $Port)
    if (-not $listeners.Count) { return $false }
    foreach ($listener in $listeners) {
        if ($listener.LocalAddress -notin @('127.0.0.1','::1')) { return $false }
        $ownerId = [int]$listener.OwningProcess
        $owned = $false
        for ($depth = 0; $depth -lt 8 -and $ownerId -gt 0; $depth++) {
            $proc = Get-Process -Id $ownerId -ErrorAction SilentlyContinue
            if ($proc -and $proc.Path -ieq $AppExe) { $owned = $true; break }
            if ($Application -ne 'monkeycode') { break }
            $row = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId" -ErrorAction SilentlyContinue
            if (-not $row) { break }
            $ownerId = [int]$row.ParentProcessId
        }
        if (-not $owned) { return $false }
    }
    return $true
}

function Get-SkinTargets {
    param([string]$Application, [string]$AppExe, [int]$Port)
    if (-not (Test-SkinCdpOwner $Application $AppExe $Port)) { return @() }
    $targets = @(Get-CdpPageTargets -Port $Port)
    return @($targets | Where-Object {
        $t = $_; $uri = $null
        $validWs = [Uri]::TryCreate([string]$t.webSocketDebuggerUrl, [UriKind]::Absolute, [ref]$uri) -and
            $uri.Scheme -eq 'ws' -and $uri.Host -in @('127.0.0.1','localhost','[::1]','::1') -and $uri.Port -eq $Port -and
            $uri.AbsolutePath -eq ('/devtools/page/' + $t.id) -and -not $uri.UserInfo
        $validUrl = switch ($Application) {
            'zcode' { $t.url -match '^file:///.*(?:app\.asar/)?out/renderer/index\.html(?:[?#].*)?$' }
            'workbuddy' {
                $renderer = $t.url -match '^file:///.*[\/]resources/app\.asar(?:\.unpacked)?/renderer/index\.html(?:[?#].*)?$'
                $decoded = [Uri]::UnescapeDataString([string]$t.url)
                if ($decoded -match '[?&]windowKind=([^&#]+)') { $renderer = $renderer -and $Matches[1] -eq 'settings' }
                $renderer
            }
            'monkeycode' { $t.url -match '^(?:https?://tauri\.localhost|tauri://localhost)/(?:index\.html)?(?:[?#].*)?$' }
            # The packaged Electron renderer also uses history-based SPA routes.
            'opencode' { $t.url -match '^oc://renderer/(?!assets/)[^?#]*(?:[?#].*)?$' }
            'codex' {
                $t.url -match '^app://[^/]+/(?:index\.html)?(?:[?#].*)?$' -and
                [Uri]::UnescapeDataString([string]$t.url) -notmatch '(?i)(?:initialRoute=|[?#])/avatar-overlay(?:[&#/?]|$)'
            }
        }
        $validWs -and $validUrl
    })
}

function Get-SkinPalette {
    param($ThemePack)
    $colors = @{}
    $mapping = @{ background = @('color-background','color-base-300'); panel = @('color-panel','color-base-100'); panelAlt = @('color-background-win-alt','color-base-200'); accent = @('color-primary'); accentAlt = @('color-accent'); text = @('color-foreground','color-text','color-base-content'); line = @('color-border','color-neutral'); secondary = @('color-secondary'); highlight = @('color-info') }
    foreach ($key in $mapping.Keys) {
        $value = if ($ThemePack.Meta.colors) { [string]$ThemePack.Meta.colors.$key } else { '' }
        if ($value -match '^#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])?$') {
            $value = '#' + $Matches[1] + $Matches[1] + $Matches[2] + $Matches[2] + $Matches[3] + $Matches[3]
        }
        if ($value -notmatch '^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$') {
            foreach ($variable in $mapping[$key]) {
                $value = Get-ZcodePackSurfaceColor -Css $ThemePack.Css -VarName $variable
                if ($value) { break }
            }
        }
        if ($value -match '^#[0-9a-fA-F]{6}') { $colors[$key] = $value.Substring(0,7) }
    }
    return $colors
}

function New-SkinBaseStyleBootstrapJs {
    param([string]$Application = 'zcode', $ThemePack, $Options)
    $marker = (Get-SkinMarker $ThemePack $Options $Application) | ConvertTo-Json -Compress
    if ($Application -eq 'workbuddy') { return New-WorkBuddyStyleBootstrapJs $ThemePack $Options }
    if ($Application -eq 'opencode') { return New-OpenCodeStyleBootstrapJs $ThemePack $Options }
    if ($Application -eq 'zcode') {
        $adapted = @{} + $ThemePack
        if ($ThemePack.Css -match 'data-mc-background|\.mc-workbench-background') {
            $adapted.Css = New-ZcodeCssFromCodexColors -Colors ([pscustomobject](Get-SkinPalette $ThemePack))
        }
        $readCss = ''
        $mode = if (Test-SkinReadability $Options) { 'on' } else { 'off' }
        if (Test-SkinReadability $Options) {
            $readCss = @'
html.theme-zai-light[data-zc-skin="active"][data-skin-readable="on"]{
 --zc-readable-ink:#17212d;--zc-readable-panel:#f8fafc;--zc-readable-bg:#f1f5f9;--zc-readable-halo:#ffffff99;--zc-readable-opacity:56%;--zc-glass-opacity:64%;--zc-composer-opacity:68%;--zc-composer-blur:6px;--zc-glass-shadow:#17212d0d;
 --color-popover:#f8fafc !important;--color-popover-header:#eef2f6 !important;--color-popover-border:#cbd2dd !important;
}
html.theme-zai-dark[data-zc-skin="active"][data-skin-readable="on"]{
 --zc-readable-ink:#eef1f6;--zc-readable-panel:#202630;--zc-readable-bg:#171d26;--zc-readable-halo:#00000099;--zc-readable-opacity:68%;--zc-glass-opacity:70%;--zc-composer-opacity:58%;--zc-composer-blur:6px;--zc-glass-shadow:#00000026;
 --color-popover:#202630 !important;--color-popover-header:#252c38 !important;--color-popover-border:#465062 !important;
}
html[data-zc-skin="active"][data-skin-readable="on"]{
 --color-foreground:var(--zc-readable-ink) !important;
 --color-popover-foreground:var(--zc-readable-ink) !important;
 --color-foreground-subtle:color-mix(in srgb,var(--zc-readable-ink) 86%,transparent) !important;
 --color-foreground-subtlest:color-mix(in srgb,var(--zc-readable-ink) 74%,transparent) !important;
 --color-background:color-mix(in srgb,var(--zc-readable-bg) var(--zc-readable-opacity),transparent) !important;
 --color-sidebar:color-mix(in srgb,var(--zc-readable-bg) var(--zc-readable-opacity),transparent) !important;
 --color-background-win-alt:color-mix(in srgb,var(--zc-readable-panel) var(--zc-readable-opacity),transparent) !important;
 --color-panel:color-mix(in srgb,var(--zc-readable-panel) var(--zc-readable-opacity),transparent) !important;
 --color-header:color-mix(in srgb,var(--zc-readable-panel) var(--zc-readable-opacity),transparent) !important;
 --zc-glass-line:color-mix(in srgb,var(--zc-readable-ink) 12%,transparent);
 --color-hover:color-mix(in srgb,var(--zc-readable-ink) 8%,transparent) !important;
 --color-selected:color-mix(in srgb,var(--zc-readable-ink) 12%,transparent) !important;
}
/* Each workspace pane paints one surface; the full-window frame stays clear.
   Stacking two 60% surfaces hid 84% of the wallpaper before its extra tint. */
html[data-zc-skin="active"][data-skin-readable="on"] [data-desktop-window-frame]:has([data-workspace-shell]){
 background-color:transparent !important;
}
html[data-zc-skin="active"][data-skin-readable="on"] [data-workspace-sidebar-panel]{
 background-color:color-mix(in srgb,var(--zc-readable-panel) var(--zc-glass-opacity),transparent) !important;
 backdrop-filter:blur(8px);
}
html[data-zc-skin="active"][data-skin-readable="on"] [data-workspace-conversation-frame]{
 background-color:color-mix(in srgb,var(--zc-readable-panel) var(--zc-readable-opacity),transparent) !important;
 border-color:var(--zc-glass-line) !important;border-radius:14px;
 box-shadow:0 2px 14px var(--zc-glass-shadow);
}
/* Keep a single glass card around both the project toolbar and the editor. */
html[data-zc-skin="active"][data-skin-readable="on"] :is(.chat-composer-input-surface,[data-composer-layout]){
 background-color:color-mix(in srgb,var(--zc-readable-panel) var(--zc-composer-opacity),transparent) !important;
 border:1px solid var(--zc-glass-line);border-radius:18px;
 backdrop-filter:blur(var(--zc-composer-blur));
}
html[data-zc-skin="active"][data-skin-readable="on"] .chat-composer-input-surface{
 box-shadow:0 6px 24px var(--zc-glass-shadow);
}
html[data-zc-skin="active"][data-skin-readable="on"] .chat-composer-input-surface [data-composer-layout]{
 background-color:transparent !important;border-color:transparent !important;box-shadow:none;backdrop-filter:none;
}
html[data-zc-skin="active"][data-skin-readable="on"] .chat-composer-input-surface:focus-within{
 border-color:color-mix(in srgb,var(--zc-readable-ink) 28%,transparent);
}
html[data-zc-skin="active"][data-skin-readable="on"] [data-testid="chat-error-banner"]{
 background-color:color-mix(in srgb,var(--zc-readable-panel) 82%,transparent) !important;
 border-color:var(--zc-glass-line) !important;backdrop-filter:blur(8px);
}
html[data-zc-skin="active"][data-skin-readable="on"] [data-testid="chat-empty"] .pointer-events-none:has(>svg[aria-hidden="true"]){
 opacity:.18;
}
html[data-zc-skin="active"][data-skin-readable="on"] :is([role="menu"],[role="dialog"],[data-slot="dropdown-menu-content"],[data-slot="dropdown-menu-sub-content"],[data-slot="context-menu-content"],[data-slot="popover-content"],[data-slot="tooltip-content"]){
 background-color:var(--color-popover) !important;color:var(--color-popover-foreground) !important;
}
html[data-zc-skin="active"][data-skin-readable="on"] button[data-variant="ghost"]:not(:disabled):not([aria-disabled="true"]) svg{
 filter:drop-shadow(0 0 1px var(--zc-readable-halo));
}
'@
        }
        $tuning = if (Test-SkinReadability $Options) { @{ SurfaceOpacity = 0.5; WallpaperTint = 0 } } else { $null }
        $js = New-ZcodeSkinBootstrapJs -ThemePack $adapted -ReadabilityCss $readCss -Tuning $tuning
        # Legacy bootstrap swallows errors; verify the installed style before success.
        return "document.documentElement.setAttribute('data-skin-readable','$mode');`n" + $js + "`n;(()=>{if(!document.getElementById('zc-skin-style'))throw Error('ZCode skin failed');window.__SKIN_STUDIO=$marker;return window.__SKIN_STUDIO})()"
    }
    $meta = $ThemePack.Meta
    $palette = Get-SkinPalette $ThemePack
    $css = New-Object Text.StringBuilder
    $scope = 'html[data-skin-studio="' + $Application + '"]'
    [void]$css.AppendLine($scope + '{')
    $pairs = if ($Application -eq 'monkeycode') {
        @{ background = @('--color-base-300'); panel = @('--color-base-100'); panelAlt = @('--color-base-200'); accent = @('--color-primary'); accentAlt = @('--color-accent'); text = @('--color-base-content'); line = @('--color-neutral') }
    } else { @{} }
    foreach ($key in $pairs.Keys) {
        foreach ($variable in $pairs[$key]) {
            if ($palette[$key]) { [void]$css.AppendLine($variable + ':' + $palette[$key] + ' !important;') }
        }
    }
    if ($Application -eq 'monkeycode') {
        [void]$css.AppendLine('--mc-surface-opacity:50% !important;--mc-background-blur:0px !important;')
    }
    [void]$css.AppendLine('}')
    if ($Application -eq 'monkeycode' -and $ThemePack.Css -match 'data-mc-background|\.mc-workbench-background') {
        [void]$css.AppendLine($ThemePack.Css)
    }
    $bg = ''
    if ($ThemePack.BgPath) {
        $mime = @{ '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.png'='image/png'; '.webp'='image/webp' }[[IO.Path]::GetExtension($ThemePack.BgPath).ToLowerInvariant()]
        $bg = 'data:' + $mime + ';base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($ThemePack.BgPath))
    }
    $position = [string]$meta.position
    if ($position -notmatch '^(center|top|bottom|left|right|\d{1,3}% \d{1,3}%)$') { $position = 'center' }
    $fit = if ($meta.fit -eq 'contain') { 'contain' } else { 'cover' }
    if ($bg) {
        $paint = 'background-image:linear-gradient(#00000040,#00000040),url("' + $bg + '") !important;background-size:' + $fit + ' !important;background-position:' + $position + ' !important;background-repeat:no-repeat !important;'
        if ($Application -eq 'monkeycode') {
            [void]$css.AppendLine($scope + ' .mc-workbench-background{' + $paint + '}')
        } else {
            # Modern Codex uses --color-surface on the main shell, independently
            # of the legacy --bg-primary variables. Keep native text/overlay tokens
            # and only make the shell and composer surfaces translucent.
            [void]$css.AppendLine($scope + '{--ss-panel:var(--color-surface,#ffffff);--ss-panel-alt:var(--color-surface-secondary,#f6f6f6);}')
            $paletteScope = if ($meta.appearance -in @('light','dark')) { $scope + '[data-theme="' + $meta.appearance + '"]' } else { $scope }
            [void]$css.AppendLine($paletteScope + '{')
            if ($palette.panel) { [void]$css.AppendLine('--ss-panel:' + $palette.panel + ';') }
            if ($palette.panelAlt) { [void]$css.AppendLine('--ss-panel-alt:' + $palette.panelAlt + ';') }
            if ($palette.text) { [void]$css.AppendLine('--color-text:' + $palette.text + ' !important;--color-text-primary:' + $palette.text + ' !important;--color-token-text-primary:' + $palette.text + ' !important;') }
            if ($palette.accent) { [void]$css.AppendLine('--text-accent:' + $palette.accent + ' !important;') }
            [void]$css.AppendLine('}')
            # No var() anywhere in this declaration: Chromium applies its
            # substitution size limit to the entire value, including a data URI.
            $paint = 'background-image:url("' + $bg + '") !important;background-size:' + $fit + ' !important;background-position:' + $position + ' !important;background-repeat:no-repeat !important;'
            [void]$css.AppendLine($scope + ' body{' + $paint + 'background-attachment:fixed !important;}')
            [void]$css.AppendLine($scope + ' #root{background:transparent !important;min-height:100vh;}')
            # With the application menu bar visible, Codex reserves an extra
            # titlebar inset above all page surfaces. Close the exposed strip.
            [void]$css.AppendLine($scope + ' [data-app-shell-application-menu-bar="true"][data-app-shell-page-surface="true"]{--app-shell-titlebar-height:0px !important;}')
            [void]$css.AppendLine($scope + '{--bg-primary:transparent !important;--bg-secondary:color-mix(in srgb,var(--ss-panel) 70%,transparent) !important;--color-token-bg-primary:transparent !important;--color-token-bg-secondary:color-mix(in srgb,var(--ss-panel) 70%,transparent) !important;--color-token-bg-tertiary:color-mix(in srgb,var(--ss-panel-alt) 80%,transparent) !important;}')
            [void]$css.AppendLine($scope + ' [data-app-shell-main-surface]{background-color:color-mix(in srgb,var(--ss-panel) 50%,transparent) !important;}')
            [void]$css.AppendLine($scope + ' [data-composer-surface-variant="default"]{background-color:color-mix(in srgb,var(--ss-panel) 88%,transparent) !important;backdrop-filter:blur(8px);}')
            # The footer has a separate, aria-hidden surface with a fade mask.
            # Clear only that decorative layer; keep the composer and buttons.
            [void]$css.AppendLine($scope + ' [data-thread-scroll-footer]{background-color:transparent !important;}')
            [void]$css.AppendLine($scope + ' [data-thread-scroll-footer] > div[aria-hidden="true"][class*="_background_"]{background:transparent !important;}')
            [void]$css.AppendLine($scope + ' .thread-scroll-container div[aria-hidden="true"][class*="_background_"][class*="_fade_"]{background:transparent !important;}')
        }
    }
    if ($Application -eq 'monkeycode' -and (Test-SkinReadability $Options)) {
        # Real work-page review found low-contrast highlighted comments over wallpaper.
        $safe=$scope+'[data-skin-readable="on"]'
        [void]$css.AppendLine($safe+'{--ss-mc-code-bg:#f8fafc;--ss-mc-code-ink:#203d4a;}')
        [void]$css.AppendLine($safe+'.dark,'+$safe+'[data-theme*="dark"]{--ss-mc-code-bg:#1c232b;--ss-mc-code-ink:#eef2f7;}')
        [void]$css.AppendLine($safe+' pre{background-color:var(--color-base-100,var(--ss-mc-code-bg)) !important;color:var(--color-base-content,var(--ss-mc-code-ink)) !important;}')
        [void]$css.AppendLine($safe+' pre code{color:inherit !important;}')
        [void]$css.AppendLine($safe+' pre :is(.hljs-comment,.hljs-quote,.token.comment){color:color-mix(in srgb,var(--color-base-content,var(--ss-mc-code-ink)) 82%,var(--color-base-100,var(--ss-mc-code-bg))) !important;opacity:1 !important;}')
    }
    if ($Application -eq 'codex' -and (Test-SkinReadability $Options)) {
        # Protect controls with one shared glass surface, without button tiles.
        $safe = $scope + '[data-skin-readable="on"]'
        [void]$css.AppendLine($safe + '{--ss-panel:#f8fafc;--ss-safe-ink:#17212d;--ss-safe-panel:#f8fafc;--ss-content-opacity:56%;--ss-glass-opacity:64%;--ss-ink-halo:#ffffffb3;}')
        [void]$css.AppendLine($safe + '[data-theme="dark"]{--ss-panel:#171e29;--ss-safe-ink:#f3f4f6;--ss-safe-panel:#171e29;--ss-content-opacity:64%;--ss-glass-opacity:70%;--ss-ink-halo:#00000099;}')
        [void]$css.AppendLine($safe + '{--color-text:var(--ss-safe-ink) !important;--color-text-primary:var(--ss-safe-ink) !important;--color-text-secondary:color-mix(in srgb,var(--ss-safe-ink) 88%,transparent) !important;--color-text-tertiary:color-mix(in srgb,var(--ss-safe-ink) 82%,transparent) !important;--color-token-text-primary:var(--ss-safe-ink) !important;--color-token-text-secondary:color-mix(in srgb,var(--ss-safe-ink) 88%,transparent) !important;}')
        [void]$css.AppendLine($safe + ' [data-app-shell-main-surface]{background-color:color-mix(in srgb,var(--ss-panel) var(--ss-content-opacity),transparent) !important;}')
        [void]$css.AppendLine($safe + ' :is([class*="_ApplicationMenuTopBar_"],nav[class~="group/sidebar-rail"]){background-color:color-mix(in srgb,var(--ss-safe-panel) var(--ss-glass-opacity),transparent) !important;backdrop-filter:blur(8px);}')
        $control = $safe + ' button[class*="_Button_"]:has(svg):not(:disabled):not([aria-disabled="true"]):not([class*="text-danger"]):not([class*="bg-danger"])'
        [void]$css.AppendLine($control + '{color:var(--ss-safe-ink) !important;--button-text-color:var(--ss-safe-ink) !important;background-color:transparent !important;box-shadow:none !important;text-shadow:0 1px 1px var(--ss-ink-halo);}')
        [void]$css.AppendLine($control + ' svg{filter:drop-shadow(0 0 1px var(--ss-ink-halo));}')
        [void]$css.AppendLine($control + ':hover{background-color:color-mix(in srgb,var(--ss-safe-panel) 38%,transparent) !important;}')
        [void]$css.AppendLine($control + ':is([data-selected],[aria-pressed="true"],[data-state="open"]){background-color:color-mix(in srgb,var(--ss-safe-ink) 12%,transparent) !important;}')
        [void]$css.AppendLine($control + ':focus-visible{outline:1px solid color-mix(in srgb,var(--ss-safe-ink) 65%,transparent) !important;outline-offset:2px;}')
    }
    # JSON serialization keeps quotes, non-ASCII IDs and newlines out of JS syntax.
    $cssJson = $css.ToString() | ConvertTo-Json -Compress
    $appJson = $Application | ConvertTo-Json -Compress
    $readabilityMode = if (Test-SkinReadability $Options) { 'on' } else { 'off' }
    return @"
(()=>{
 const root=document.documentElement;
 root.setAttribute('data-skin-studio',$appJson);
 root.setAttribute('data-skin-readable','$readabilityMode');
 if($appJson==='monkeycode')root.setAttribute('data-mc-background','active');
 let style=document.getElementById('skin-studio-style');
 if(!style){style=document.createElement('style');style.id='skin-studio-style';(document.head||root).appendChild(style);}
 style.textContent=$cssJson;
 window.__SKIN_STUDIO=$marker;
 return window.__SKIN_STUDIO;
})()
"@
}

function New-SkinBootstrapJs {
    param([string]$Application = 'zcode', $ThemePack, $Options)
    $style = New-SkinStyleBootstrapJs $Application $ThemePack $Options
    $appearance = ([string]$ThemePack.Meta.appearance).Trim().ToLowerInvariant()
    if (-not (Test-SkinAppearanceSync $Options) -or $appearance -notin @('light','dark')) {
        if ($Application -eq 'workbuddy') { return New-WorkBuddyReadyBootstrapJs $style }
        return $style
    }
    $helper = [IO.File]::ReadAllText((Join-Path $script:SkinPlatformsDir 'skin-appearance.js'), [Text.Encoding]::UTF8)
    $appJson = $Application | ConvertTo-Json -Compress
    $modeJson = $appearance | ConvertTo-Json -Compress
    $bootstrap = "(async()=>{`n" + $helper + "`nawait skinStudioSyncAppearance($appJson,$modeJson);`nreturn (function(){`n" + $style + "`nreturn window.__SKIN_STUDIO;})();`n})()"
    if ($Application -eq 'workbuddy') { return New-WorkBuddyReadyBootstrapJs ('await ' + $bootstrap + ';') }
    return $bootstrap
}

. (Join-Path $PSScriptRoot 'skin-operation.ps1')
. (Join-Path $PSScriptRoot 'skin-compatibility.ps1')

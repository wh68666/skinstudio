# Explicit, per-application/per-theme visual adjustments. PowerShell 5.1.
# Saved adjustments are never selected implicitly when applying a theme.
function ConvertTo-SkinVisual {
    param($Value)
    if ($null -eq $Value) { return $null }
    $opacity = 0; $blur = 0
    if (-not [int]::TryParse([string]$Value.panelOpacity, [ref]$opacity) -or $opacity -lt 0 -or $opacity -gt 100) { return $null }
    if (-not [int]::TryParse([string]$Value.blur, [ref]$blur) -or $blur -lt 0 -or $blur -gt 20) { return $null }
    $position = [string]$Value.position
    if ($position -notin @('theme','center','top','bottom','left','right','top-left','top-right','bottom-left','bottom-right')) { return $null }
    return @{ panelOpacity = $opacity; blur = $blur; position = $position }
}

function Get-SkinVisualPreset {
    param([ValidateSet('clear','glass','reading')][string]$Name)
    switch ($Name) {
        'clear' { return @{ panelOpacity = 56; blur = 0; position = 'theme' } }
        'glass' { return @{ panelOpacity = 64; blur = 6; position = 'theme' } }
        'reading' { return @{ panelOpacity = 88; blur = 0; position = 'theme' } }
    }
}

function Get-SkinVisualAdjustment {
    param($Options, [string]$ThemeId)
    if ($null -eq $Options) { return $null }
    if ($null -ne $Options.visual) { return ConvertTo-SkinVisual $Options.visual }
    if ($Options.activeVisual -and $Options.activeVisual.themeId -eq $ThemeId) { return ConvertTo-SkinVisual $Options.activeVisual }
    return $null
}

function Get-SkinThemeOptions {
    param($Profile, [string]$ThemeId, [switch]$Default)
    $options = @{ readability = (Test-SkinReadability $Profile); syncAppearance = (Test-SkinAppearanceSync $Profile); visual = $null }
    if (-not $Default) { $options.visual = Get-SkinVisualAdjustment $Profile $ThemeId }
    return $options
}

function New-SkinVisualCss {
    param([string]$Application, $Visual, $ThemePack, $Options)
    $op = [int]$Visual.panelOpacity; $blur = [int]$Visual.blur
    $scope = if ($Application -eq 'zcode') { 'html[data-zc-skin="active"][data-skin-readable][data-skin-visual="custom"]' } else { 'html[data-skin-studio="' + $Application + '"][data-skin-readable][data-skin-visual="custom"]' }
    $css = switch ($Application) {
        'workbuddy' { @'
__S__ body[data-skin-studio-workbuddy]{--ss-wb-content:__O__% !important;--ss-wb-glass:__O__% !important;--ss-wb-filter:blur(__B__px) !important;}
'@ }
        'opencode' { @'
__S__{--ss-oc-content:__O__% !important;--ss-oc-session-content:__O__% !important;--ss-oc-glass:__O__% !important;}
__S__ :is([data-component="new-session"],[data-slot="session-chat-panel"] > .bg-v2-background-bg-base,[data-slot="session-side-panel-content"] aside:not(aside aside),aside:not(aside aside),nav){backdrop-filter:blur(__B__px) !important;}
__S__ [data-slot="titlebar-v2"]::before{backdrop-filter:blur(__B__px) !important;}
'@ }
        'codex' { @'
__S__{--ss-content-opacity:__O__% !important;--ss-glass-opacity:__O__% !important;--color-token-bg-secondary:color-mix(in srgb,var(--ss-panel) __O__%,transparent) !important;--bg-secondary:color-mix(in srgb,var(--ss-panel) __O__%,transparent) !important;}
__S__ :is([data-app-shell-main-surface],[class*="_ApplicationMenuTopBar_"],nav[class~="group/sidebar-rail"]){background-color:color-mix(in srgb,var(--ss-panel) __O__%,transparent) !important;backdrop-filter:blur(__B__px) !important;}
'@ }
        'zcode' { @'
__S__{--ss-tune-panel:#f8fafc;--zc-readable-opacity:__O__% !important;--zc-glass-opacity:__O__% !important;}
__S__.theme-zai-dark{--ss-tune-panel:#202630;}
__S__{--color-background:color-mix(in srgb,var(--zc-readable-panel,var(--ss-tune-panel)) __O__%,transparent) !important;--color-sidebar:color-mix(in srgb,var(--zc-readable-panel,var(--ss-tune-panel)) __O__%,transparent) !important;--color-background-win-alt:color-mix(in srgb,var(--zc-readable-panel,var(--ss-tune-panel)) __O__%,transparent) !important;--color-panel:color-mix(in srgb,var(--zc-readable-panel,var(--ss-tune-panel)) __O__%,transparent) !important;--color-header:color-mix(in srgb,var(--zc-readable-panel,var(--ss-tune-panel)) __O__%,transparent) !important;}
__S__ :is([data-workspace-sidebar-panel],[data-workspace-conversation-frame]){background-color:color-mix(in srgb,var(--zc-readable-panel,var(--ss-tune-panel)) __O__%,transparent) !important;backdrop-filter:blur(__B__px) !important;}
__S__ [data-desktop-window-frame]:has([data-workspace-shell]){background-color:transparent !important;}
'@ }
        'monkeycode' { @'
__S__{--ss-tune-panel:#f8fafc;--mc-surface-opacity:__O__% !important;--mc-background-blur:__B__px !important;}
__S__:is([data-theme="dark"],[data-theme="mc-dark"]){--ss-tune-panel:#202630;}
__S__{--color-base-100:color-mix(in srgb,var(--ss-tune-panel) __O__%,transparent) !important;--color-base-200:color-mix(in srgb,var(--ss-tune-panel) __O__%,transparent) !important;--color-base-300:color-mix(in srgb,var(--ss-tune-panel) __O__%,transparent) !important;}
__S__ .mc-workbench-background{filter:blur(__B__px) !important;}
'@ }
    }
    $css = $css.Replace('__S__', $scope).Replace('__O__', [string]$op).Replace('__B__', [string]$blur).Replace('blur(0px)', 'none')
    if ($Application -eq 'monkeycode' -or ($Application -eq 'zcode' -and -not (Test-SkinReadability $Options))) {
        $palette = Get-SkinPalette $ThemePack
        if ($palette.panel) {
            $mode = [string]$ThemePack.Meta.appearance
            $matching = ''
            if ($mode -in @('light','dark')) {
                $matching = if ($Application -eq 'zcode') { '.theme-zai-' + $mode } else { ':is([data-theme="' + $mode + '"],[data-theme="mc-' + $mode + '"])' }
            }
            $css += "`n" + $scope + $matching + '{--ss-tune-panel:' + $palette.panel + ';}'
        }
    }
    if ($Visual.position -ne 'theme') {
        $position = ([string]$Visual.position).Replace('-', ' ')
        $wallpaper = switch ($Application) { 'zcode' { '#root' }; 'monkeycode' { '.mc-workbench-background' }; default { 'body' } }
        $css += "`n" + $scope + ' ' + $wallpaper + '{background-position:' + $position + ' !important;}'
        if ($Application -eq 'monkeycode') { $css += "`n" + $scope + '{--mc-background-position:' + $position + ' !important;}' }
    }
    return $css
}

function New-SkinStyleBootstrapJs {
    param([string]$Application = 'zcode', $ThemePack, $Options)
    $base = New-SkinBaseStyleBootstrapJs $Application $ThemePack $Options
    $visual = Get-SkinVisualAdjustment $Options ([string]$ThemePack.Meta.id)
    if (-not $visual) { return $base + "`n;document.documentElement.removeAttribute('data-skin-visual');window.__SKIN_STUDIO;" }
    $css = (New-SkinVisualCss $Application $visual $ThemePack $Options) | ConvertTo-Json -Compress
    $styleId = if ($Application -eq 'zcode') { 'zc-skin-style' } else { 'skin-studio-style' }
    return $base + "`n;(()=>{const s=document.getElementById('$styleId');if(!s)throw Error('Theme style missing');document.documentElement.setAttribute('data-skin-visual','custom');s.textContent+='\n'+$css;return window.__SKIN_STUDIO;})()"
}

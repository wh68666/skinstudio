# OpenCode Electron desktop (2.x): v2 UI tokens plus legacy theme tokens.
# No application files or terminal CLI settings are changed.
function New-OpenCodeStyleBootstrapJs {
    param($ThemePack, $Options)
    $scope = 'html[data-skin-studio="opencode"]'
    $palette = Get-SkinPalette $ThemePack
    $appearance = ([string]$ThemePack.Meta.appearance).Trim().ToLowerInvariant()
    $lightPanel = '#f8fafc'; $darkPanel = '#171e29'
    $lightInk = '#17212d'; $darkInk = '#f3f4f6'
    if (-not (Test-SkinReadability $Options)) {
        if ($appearance -ne 'dark') {
            if ($palette.panel) { $lightPanel = $palette.panel }
            if ($palette.text) { $lightInk = $palette.text }
        }
        if ($appearance -ne 'light') {
            if ($palette.panel) { $darkPanel = $palette.panel }
            if ($palette.text) { $darkInk = $palette.text }
        }
    }
    $css = New-Object Text.StringBuilder
    [void]$css.AppendLine($scope + '{--ss-oc-panel:' + $lightPanel + ';--ss-oc-ink:' + $lightInk + ';--ss-oc-content:56%;--ss-oc-session-content:64%;--ss-oc-glass:64%;--ss-oc-halo:#ffffff99;}')
    [void]$css.AppendLine($scope + '[data-color-scheme="dark"]{--ss-oc-panel:' + $darkPanel + ';--ss-oc-ink:' + $darkInk + ';--ss-oc-content:64%;--ss-oc-session-content:68%;--ss-oc-glass:70%;--ss-oc-halo:#00000099;}')
    $tokens = @'
__SCOPE__{
 --ss-oc-surface:color-mix(in srgb,var(--ss-oc-panel) var(--ss-oc-content),transparent);
 --ss-oc-card:color-mix(in srgb,var(--ss-oc-panel) 90%,transparent);
 --ss-oc-line:color-mix(in srgb,var(--ss-oc-ink) 12%,transparent);
 --background-base:transparent !important;
 --background-weak:var(--ss-oc-surface) !important;
 --background-strong:var(--ss-oc-card) !important;
 --background-stronger:var(--ss-oc-panel) !important;
 --surface-base:var(--ss-oc-surface) !important;
 --surface-raised-base:var(--ss-oc-card) !important;
 --surface-raised-strong:var(--ss-oc-card) !important;
 --surface-raised-stronger:var(--ss-oc-panel) !important;
 --input-base:var(--ss-oc-card) !important;--input-focus:var(--ss-oc-card) !important;
 --v2-background-bg-deep:transparent !important;
 --v2-background-bg-base:var(--ss-oc-surface) !important;
 --v2-background-bg-layer-01:var(--ss-oc-card) !important;
 --v2-background-bg-layer-02:var(--ss-oc-panel) !important;
 --v2-background-bg-layer-03:var(--ss-oc-panel) !important;
 --v2-background-bg-layer-04:var(--ss-oc-panel) !important;
 --v2-border-border-base:var(--ss-oc-line) !important;
 --v2-border-border-weak:var(--ss-oc-line) !important;
 --text-base:var(--ss-oc-ink) !important;--text-strong:var(--ss-oc-ink) !important;--text-stronger:var(--ss-oc-ink) !important;
 --text-weak:color-mix(in srgb,var(--ss-oc-ink) 88%,transparent) !important;
 --text-weaker:color-mix(in srgb,var(--ss-oc-ink) 80%,transparent) !important;
 --icon-base:var(--ss-oc-ink) !important;--icon-strong-base:var(--ss-oc-ink) !important;
 --icon-weak-base:color-mix(in srgb,var(--ss-oc-ink) 88%,transparent) !important;
 --v2-text-text-base:var(--ss-oc-ink) !important;
 --v2-text-text-muted:color-mix(in srgb,var(--ss-oc-ink) 88%,transparent) !important;
 --v2-text-text-faint:color-mix(in srgb,var(--ss-oc-ink) 80%,transparent) !important;
 --v2-icon-icon-base:var(--ss-oc-ink) !important;
 --v2-icon-icon-muted:color-mix(in srgb,var(--ss-oc-ink) 88%,transparent) !important;
 --v2-icon-icon-faint:color-mix(in srgb,var(--ss-oc-ink) 80%,transparent) !important;
 --text-mix-blend-mode:normal !important;
 color:var(--ss-oc-ink);
}
__SCOPE__ :is(aside,nav){
 background-color:color-mix(in srgb,var(--ss-oc-panel) var(--ss-oc-glass),transparent) !important;
 backdrop-filter:blur(8px);
}
/* Keep the native window-control reservation; extend only the glass behind it. */
__SCOPE__ [data-slot="titlebar-v2"]{background:transparent !important;isolation:isolate;}
__SCOPE__ [data-slot="titlebar-v2"]::before{
 content:"";position:absolute;inset:0;width:100vw;z-index:-1;pointer-events:none;
 background:color-mix(in srgb,var(--ss-oc-panel) var(--ss-oc-glass),transparent);
 backdrop-filter:blur(8px);
}
__SCOPE__ :is([data-component="composer"],[data-component="dock-prompt"]){
 background-color:color-mix(in srgb,var(--ss-oc-panel) 90%,transparent) !important;
 border:1px solid var(--ss-oc-line);backdrop-filter:blur(10px);
}
__SCOPE__ [data-component="session-composer-dock"]{background-color:transparent !important;}
/* Session and review panes share one glass coat. Native nested base surfaces
   (review wrapper, context body, legacy tabs) otherwise compound to ~97% white.
   Local token overrides leave raised cards, diffs, menus and webviews intact. */
__SCOPE__ [data-slot="session-side-panel-content"] aside{background-color:transparent !important;backdrop-filter:none;}
__SCOPE__ :is([data-slot="session-chat-panel"] > .bg-v2-background-bg-base,[data-slot="session-side-panel-content"] aside:not(aside aside)){
 --v2-background-bg-base:transparent;
 /* Tailwind aliases resolve on the declaring element, not on descendants. */
 --color-v2-background-bg-base:transparent;
 background-color:color-mix(in srgb,var(--ss-oc-panel) var(--ss-oc-session-content),transparent) !important;
 backdrop-filter:none;
}
/* A sticky header covers scrolling text, unlike the translucent reading pane. */
__SCOPE__ [data-session-title] > .bg-v2-background-bg-base{
 background-color:var(--ss-oc-panel) !important;
}
/* Overlays receive their own opaque tokens: nested menus must stay readable. */
__SCOPE__ :is([data-component="menu-v2-content"],[data-component="context-menu-content"],[data-component="context-menu-sub-content"],[data-component="popover-content"],[data-component="hover-card-content"],[data-component="tooltip-v2"],[data-slot="dialog-container"],[role="menu"],[role="dialog"]){
 --background-base:var(--ss-oc-panel);--background-weak:var(--ss-oc-panel);
 --v2-background-bg-base:var(--ss-oc-panel);--v2-background-bg-deep:var(--ss-oc-panel);
 --color-v2-background-bg-base:var(--ss-oc-panel);--color-v2-background-bg-deep:var(--ss-oc-panel);
 background-color:var(--ss-oc-panel) !important;color:var(--ss-oc-ink) !important;
}
__SCOPE__[data-skin-readable="on"] :is([data-component="icon-button-v2"],[data-component="icon-button"]):not(:disabled):not([aria-disabled="true"]) svg{
 filter:drop-shadow(0 0 1px var(--ss-oc-halo));
}
'@
    [void]$css.AppendLine($tokens.Replace('__SCOPE__', $scope))
    if ($palette.accent) {
        $matching = if ($appearance -in @('light','dark')) { '[data-color-scheme="' + $appearance + '"]' } else { '' }
        [void]$css.AppendLine($scope + $matching + '{--v2-border-border-focus:' + $palette.accent + ' !important;}')
    }
    if ($ThemePack.BgPath) {
        $mime = @{ '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.png'='image/png'; '.webp'='image/webp' }[[IO.Path]::GetExtension($ThemePack.BgPath).ToLowerInvariant()]
        $image = 'data:' + $mime + ';base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($ThemePack.BgPath))
        $position = [string]$ThemePack.Meta.position
        if ($position -notmatch '^(center|top|bottom|left|right|\d{1,3}% \d{1,3}%)$') { $position = 'center' }
        $fit = if ($ThemePack.Meta.fit -eq 'contain') { 'contain' } else { 'cover' }
        # Wallpaper is a direct declaration, avoiding Chromium's var() size limit.
        [void]$css.AppendLine($scope + ' body{background-image:url("' + $image + '") !important;background-size:' + $fit + ' !important;background-position:' + $position + ' !important;background-repeat:no-repeat !important;background-attachment:fixed !important;background-color:var(--ss-oc-panel) !important;}')
        [void]$css.AppendLine($scope + ' #root{background:transparent !important;min-height:100vh;}')
    }
    $cssJson = $css.ToString() | ConvertTo-Json -Compress
    $markerJson = (Get-SkinMarker $ThemePack $Options) | ConvertTo-Json -Compress
    $readability = if (Test-SkinReadability $Options) { 'on' } else { 'off' }
    return @"
(()=>{
 const root=document.documentElement;
 root.setAttribute('data-skin-studio','opencode');root.setAttribute('data-skin-readable','$readability');
 let style=document.getElementById('skin-studio-style');
 if(!style){style=document.createElement('style');style.id='skin-studio-style';(document.head||root).appendChild(style);}
 style.textContent=$cssJson;
 window.__SKIN_STUDIO=$markerJson;
 return window.__SKIN_STUDIO;
})()
"@
}

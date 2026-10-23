# WorkBuddy Electron renderer. Native controls and semantic action colors are preserved.
function Get-WorkBuddyReadyExpression {
    return @'
(()=>!!document.body&&(document.body.dataset.applicationName==='workbuddy'||
 (new URL(location.href).searchParams.get('windowKind')==='settings'&&!!window.workbuddyDesktop&&!!document.querySelector('.settings-window-root'))))()
'@
}

function Test-WorkBuddyTargetReady {
    param($Target)
    $ws=$null
    try {
        $ws=Connect-CdpWs $Target.webSocketDebuggerUrl
        $response=(Invoke-Cdp $ws 72 'Runtime.evaluate' @{expression=(Get-WorkBuddyReadyExpression);returnByValue=$true} -TimeoutMs 1500)|ConvertFrom-Json
        return -not $response.error -and -not $response.result.exceptionDetails -and $response.result.result.value -eq $true
    } catch { return $false }
    finally { if($ws){Disconnect-CdpWs $ws} }
}

function New-WorkBuddyReadyBootstrapJs {
    param([string]$Body)
    $ready=Get-WorkBuddyReadyExpression
    return @"
(async()=>{
 const started=performance.now();
 while(!($ready)){
   if(performance.now()-started>=5000)throw Error('WorkBuddy renderer is still initializing. Retry after the app window finishes opening.');
   await new Promise(resolve=>setTimeout(resolve,75));
 }
 $Body
 return window.__SKIN_STUDIO;
})()
"@
}

function New-WorkBuddyStyleBootstrapJs {
    param($ThemePack, $Options)
    $css = @'
html[data-skin-studio="workbuddy"] body[data-skin-studio-workbuddy]{
 --ss-wb-panel:#f8fafc;--ss-wb-ink:#17212d;--ss-wb-content:52%;--ss-wb-glass:60%;--ss-wb-filter:none;
}
html[data-skin-studio="workbuddy"] body[data-skin-studio-workbuddy].vscode-dark{
 --ss-wb-panel:#202630;--ss-wb-ink:#eef1f6;--ss-wb-content:64%;--ss-wb-glass:68%;
}
html[data-skin-studio="workbuddy"] body[data-skin-studio-workbuddy]{
 --ss-wb-surface:color-mix(in srgb,var(--ss-wb-panel) var(--ss-wb-content),transparent);
 --ss-wb-card:color-mix(in srgb,var(--ss-wb-panel) 92%,transparent);
 --ss-wb-line:color-mix(in srgb,var(--ss-wb-ink) 14%,transparent);
 --wb-color-bg-primary-default:transparent !important;
 --wb-color-bg-secondary-default:var(--ss-wb-surface) !important;
 --wb-color-bg-card-default:var(--ss-wb-card) !important;
 --wb-color-bg-input:var(--ss-wb-card) !important;
 --wb-color-bg-modal:var(--ss-wb-panel) !important;
 --wb-color-bg-primary-hover:color-mix(in srgb,var(--ss-wb-ink) 8%,transparent) !important;
 --wb-color-bg-primary-active:color-mix(in srgb,var(--ss-wb-ink) 12%,transparent) !important;
 --wb-color-border-primary:var(--ss-wb-line) !important;
 --wb-color-border-secondary:var(--ss-wb-line) !important;
 --wb-color-text-primary:var(--ss-wb-ink) !important;
 --wb-color-text-secondary:color-mix(in srgb,var(--ss-wb-ink) 84%,transparent) !important;
 --wb-color-text-tertiary:color-mix(in srgb,var(--ss-wb-ink) 76%,transparent) !important;
 --wb-color-text-placeholder:color-mix(in srgb,var(--ss-wb-ink) 68%,transparent) !important;
 --vscode-foreground:var(--ss-wb-ink) !important;
 --vscode-editor-foreground:var(--ss-wb-ink) !important;
 --vscode-editor-background:var(--ss-wb-card) !important;
 --vscode-sideBar-background:transparent !important;
 --vscode-titleBar-activeBackground:transparent !important;
 --vscode-titleBar-inactiveBackground:transparent !important;
 --vscode-titleBar-activeForeground:var(--ss-wb-ink) !important;
 --vscode-menu-background:var(--ss-wb-panel) !important;
 --vscode-menu-foreground:var(--ss-wb-ink) !important;
 --vscode-menu-selectionBackground:color-mix(in srgb,var(--ss-wb-ink) 12%,var(--ss-wb-panel)) !important;
 --vscode-menu-selectionForeground:var(--ss-wb-ink) !important;
 --vscode-input-background:var(--ss-wb-card) !important;
 --vscode-input-foreground:var(--ss-wb-ink) !important;
 color:var(--ss-wb-ink);
}
html[data-skin-studio="workbuddy"] #root{background-color:transparent !important;}
html[data-skin-studio="workbuddy"] :is(.teams-grid-scroll-content,[class*="_gridView_"],[class*="_gridViewItem_"],.conversation-list,.teams-container,.teams-content-wrapper,.teams-main-content,.main-content,.conversation-shell,.cr-frame,.cr-document,.cr-agent,.chat-container,.cr-message-list){background-color:transparent !important;}
html[data-skin-studio="workbuddy"] :is(.conversation-shell__main,.conversation-sidebar,.conversation-history-navigation){
 background-color:var(--ss-wb-surface) !important;backdrop-filter:var(--ss-wb-filter);
}
html[data-skin-studio="workbuddy"] :is(.sidebar-next,.workbuddy-topbar,.conversation-page-chrome__header){
 background-color:color-mix(in srgb,var(--ss-wb-panel) var(--ss-wb-glass),transparent) !important;backdrop-filter:var(--ss-wb-filter);
}
html[data-skin-studio="workbuddy"] .cr-input-container{
 background:var(--ss-wb-card) !important;border-color:var(--ss-wb-line) !important;box-shadow:0 4px 18px #00000010;
}
html[data-skin-studio="workbuddy"] :is(.cr-input-container-wrapper,[class*="_inputBottom_"],[class*="_emptyStateContainer_"]){background:transparent !important;}
html[data-skin-studio="workbuddy"] :is([role="menu"],[role="dialog"],[role="listbox"],.wb-dialog,.monaco-menu-container){
 --wb-color-bg-primary-default:var(--ss-wb-panel) !important;--wb-color-bg-secondary-default:var(--ss-wb-panel) !important;
 --vscode-editor-background:var(--ss-wb-panel) !important;
 background:var(--ss-wb-panel) !important;color:var(--ss-wb-ink) !important;backdrop-filter:none;
}
html[data-skin-studio="workbuddy"] .wb-homepage-disclaimer{color:color-mix(in srgb,var(--ss-wb-ink) 76%,transparent) !important;}
html[data-skin-studio="workbuddy"][data-skin-readable="on"] :is(.cr-icon-button,.wb-button--ghost):not(:disabled):not([aria-disabled="true"]) svg{filter:drop-shadow(0 0 1px color-mix(in srgb,var(--ss-wb-panel) 70%,transparent));}
html[data-skin-studio="workbuddy"] pre{background-color:var(--ss-wb-card) !important;}
'@
    if (-not (Test-SkinReadability $Options)) {
        $palette = Get-SkinPalette $ThemePack
        $appearance = [string]$ThemePack.Meta.appearance
        if ($appearance -in @('light','dark')) {
            $vars = ''
            if ($palette.panel) { $vars += '--ss-wb-panel:' + $palette.panel + ';' }
            if ($palette.text) { $vars += '--ss-wb-ink:' + $palette.text + ';' }
            $css += 'html[data-skin-studio="workbuddy"] body[data-skin-studio-workbuddy].vscode-' + $appearance + '{' + $vars + '}'
        }
    }
    if ($ThemePack.BgPath) {
        $mime = @{ '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.png'='image/png'; '.webp'='image/webp' }[[IO.Path]::GetExtension($ThemePack.BgPath).ToLowerInvariant()]
        $image = 'data:' + $mime + ';base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($ThemePack.BgPath))
        $position = [string]$ThemePack.Meta.position
        if ($position -notmatch '^(center|top|bottom|left|right|\d{1,3}% \d{1,3}%)$') { $position = 'center' }
        $fit = if ($ThemePack.Meta.fit -eq 'contain') { 'contain' } else { 'cover' }
        $css += 'html[data-skin-studio="workbuddy"] body{background-image:url("' + $image + '") !important;background-size:' + $fit + ' !important;background-position:' + $position + ' !important;background-repeat:no-repeat !important;background-attachment:fixed !important;}'
    }
    $cssJson = $css | ConvertTo-Json -Compress
    $markerJson = (Get-SkinMarker $ThemePack $Options) | ConvertTo-Json -Compress
    $readability = if (Test-SkinReadability $Options) { 'on' } else { 'off' }
    return @"
(()=>{
 const settings=new URL(location.href).searchParams.get('windowKind')==='settings'&&!!window.workbuddyDesktop&&!!document.querySelector('.settings-window-root');
 if(document.body?.dataset.applicationName!=='workbuddy'&&!settings)throw Error('Not a WorkBuddy renderer');
 document.body.setAttribute('data-skin-studio-workbuddy','');
 const root=document.documentElement;
 root.setAttribute('data-skin-studio','workbuddy');root.setAttribute('data-skin-readable','$readability');
 let style=document.getElementById('skin-studio-style');
 if(!style){style=document.createElement('style');style.id='skin-studio-style';(document.head||root).appendChild(style);}
 style.textContent=$cssJson;window.__SKIN_STUDIO=$markerJson;return window.__SKIN_STUDIO;
})()
"@
}


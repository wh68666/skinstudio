# Executed in the isolated Chromium fixture, never in a user's WorkBuddy session.
$wbSetup = @'
(()=>{document.body.className='agent-ui-theme vscode-dark';const host=document.createElement('div');host.id='wb-fixture';host.innerHTML='<div class="conversation-shell"><div class="conversation-shell__main">Chat<pre>const code = 1</pre><div class="cr-input-container"><button id="wb-send" style="background:rgb(20,127,153);color:white">Send</button></div></div></div><div role="dialog">Settings</div><div role="menu">Menu<button disabled id="wb-disabled" style="opacity:.4">Disabled</button></div>';document.getElementById('root').appendChild(host);return true})()
'@
[void](Invoke-Cdp $ws 81 'Runtime.evaluate' @{expression=$wbSetup;returnByValue=$true})
$sidebarSetup=@'
(()=>{const host=document.getElementById('wb-fixture'),sidebar=document.createElement('aside');sidebar.className='conversation-sidebar';sidebar.innerHTML='<div class="conversation-section-label" style="background:white;position:sticky;top:0">Tasks</div><div class="collapsible-section-header" style="background:white">Project</div><div class="conversation-agent-card _selected_fixture" style="background:white">Selected</div><div class="conversation-agent-card" style="background:white">Other</div><div class="wb-slot--avatar-top-combo" data-theme="dark"></div>';host.appendChild(sidebar);const shadow=sidebar.querySelector('.wb-slot--avatar-top-combo').attachShadow({mode:'open'});shadow.innerHTML='<style>:host{--cd:#fff;--t1:#111}.cb{background:var(--cd);color:var(--t1)}</style><div class="cb">Promotion<button style="background:rgb(20,127,153);color:white">Action</button></div>';return true})()
'@
[void](Invoke-Cdp $ws 811 'Runtime.evaluate' @{expression=$sidebarSetup;returnByValue=$true})
$sidebarProbe=@'
(()=>{const sidebar=document.querySelector('#wb-fixture .conversation-sidebar'),shadow=sidebar.querySelector('.wb-slot--avatar-top-combo').shadowRoot,c=document.createElement('canvas').getContext('2d');function alpha(e){c.clearRect(0,0,1,1);c.fillStyle=getComputedStyle(e).backgroundColor;c.fillRect(0,0,1,1);return c.getImageData(0,0,1,1).data[3]/255}return {header:alpha(sidebar.querySelector('.conversation-section-label')),project:alpha(sidebar.querySelector('.collapsible-section-header')),selected:alpha(sidebar.querySelector('._selected_fixture')),other:alpha(sidebar.querySelector('.conversation-agent-card:not(._selected_fixture)')),promo:alpha(shadow.querySelector('.cb')),promoInk:getComputedStyle(shadow.querySelector('.cb')).color,action:getComputedStyle(shadow.querySelector('button')).backgroundColor,sticky:getComputedStyle(sidebar.querySelector('.conversation-section-label')).position}})()
'@

$wbStyle = New-SkinBootstrapJs workbuddy $pack @{readability=$true;syncAppearance=$false}
[void](Invoke-Cdp $ws 82 'Runtime.evaluate' @{expression=$wbStyle;returnByValue=$true})
$wbProbe = @'
(()=>{const host=document.getElementById('wb-fixture'),style=e=>getComputedStyle(host.querySelector(e)),b=style('[role=menu]');return {menu:b.backgroundColor,ink:b.color,dialog:style('[role=dialog]').backgroundColor,shell:style('.conversation-shell').backgroundColor,blur:style('.conversation-shell__main').backdropFilter,disabled:style('#wb-disabled').opacity,send:style('#wb-send').backgroundColor,single:document.querySelectorAll('#skin-studio-style').length===1}})()
'@
$wb=((Invoke-Cdp $ws 83 'Runtime.evaluate' @{expression=$wbProbe;returnByValue=$true})|ConvertFrom-Json).result.result.value
Assert ($wb.menu -eq 'rgb(32, 38, 48)' -and $wb.ink -eq 'rgb(238, 241, 246)' -and $wb.dialog -eq $wb.menu) 'WorkBuddy dark menus/settings lost contrast'
Assert ($wb.shell -eq 'rgba(0, 0, 0, 0)' -and $wb.blur -in @('none','blur(0px)') -and $wb.single) 'WorkBuddy wallpaper was stacked or blurred'
Assert ($wb.disabled -eq '0.4' -and $wb.send -eq 'rgb(20, 127, 153)') 'WorkBuddy semantic button states were changed'
$bad="document.body.dataset.applicationName='guest';" + $wbStyle
$denied=(Invoke-Cdp $ws 84 'Runtime.evaluate' @{expression=$bad;returnByValue=$true;awaitPromise=$true})|ConvertFrom-Json
Assert ([bool]$denied.result.exceptionDetails) 'WorkBuddy renderer identity was not verified'
[void](Invoke-Cdp $ws 85 'Runtime.evaluate' @{expression="document.body.dataset.applicationName='workbuddy';document.body.className='agent-ui-theme vscode-light';";returnByValue=$true})
[void](Invoke-Cdp $ws 86 'Runtime.evaluate' @{expression=$wbStyle;returnByValue=$true})
$wb=((Invoke-Cdp $ws 87 'Runtime.evaluate' @{expression=$wbProbe;returnByValue=$true})|ConvertFrom-Json).result.result.value
Assert ($wb.menu -eq 'rgb(248, 250, 252)' -and $wb.ink -eq 'rgb(23, 33, 45)' -and $wb.single) 'WorkBuddy light menu or repeated injection failed'
foreach($mode in @('dark','light')){
 [void](Invoke-Cdp $ws 812 'Runtime.evaluate' @{expression="document.body.classList.toggle('vscode-dark','$mode'==='dark');";returnByValue=$true})
 $sidebar=((Invoke-Cdp $ws 813 'Runtime.evaluate' @{expression=$sidebarProbe;returnByValue=$true})|ConvertFrom-Json).result.result.value
 $ink=if($mode -eq 'dark'){'rgb(238, 241, 246)'}else{'rgb(23, 33, 45)'}
 Assert ($sidebar.header -lt .2 -and $sidebar.project -eq 0 -and $sidebar.other -eq 0 -and $sidebar.selected -gt .08 -and $sidebar.selected -lt .2) ('WorkBuddy sidebar still has opaque rows or lost selection: '+$mode)
 Assert ($sidebar.promo -lt .3 -and $sidebar.promoInk -eq $ink -and $sidebar.action -eq 'rgb(20, 127, 153)' -and $sidebar.sticky -eq 'sticky') ('WorkBuddy shadow card/theme semantics or sticky headings regressed: '+$mode)
}

$settingsSetup = @'
(()=>{window.__wbFixtureUrl=location.href;history.replaceState(null,'','?windowKind=settings');delete document.body.dataset.applicationName;document.body.className='settings-window vscode-light';window.workbuddyDesktop={};const settings=document.createElement('div');settings.className='settings-window-root';document.body.appendChild(settings);return true})()
'@
[void](Invoke-Cdp $ws 88 'Runtime.evaluate' @{expression=$settingsSetup;returnByValue=$true})
$settingsPack=@{}+$pack
$settingsPack.Meta=[pscustomobject]@{id='settings-fixture';version='1';appearance='dark'}
$settingsStyle=New-SkinBootstrapJs workbuddy $settingsPack @{readability=$true;syncAppearance=$true}
$settingsResult=(Invoke-Cdp $ws 89 'Runtime.evaluate' @{expression=$settingsStyle;returnByValue=$true;awaitPromise=$true})|ConvertFrom-Json
Assert (-not $settingsResult.result.exceptionDetails) 'WorkBuddy settings window without main-page marker rejected'
$settingsCheck=((Invoke-Cdp $ws 90 'Runtime.evaluate' @{expression="document.body.classList.contains('vscode-dark')&&document.body.hasAttribute('data-skin-studio-workbuddy')&&window.__SKIN_STUDIO_APPEARANCE.mode==='dark'";returnByValue=$true})|ConvertFrom-Json).result.result.value
Assert $settingsCheck 'WorkBuddy settings fallback did not synchronize appearance'
[void](Invoke-Cdp $ws 91 'Runtime.evaluate' @{expression="history.replaceState(null,'',window.__wbFixtureUrl);document.body.dataset.applicationName='workbuddy';document.body.className='agent-ui-theme vscode-light';document.querySelector('.settings-window-root').remove();delete window.workbuddyDesktop;";returnByValue=$true})

# A newly connected renderer can exist before its native identity marker.
# Wait before either appearance synchronization or custom visual CSS executes.
$delayedSetup="delete document.body.dataset.applicationName;window.__wbStart=performance.now();setTimeout(()=>{document.body.dataset.applicationName='workbuddy'},450);true"
[void](Invoke-Cdp $ws 92 'Runtime.evaluate' @{expression=$delayedSetup;returnByValue=$true})
$delayedJs=New-SkinBootstrapJs workbuddy $pack @{readability=$true;syncAppearance=$false;visual=@{panelOpacity=43;blur=0;position='right'}}
$delayed=(Invoke-Cdp $ws 93 'Runtime.evaluate' @{expression=$delayedJs;returnByValue=$true;awaitPromise=$true})|ConvertFrom-Json
Assert (-not $delayed.result.exceptionDetails) 'WorkBuddy cold-start marker race failed with appearance sync disabled'
$elapsed=((Invoke-Cdp $ws 94 'Runtime.evaluate' @{expression="({elapsed:performance.now()-window.__wbStart,custom:document.documentElement.dataset.skinVisual,style:!!document.getElementById('skin-studio-style')})";returnByValue=$true})|ConvertFrom-Json).result.result.value
Assert ($elapsed.elapsed -ge 400 -and $elapsed.custom -eq 'custom' -and $elapsed.style) 'WorkBuddy readiness did not precede visual overrides'
[void](Invoke-Cdp $ws 95 'Runtime.evaluate' @{expression=$delayedSetup;returnByValue=$true})
$delayedJs=New-SkinBootstrapJs workbuddy $settingsPack @{readability=$true;syncAppearance=$true}
$delayed=(Invoke-Cdp $ws 96 'Runtime.evaluate' @{expression=$delayedJs;returnByValue=$true;awaitPromise=$true})|ConvertFrom-Json
Assert (-not $delayed.result.exceptionDetails) 'WorkBuddy cold-start race failed before native appearance synchronization'

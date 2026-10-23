# Executed in the isolated Chromium fixture, never in a user's WorkBuddy session.
$wbSetup = @'
(()=>{document.body.className='agent-ui-theme vscode-dark';const host=document.createElement('div');host.id='wb-fixture';host.innerHTML='<div class="conversation-shell"><div class="conversation-shell__main">Chat<pre>const code = 1</pre><div class="cr-input-container"><button id="wb-send" style="background:rgb(20,127,153);color:white">Send</button></div></div></div><div role="dialog">Settings</div><div role="menu">Menu<button disabled id="wb-disabled" style="opacity:.4">Disabled</button></div>';document.getElementById('root').appendChild(host);return true})()
'@
[void](Invoke-Cdp $ws 81 'Runtime.evaluate' @{expression=$wbSetup;returnByValue=$true})
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
$denied=(Invoke-Cdp $ws 84 'Runtime.evaluate' @{expression=$bad;returnByValue=$true})|ConvertFrom-Json
Assert ([bool]$denied.result.exceptionDetails) 'WorkBuddy renderer identity was not verified'
[void](Invoke-Cdp $ws 85 'Runtime.evaluate' @{expression="document.body.dataset.applicationName='workbuddy';document.body.className='agent-ui-theme vscode-light';";returnByValue=$true})
[void](Invoke-Cdp $ws 86 'Runtime.evaluate' @{expression=$wbStyle;returnByValue=$true})
$wb=((Invoke-Cdp $ws 87 'Runtime.evaluate' @{expression=$wbProbe;returnByValue=$true})|ConvertFrom-Json).result.result.value
Assert ($wb.menu -eq 'rgb(248, 250, 252)' -and $wb.ink -eq 'rgb(23, 33, 45)' -and $wb.single) 'WorkBuddy light menu or repeated injection failed'
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

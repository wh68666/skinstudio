# Executed inside the verified, isolated Chromium fixture with $ws/$id/$pack.
$setupVisual = @'
(()=>{
 const host=document.createElement('div');host.id='visual-fixture';
 host.innerHTML='<div data-desktop-window-frame><div data-workspace-shell><div data-workspace-conversation-frame id="visual-zcode" style="background:var(--color-background)">ZCode</div></div></div><div id="visual-codex" data-app-shell-main-surface>Codex</div><div id="visual-monkeycode" style="background:var(--color-base-100)">MonkeyCode</div><div data-slot="session-chat-panel"><div id="visual-opencode" class="bg-v2-background-bg-base">OpenCode</div></div><button id="visual-disabled" disabled style="opacity:.4">Disabled</button><button id="visual-send" style="background:rgb(20,127,153);color:white">Send</button>';
 const css=document.createElement('style');css.textContent=':root{--color-v2-background-bg-base:var(--v2-background-bg-base)}.bg-v2-background-bg-base{background-color:var(--color-v2-background-bg-base)}';document.head.appendChild(css);
 document.getElementById('root').appendChild(host);return true;
})()
'@
[void](Invoke-Cdp $ws 50 'Runtime.evaluate' @{expression=$setupVisual;returnByValue=$true})
$defaults = @{readability=$true;syncAppearance=$false;themeAdjustments=@{fixture=(Get-SkinVisualPreset reading)}}
$defaultJs = New-SkinStyleBootstrapJs $id $pack $defaults
[void](Invoke-Cdp $ws 51 'Runtime.evaluate' @{expression=$defaultJs;returnByValue=$true})
$visualProbe = @"
(()=>{const pane=document.getElementById('visual-$id'),s=getComputedStyle(pane),bg=getComputedStyle(document.querySelector('$(@{zcode='#root';codex='body';opencode='body';monkeycode='.mc-workbench-background'}[$id])'));const ctx=document.createElement('canvas').getContext('2d');ctx.fillStyle=s.backgroundColor;ctx.fillRect(0,0,1,1);return {opacity:ctx.getImageData(0,0,1,1).data[3]/255,background:s.backgroundColor,blur:'$id'==='monkeycode'?bg.filter:s.backdropFilter,position:bg.backgroundPosition,custom:document.documentElement.getAttribute('data-skin-visual'),disabled:getComputedStyle(document.getElementById('visual-disabled')).opacity,send:getComputedStyle(document.getElementById('visual-send')).backgroundColor}})()
"@
$before = ((Invoke-Cdp $ws 52 'Runtime.evaluate' @{expression=$visualProbe;returnByValue=$true}) | ConvertFrom-Json).result.result.value
Assert ($null -eq $before.custom) ('Saved adjustment applied implicitly: '+$id)
$options = @{readability=$true;syncAppearance=$false;visual=@{panelOpacity=37;blur=4;position='bottom-right'}}
$customJs = New-SkinStyleBootstrapJs $id $pack $options
[void](Invoke-Cdp $ws 53 'Runtime.evaluate' @{expression=$customJs;returnByValue=$true})
$custom = ((Invoke-Cdp $ws 54 'Runtime.evaluate' @{expression=$visualProbe;returnByValue=$true}) | ConvertFrom-Json).result.result.value
$correctPosition = @($custom.position -split ',\s*' | Where-Object { $_ -ne '100% 100%' }).Count -eq 0
Assert ([Math]::Abs($custom.opacity-.37) -lt .01 -and $custom.blur -eq 'blur(4px)' -and $correctPosition -and $custom.custom -eq 'custom') ('Custom renderer adjustment failed: '+$id+' '+($custom|ConvertTo-Json -Compress))
Assert ($custom.disabled -eq '0.4' -and $custom.send -eq 'rgb(20, 127, 153)') ('Adjustment changed control states: '+$id)
Assert ((Get-SkinMarker $pack $options) -ne (Get-SkinMarker $pack $defaults)) ('Watcher marker did not include adjustment: '+$id)
$options.visual.blur = 0
$zeroJs = New-SkinStyleBootstrapJs $id $pack $options
[void](Invoke-Cdp $ws 55 'Runtime.evaluate' @{expression=$zeroJs;returnByValue=$true})
$zero = ((Invoke-Cdp $ws 56 'Runtime.evaluate' @{expression=$visualProbe;returnByValue=$true}) | ConvertFrom-Json).result.result.value
Assert ($zero.blur -eq 'none') ('Zero blur still filters the background: '+$id)
[void](Invoke-Cdp $ws 57 'Runtime.evaluate' @{expression=$defaultJs;returnByValue=$true})
$restored = ((Invoke-Cdp $ws 58 'Runtime.evaluate' @{expression=$visualProbe;returnByValue=$true}) | ConvertFrom-Json).result.result.value
Assert (($before|ConvertTo-Json -Compress) -eq ($restored|ConvertTo-Json -Compress)) ('Default appearance failed to reset custom overrides: '+$id)

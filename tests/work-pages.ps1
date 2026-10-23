# Synthetic work-page regressions. These results must never count as device acceptance.
$workHtml=Join-Path $temp 'work-page-fixture.html'
Copy-Item (Join-Path $PSScriptRoot 'work-page-fixture.html') $workHtml
$workTargetId=$null; $workWs=$null
$control=Connect-CdpWs $target.webSocketDebuggerUrl
try{
    $created=(Invoke-Cdp $control 401 'Target.createTarget' @{url=([Uri]::new($workHtml)).AbsoluteUri;newWindow=$true;width=1200;height=800})|ConvertFrom-Json
    $workTargetId=$created.result.targetId
    Assert ([bool]$workTargetId) ('Work-page creation failed: '+($created|ConvertTo-Json -Compress -Depth 6))
    $workTarget=$null
    foreach($attempt in 1..20){$workTarget=@(Get-CdpPageTargets $port | Where-Object id -eq $workTargetId)[0];if($workTarget){break};Start-Sleep -Milliseconds 100}
    Assert ([bool]$workTarget) 'Work-page fixture did not open'
    $workWs=Connect-CdpWs $workTarget.webSocketDebuggerUrl
    $auditJs=[IO.File]::ReadAllText((Join-Path $root 'skin-workpage-audit.js'))
    $caseCount=0
    foreach($appId in $script:SkinApps.Keys){foreach($mode in @('light','dark')){
        $clone=@{}+$pack; $clone.Meta=[pscustomobject]@{id='fixture';version='0.0.0';appearance=$mode}
        $dark=($mode -eq 'dark').ToString().ToLowerInvariant()
        $setup="(()=>{document.documentElement.className=$('$mode'|ConvertTo-Json -Compress);document.documentElement.classList.add('theme-zai-$mode');document.documentElement.dataset.theme='$mode';document.documentElement.dataset.colorScheme='$mode';document.querySelectorAll('#zc-skin-style,#skin-studio-style').forEach(e=>e.remove());return true})()"
        [void](Invoke-Cdp $workWs 402 'Runtime.evaluate' @{expression=$setup;returnByValue=$true})
        $style=New-SkinStyleBootstrapJs $appId $clone @{readability=$true;syncAppearance=$false}
        $r=(Invoke-Cdp $workWs 403 'Runtime.evaluate' @{expression=$style;returnByValue=$true;awaitPromise=$true})|ConvertFrom-Json
        Assert (-not $r.result.exceptionDetails) ('Working-page injection failed: '+$appId+'/'+$mode)
        if($appId -eq 'monkeycode'){
            $contrast=@'
(()=>{const canvas=document.createElement('canvas'),c=canvas.getContext('2d');function rgb(color){c.clearRect(0,0,1,1);c.fillStyle=color;c.fillRect(0,0,1,1);return [...c.getImageData(0,0,1,1).data].slice(0,3).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4})}function luminance(x){return x[0]*.2126+x[1]*.7152+x[2]*.0722}const bg=luminance(rgb(getComputedStyle(document.querySelector('pre')).backgroundColor)),fg=luminance(rgb(getComputedStyle(document.querySelector('.hljs-comment')).color));return (Math.max(bg,fg)+.05)/(Math.min(bg,fg)+.05)})()
'@
            $ratio=((Invoke-Cdp $workWs 408 'Runtime.evaluate' @{expression=$contrast;returnByValue=$true})|ConvertFrom-Json).result.result.value
            Assert ($ratio -ge 4) ('MonkeyCode code comments lost contrast: '+$mode+' / '+$ratio)
        }
        foreach($scene in $script:SkinCompatibilityScenes){
            $toggle="(()=>{document.getElementById('case-menu').hidden=$('true');document.getElementById('case-settings').hidden=$('true');if('$scene'==='menu')document.getElementById('case-menu').hidden=false;if('$scene'==='settings')document.getElementById('case-settings').hidden=false;return true})()"
            [void](Invoke-Cdp $workWs 404 'Runtime.evaluate' @{expression=$toggle;returnByValue=$true})
            $observed=((Invoke-Cdp $workWs 405 'Runtime.evaluate' @{expression=$auditJs;returnByValue=$true})|ConvertFrom-Json).result.result.value
            Assert ($observed.scenes.$scene.present) ('Missing fixture scenario: '+$appId+'/'+$mode+'/'+$scene)
            Assert ($observed.mode -eq $mode) ('Working-page mode mismatch: '+$appId+'/'+$mode)
            Assert ($observed.scenes.code.clipped -eq 0) ('Code horizontally clipped: '+$appId+'/'+$mode)
            $layout=@'
(()=>{const box=document.querySelector('textarea').getBoundingClientRect(),pre=document.querySelector('pre'),scroll=document.querySelector('.thread-scroll-container');const before=box.top;scroll.scrollTop=scroll.scrollHeight;const after=document.querySelector('textarea').getBoundingClientRect().top;return {composer:box.width>100&&box.height>20&&box.bottom<=innerHeight,fixed:Math.abs(before-after)<1,scroll:scroll.scrollTop>0,code:pre.scrollWidth>=pre.clientWidth&&pre.clientWidth<innerWidth}})()
'@
            $check=((Invoke-Cdp $workWs 406 'Runtime.evaluate' @{expression=$layout;returnByValue=$true})|ConvertFrom-Json).result.result.value
            Assert ($check.composer -and $check.fixed -and $check.scroll -and $check.code) ('Working-page layout failed: '+$appId+'/'+$mode+'/'+$scene)
            $caseCount++
        }
    }}
    Assert ($caseCount -eq 56) 'Working-page matrix incomplete'
    Write-Host 'PASS: 56 synthetic working-page cases (4 apps x 2 modes x 7 scenes); no device-acceptance record written.'
}finally{
    if($workWs){Disconnect-CdpWs $workWs}
    if($workTargetId){[void](Invoke-Cdp $control 407 'Target.closeTarget' @{targetId=$workTargetId})}
    Disconnect-CdpWs $control
}

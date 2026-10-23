# Regression checks use temporary fixtures and never restart the user's apps.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$root = Join-Path $projectRoot 'src'
$builtin = Join-Path $projectRoot 'resources\themes\aurora'
. (Join-Path $root 'skin-lib.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Work, [string]$Message) {
    $threw = $false
    try { & $Work } catch { $threw = $true }
    Assert $threw $Message
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('SkinStudio-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item $temp -ItemType Directory)
try {
    . (Join-Path $PSScriptRoot 'storage.ps1')
    $sourceFiles=@(Get-ChildItem $root -Filter *.ps1) + @(Get-ChildItem (Join-Path $projectRoot 'scripts') -Filter *.ps1) + @(Get-ChildItem (Join-Path $projectRoot 'packaging') -Filter *.ps1) + @(Get-ChildItem $PSScriptRoot -Filter *.ps1)
    foreach ($file in $sourceFiles) {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert (-not $errors.Count) ('Parse failure: ' + $file.Name + ': ' + ($errors -join '; '))
    }
    $cfg = Join-Path $temp 'config.json'
    [IO.File]::WriteAllText($cfg, '{"currentTheme":"aurora","port":9224,"appExe":"D:\\ZCode\\ZCode.exe","lang":"zh-CN"}')
    $settings = Read-SkinSettings $cfg
    Assert ($settings.managerTheme -eq 'pearl') 'Legacy config changed the default manager appearance'
    Assert ($settings.apps.zcode.currentTheme -eq 'aurora') 'Legacy theme was lost'
    Assert ($settings.apps.zcode.appExe -eq 'D:\ZCode\ZCode.exe') 'Legacy app path was lost'
    Assert ($settings.apps.codex.currentTheme -eq '') 'Legacy theme leaked into Codex'
    Assert (@($settings.apps.Values.port | Select-Object -Unique).Count -eq 4) 'Ports collide after migration'
    $settings.apps.codex.currentTheme = 'other'
    $settings.managerTheme = 'midnight'
    $settings.apps.codex.readability = $false
    $settings.apps.codex.syncAppearance = $false
    $settings.apps.opencode.currentTheme = 'open-theme'
    Write-SkinSettings $cfg $settings
    $roundtrip = Read-SkinSettings $cfg
    Assert ($roundtrip.managerTheme -eq 'midnight') 'Manager appearance was not restored from settings'
    Assert ($roundtrip.apps.codex.currentTheme -eq 'other' -and $roundtrip.apps.zcode.currentTheme -eq 'aurora') 'Profiles are not isolated'
    Assert (-not $roundtrip.apps.codex.readability) 'Readability preference was not preserved'
    Assert (-not $roundtrip.apps.codex.syncAppearance) 'Appearance sync preference was not preserved'
    Assert ($roundtrip.apps.opencode.currentTheme -eq 'open-theme' -and $roundtrip.apps.opencode.port -eq 9336 -and $roundtrip.apps.opencode.syncAppearance) 'OpenCode profile was not preserved independently'
    $roundtrip.apps.opencode.themeAdjustments.aurora = @{panelOpacity=73;blur=5;position='bottom-right'}
    $roundtrip.apps.opencode.themeAdjustments.'open-theme' = Get-SkinVisualPreset reading
    $roundtrip.apps.codex.themeAdjustments.aurora = Get-SkinVisualPreset clear
    $roundtrip.apps.opencode.activeVisual = @{themeId='open-theme';panelOpacity=42;blur=2;position='left'}
    Write-SkinSettings $cfg $roundtrip
    $visualRoundtrip = Read-SkinSettings $cfg
    Assert ($visualRoundtrip.schemaVersion -eq 4) 'Visual preferences need a protected configuration version'
    Assert ($visualRoundtrip.apps.opencode.themeAdjustments.aurora.panelOpacity -eq 73 -and $visualRoundtrip.apps.codex.themeAdjustments.aurora.panelOpacity -eq 56) 'Visual preferences leaked between applications'
    Assert ($visualRoundtrip.apps.opencode.themeAdjustments.'open-theme'.panelOpacity -eq 88 -and $visualRoundtrip.apps.opencode.activeVisual.panelOpacity -eq 42) 'Saved adjustments replaced active values without applying'
    Assert ($null -eq (Get-SkinThemeOptions $visualRoundtrip.apps.opencode 'open-theme' -Default).visual) 'Normal apply picked saved/active adjustments'
    Assert ((Get-SkinThemeOptions $visualRoundtrip.apps.opencode 'open-theme').visual.panelOpacity -eq 42 -and $null -eq (Get-SkinThemeOptions $visualRoundtrip.apps.opencode aurora).visual) 'Active adjustment crossed theme boundaries'
    $visualRoundtrip.apps.opencode.activeVisual = $null
    Write-SkinSettings $cfg $visualRoundtrip
    $visualReset = Read-SkinSettings $cfg
    Assert ($null -eq $visualReset.apps.opencode.activeVisual -and $visualReset.apps.opencode.themeAdjustments.aurora.blur -eq 5) 'Returning to default deleted saved adjustments'
    Assert ($null -eq (ConvertTo-SkinVisual @{panelOpacity=101;blur=0;position='center'})) 'Out-of-range visual preference accepted'
    Assert ($null -eq (ConvertTo-SkinVisual @{panelOpacity=50;blur=0;position='center; color:red'})) 'Unsafe wallpaper position accepted'
    $visualReset.favorites = @('aurora','tom-and-jerry-solid-serenade','aurora','../unsafe')
    Write-SkinSettings $cfg $visualReset
    $favorites = Read-SkinSettings $cfg
    Assert ($favorites.favorites.Count -eq 2 -and $favorites.favorites -contains 'aurora' -and $favorites.apps.opencode.themeAdjustments.aurora.panelOpacity -eq 73) 'Favorite migration lost adjustments or accepted unsafe/duplicate IDs'
    . (Join-Path $root 'skin-thumbnails.ps1')
    $thumbnail = Read-ThemeThumbnail (Join-Path $builtin 'background.jpg')
    Assert ($thumbnail.PixelWidth -gt 1 -and $thumbnail.PixelWidth -le 320 -and $thumbnail.PixelHeight -le 240 -and $thumbnail.IsFrozen) 'Thumbnail decode lost detail, size bounds or cross-thread support'
    $cacheDir = Join-Path $temp 'thumbnail-cache'
    [void](New-Item $cacheDir -ItemType Directory)
    $cacheFile = Join-Path $cacheDir 'fixture-version-v1.jpg'
    Copy-Item (Join-Path $builtin 'background.jpg') $cacheFile
    $cachedThumbnail = Get-RemoteThemeThumbnail 'fixture-version' $cacheDir
    Assert ($cachedThumbnail.PixelWidth -eq $thumbnail.PixelWidth) 'Disk thumbnail cache could not reopen offline'
    $exclusive = [IO.File]::Open($cacheFile,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $exclusive.Dispose()
    [IO.File]::WriteAllText((Join-Path $temp 'bad-image.jpg'),'invalid image')
    Assert-Throws { Read-ThemeThumbnail (Join-Path $temp 'bad-image.jpg') } 'Invalid preview was decoded as an image'
    # Existing schema 2 profiles gain OpenCode without changing their selections.
    [IO.File]::WriteAllText($cfg, '{"schemaVersion":2,"activeApp":"codex","apps":{"codex":{"currentTheme":"other","port":9335}}}')
    $upgrade = Read-SkinSettings $cfg
    Assert ($upgrade.managerTheme -eq 'pearl') 'Older settings need the original light manager palette'
    [IO.File]::WriteAllText($cfg, '{"schemaVersion":4,"managerTheme":"missing-palette","activeApp":"opencode","apps":{"opencode":{"currentTheme":"existing"}}}')
    $unknownPalette=Read-SkinSettings $cfg
    Assert ($unknownPalette.managerTheme -eq 'pearl' -and $unknownPalette.apps.opencode.currentTheme -eq 'existing') 'Unknown manager palette broke existing application settings'
    Assert ($upgrade.activeApp -eq 'codex' -and $upgrade.apps.codex.currentTheme -eq 'other' -and $upgrade.apps.opencode.currentTheme -eq '' -and $upgrade.apps.opencode.port -eq 9336) 'Upgrade changed an existing selection'
    [IO.File]::WriteAllText($cfg, '{"schemaVersion":99}')
    Assert-Throws { Read-SkinSettings $cfg } 'Newer settings must not be overwritten'
    Assert (-not (Test-SkinDesktopExe codex (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'))) 'CLI mistaken for desktop'
    $desktop = Join-Path $temp 'desktop'
    [void](New-Item (Join-Path $desktop 'resources') -ItemType Directory -Force)
    [IO.File]::WriteAllText((Join-Path $desktop 'OpenCode.exe'), '')
    Assert (-not (Test-SkinDesktopExe opencode (Join-Path $desktop 'OpenCode.exe'))) 'OpenCode CLI mistaken for Electron desktop'
    [IO.File]::WriteAllText((Join-Path $desktop 'resources\app.asar'), '')
    Assert (Test-SkinDesktopExe opencode (Join-Path $desktop 'OpenCode.exe')) 'OpenCode desktop rejected'
    [IO.File]::WriteAllText((Join-Path $desktop 'opencode-cli.exe'), '')
    Assert (-not (Test-SkinDesktopExe opencode (Join-Path $desktop 'opencode-cli.exe'))) 'Bundled OpenCode CLI mistaken for desktop'

    $packDir = Join-Path $temp 'package'
    [void](New-Item $packDir -ItemType Directory)
    Copy-Item (Join-Path $builtin 'background.jpg') $packDir
    # A decodable JPEG with trailing padding reproduces Chromium's 2^21-byte
    # variable substitution limit, which small wallpapers do not exercise.
    $jpeg = [IO.File]::ReadAllBytes((Join-Path $packDir 'background.jpg'))
    $largeJpeg = New-Object byte[] (2MB + 4096)
    [Array]::Copy($jpeg, $largeJpeg, $jpeg.Length)
    [IO.File]::WriteAllBytes((Join-Path $packDir 'background.jpg'), $largeJpeg)
    [IO.File]::WriteAllText((Join-Path $packDir 'theme.json'), '{"id":"fixture","name":"Fixture","appearance":"light","image":"background.jpg","colors":{"background":"#fafafa","panel":"#ffffff80","text":"#111111","accent":"#0066cc"},"art":{"focusX":0.25,"focusY":0.75}}')
    [IO.File]::WriteAllText((Join-Path $packDir 'theme.css'), '.codex-only{color:red}')
    $zip = Join-Path $temp 'fixture.zip'
    Compress-Archive -Path (Join-Path $packDir '*') -DestinationPath $zip
    $themes = Join-Path $temp 'themes'
    $result = Import-CodexThemePack -ZipPath $zip -ThemesRoot $themes
    $pack = Get-ThemePack $result.Dir
    Assert ($pack.Meta.colors.text -eq '#111111') 'Import discarded the portable color palette'
    Assert ($pack.Meta.position -eq '25% 75%') 'Import discarded focal point'
    Assert-Throws { Import-CodexThemePack -ZipPath $zip -ThemesRoot $themes } 'Duplicate import should require Force'
    $scripts = @{}
    foreach ($id in $script:SkinApps.Keys) {
        $scripts[$id] = New-SkinBootstrapJs $id $pack @{ readability = $false; syncAppearance = $false }
        Assert ($scripts[$id] -match '__SKIN_STUDIO') ('Missing marker for ' + $id)
        Assert ($scripts[$id] -notmatch 'codex-only') ('Codex-only CSS leaked into ' + $id)
    }
    Assert ($scripts.monkeycode -match '--color-base-content:#111111') 'MonkeyCode palette mapping failed'
    Assert ($scripts.codex -match '--color-token-text-primary:#111111') 'Codex palette mapping failed'
    $nativeZip = Join-Path $temp 'native.zip'
    Compress-Archive -Path (Join-Path $builtin '*') -DestinationPath $nativeZip
    $native = Import-CodexThemePack -ZipPath $nativeZip -ThemesRoot $themes
    Assert ((Get-ThemePack $native.Dir).Version -eq '1.0.0') 'Native theme ZIP/version not supported'
    $monkey = @{ Meta = [pscustomobject]@{ id='legacy-monkey'; version='1' }; BgPath=$pack.BgPath; Css='html[data-mc-background="active"]{--color-base-300:#123456;--color-base-content:#abcdef;}' }
    Assert ((New-SkinBootstrapJs zcode $monkey) -match '--color-background:#123456') 'Legacy MonkeyCode palette cannot be used in ZCode'

    # Test target selection independently of network/installed application state.
    function Test-SkinCdpOwner { return $true }
    function Get-CdpPageTargets { return $script:FixtureTargets }
    foreach ($case in @(@('zcode','file:///C:/ZCode/resources/app.asar/out/renderer/index.html'), @('monkeycode','http://tauri.localhost/'), @('codex','app://-/index.html'), @('opencode','oc://renderer/index.html'), @('opencode','oc://renderer/new-session?draftId=123'))) {
        $script:FixtureTargets = @(
            [pscustomobject]@{ type='page'; id='a'; url=$case[1]; webSocketDebuggerUrl='ws://127.0.0.1:19223/devtools/page/a' },
            [pscustomobject]@{ type='page'; id='b'; url='https://example.com/'; webSocketDebuggerUrl='ws://127.0.0.1:19223/devtools/page/b' },
            [pscustomobject]@{ type='page'; id='c'; url=$case[1]; webSocketDebuggerUrl='ws://example.com:19223/devtools/page/c' }
        )
        if ($case[0] -eq 'codex') {
            $script:FixtureTargets += [pscustomobject]@{ type='page'; id='d'; url='app://-/index.html?initialRoute=%2Favatar-overlay'; webSocketDebuggerUrl='ws://127.0.0.1:19223/devtools/page/d' }
        }
        if ($case[0] -eq 'monkeycode') {
            $script:FixtureTargets += [pscustomobject]@{type='page';id='pet';url='http://tauri.localhost/pet.html';webSocketDebuggerUrl='ws://127.0.0.1:19223/devtools/page/pet'}
        }
        if ($case[0] -eq 'opencode') {
            foreach ($url in @('oc://external/index.html','oc://renderer/assets/main.js','http://localhost:4096/','file:///C:/opencode/index.html')) {
                $script:FixtureTargets += [pscustomobject]@{type='page';id='bad';url=$url;webSocketDebuggerUrl='ws://127.0.0.1:19223/devtools/page/bad'}
            }
        }
        $targets = @(Get-SkinTargets $case[0] 'fixture.exe' 19223)
        Assert ($targets.Count -eq 1 -and $targets[0].id -eq 'a') ('Cross-target filtering failed for ' + $case[0])
    }
    Remove-Item Function:\Test-SkinCdpOwner, Function:\Get-CdpPageTargets
    . (Join-Path $root 'skin-lib.ps1')

    . (Join-Path $PSScriptRoot 'operation-state.ps1')
    . (Join-Path $PSScriptRoot 'compatibility.ps1')
    # Real Chromium + the production WebSocket transport. Dedicated headless profile.
    $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
    Assert (Test-Path $edge) 'Edge is required for renderer integration tests'
    $html = Join-Path $temp 'fixture.html'
    $nativeModule = 'export const definitions={theme:{key:"appearanceTheme"}};export const host={settings:{read:async()=>({configured:window.__fixtureNativeMode}),write:async(key,value)=>{window.__fixtureNativeMode=value;document.documentElement.dataset.theme=value;}}};'
    [IO.File]::WriteAllText((Join-Path $temp 'app-shared-fixture.js'),$nativeModule)
    [IO.File]::WriteAllText($html, '<html class="theme-zai-light" data-theme="light"><head><style>:root{--color-surface:#fff;--color-text:#111;--color-foreground:#111111;--color-popover:#fafafa;--color-popover-foreground:var(--color-foreground)}.theme-zai-dark{--color-foreground:#eeeeee;--color-popover:#202020}[data-theme=dark]{--color-surface:#202020;--color-text:#eeeeee}html[data-theme="mc-light"]{}html[data-theme="mc-dark"]{}body{margin:0}button._Button_fixture{background:transparent}#root{height:100vh}.panel{background:var(--color-token-bg-secondary,var(--color-panel,white));color:var(--color-token-text-primary,var(--color-text));padding:32px}[data-app-shell-main-surface],[data-composer-surface-variant]{background-color:var(--color-surface)}.mc-workbench-background{position:fixed;inset:0;z-index:-1}</style></head><body><div class="mc-workbench-background"></div><div id="root" data-app-shell-application-menu-bar="true" data-app-shell-page-surface="true" style="--app-shell-titlebar-height:8px"><main data-app-shell-main-surface="default" style="margin-top:var(--app-shell-titlebar-height)"><div class="thread-scroll-container"><div aria-hidden="true" class="_background_fixture _fade_fixture" style="background:linear-gradient(to top,white,transparent)"></div></div><div class="_ApplicationMenuTopBar_fixture"><button id="tool" class="_Button_fixture" style="color:rgba(26,28,31,.49)"><svg width="10" height="10"></svg>Menu</button><button id="disabled" disabled class="_Button_fixture" style="opacity:.4"><svg></svg>Disabled</button><button id="send" style="background:rgb(20,127,153);color:white">Send</button></div><div id="zmenu" role="menu" style="background:var(--color-popover);color:var(--color-popover-foreground)">Menu</div><button id="zghost" data-variant="ghost" style="background:transparent;color:var(--color-foreground)"><svg width="10" height="10"></svg>Action</button><div class="panel">SkinStudio renderer verification</div><div data-thread-scroll-footer="true" style="background:white"><div aria-hidden="true" class="_background_fixture" style="background:white;position:absolute;inset:0;pointer-events:none"></div><div data-composer-surface-variant="default">Composer</div></div></main></div></body></html>')
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
    $browser = Start-Process -FilePath $edge -ArgumentList @('--headless=new','--disable-gpu','--no-first-run','--allow-file-access-from-files',('--user-data-dir="' + (Join-Path $temp 'browser') + '"'),"--remote-debugging-port=$port",'--remote-debugging-address=127.0.0.1',('"' + $html + '"')) -PassThru -WindowStyle Hidden
    try {
        Assert ([bool](Wait-CdpOpen -Port $port -TimeoutSec 15)) 'Headless CDP failed to open'
        Assert (Test-SkinCdpOwner zcode $edge $port) 'Real endpoint owner was not recognized'
        Assert (-not (Test-SkinCdpOwner zcode 'C:\unrelated.exe' $port)) 'Unrelated process accepted as CDP owner'
        $target = @(Get-CdpPageTargets -Port $port | Where-Object { $_.url -like 'file://*/fixture.html' })[0]
        Assert ([bool]$target) 'Fixture page was not opened by Edge'
        foreach ($id in $script:SkinApps.Keys) {
            $ws = Connect-CdpWs $target.webSocketDebuggerUrl
            try {
                [void](Invoke-Cdp $ws 1 'Page.reload' @{})
                Start-Sleep -Milliseconds 250
            } finally { Disconnect-CdpWs $ws }
            Assert (Push-ThemeToTarget $target $scripts[$id] (Join-Path $temp 'cdp.log')) ('Injection failed: ' + $id)
            Assert ((Get-TargetSkinMarker $target) -eq (Get-SkinMarker $pack @{ readability = $false; syncAppearance = $false })) ('Marker missing: ' + $id)
            $effect=Test-TargetSkinEffect $target $id (Get-SkinMarker $pack @{readability=$false;syncAppearance=$false}) $true
            Assert $effect.ok ('Independent style/wallpaper verification failed: '+$id+' / '+$effect.reason)
            Assert (-not (Test-TargetSkinEffect $target $id 'wrong-marker' $true).ok) 'Wrong theme marker passed verification'
            $ws = Connect-CdpWs $target.webSocketDebuggerUrl
            try {
                $expression = switch ($id) {
                    'zcode' { "getComputedStyle(document.getElementById('root')).backgroundImage.includes('data:image/jpeg')" }
                    'monkeycode' { "getComputedStyle(document.querySelector('.mc-workbench-background')).backgroundImage.includes('data:image/jpeg')" }
                    'codex' { "getComputedStyle(document.body).backgroundImage.includes('data:image/jpeg')" }
                    'opencode' { "getComputedStyle(document.body).backgroundImage.includes('data:image/jpeg')" }
                }
                $reply = (Invoke-Cdp $ws 20 'Runtime.evaluate' @{ expression=$expression; returnByValue=$true }) | ConvertFrom-Json
                Assert ($reply.result.result.value -eq $true) ('Wallpaper is not rendered for ' + $id)
                if ($id -eq 'zcode') {
                    # A light author's stylesheet must not recolor native dark mode.
                    $js = "document.documentElement.className='theme-zai-dark';getComputedStyle(document.documentElement).getPropertyValue('--color-foreground').trim()==='#eeeeee'"
                    $opposite = (Invoke-Cdp $ws 30 'Runtime.evaluate' @{expression=$js;returnByValue=$true}) | ConvertFrom-Json
                    Assert $opposite.result.result.value 'Light ZCode theme text leaked into dark mode'
                    $safeJs = New-SkinBootstrapJs zcode $pack @{readability=$true;syncAppearance=$false}
                    [void](Invoke-Cdp $ws 31 'Runtime.evaluate' @{expression=$safeJs;returnByValue=$true})
                    $menuJs = "getComputedStyle(document.getElementById('zmenu')).color==='rgb(238, 241, 246)' && getComputedStyle(document.getElementById('zmenu')).backgroundColor==='rgb(32, 38, 48)' && getComputedStyle(document.getElementById('zghost')).backgroundColor==='rgba(0, 0, 0, 0)'"
                    $menu = (Invoke-Cdp $ws 32 'Runtime.evaluate' @{expression=$menuJs;returnByValue=$true}) | ConvertFrom-Json
                    Assert $menu.result.result.value 'ZCode menu contrast or transparent button check failed'
                    # Reproduce the native shell's nested surfaces and shared composer.
                    # Contrast is measured after compositing over black/white wallpaper.
                    $glassJs = @'
(()=>{
 const host=document.createElement('div');host.id='z-workspace-fixture';
 host.innerHTML=`<div data-desktop-window-frame style="background:var(--color-background-win-alt);color:var(--color-foreground)"><div data-workspace-shell style="display:flex;width:600px;height:240px"><aside data-workspace-sidebar-panel style="width:180px">Sidebar</aside><section data-workspace-conversation-frame style="width:420px;background:var(--color-background)"><div class="chat-composer-input-surface" style="background:rgba(13,13,13,.03)"><button data-variant="ghost" style="background:transparent">Project</button><div data-composer-layout="stacked" style="background:white"><button id="zc-disabled" disabled style="opacity:.5">Disabled</button><button id="zc-send" style="background:rgb(20,127,153);color:white">Send</button><button id="zc-danger" style="color:rgb(224,49,49)">Delete</button></div></div></section></div></div>`;
 document.getElementById('root').appendChild(host);
 const frame=host.firstElementChild,sidebar=host.querySelector('aside'),main=host.querySelector('section'),card=host.querySelector('.chat-composer-input-surface'),editor=host.querySelector('[data-composer-layout]');
 const ctx=document.createElement('canvas').getContext('2d',{willReadFrequently:true});
 const pixel=(css,under)=>{ctx.clearRect(0,0,1,1);ctx.fillStyle=under;ctx.fillRect(0,0,1,1);ctx.fillStyle=css;ctx.fillRect(0,0,1,1);return [...ctx.getImageData(0,0,1,1).data].slice(0,3)};
 const lum=rgb=>rgb.map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4}).reduce((s,x,i)=>s+x*[.2126,.7152,.0722][i],0);
 const ratios=[],surfaces=[];
 for(const mode of ['light','dark']){
  document.documentElement.className='theme-zai-'+mode;
  for(const pane of [sidebar,main]){
   const style=getComputedStyle(pane),text=lum(pixel(style.color,'#000'));
   for(const wallpaper of ['#000','#fff']){const bg=lum(pixel(style.backgroundColor,wallpaper));ratios.push((Math.max(text,bg)+.05)/(Math.min(text,bg)+.05))}
  }
  surfaces.push(getComputedStyle(frame).backgroundColor==='rgba(0, 0, 0, 0)' && getComputedStyle(sidebar).backdropFilter==='blur(8px)' && getComputedStyle(editor).backgroundColor==='rgba(0, 0, 0, 0)' && getComputedStyle(card).backgroundColor!=='rgba(0, 0, 0, 0)' && getComputedStyle(main).borderRadius==='14px' && main.getBoundingClientRect().width===420);
 }
 const states=getComputedStyle(document.getElementById('zc-disabled')).opacity==='0.5' && getComputedStyle(document.getElementById('zc-send')).backgroundColor==='rgb(20, 127, 153)' && getComputedStyle(document.getElementById('zc-danger')).color==='rgb(224, 49, 49)';
 return {pass:surfaces.every(Boolean) && states && Math.min(...ratios)>=4.5,minContrast:Math.min(...ratios),surfaces,states};
})()
'@
                    $glass = (Invoke-Cdp $ws 33 'Runtime.evaluate' @{expression=$glassJs;returnByValue=$true}) | ConvertFrom-Json
                    Assert $glass.result.result.value.pass ('ZCode glass compositing/contrast/state check failed: ' + ($glass.result.result.value | ConvertTo-Json -Compress))
                    [void](Invoke-Cdp $ws 34 'Runtime.evaluate' @{expression=$scripts.zcode;returnByValue=$true})
                    $off = (Invoke-Cdp $ws 35 'Runtime.evaluate' @{expression="getComputedStyle(document.querySelector('#z-workspace-fixture [data-desktop-window-frame]')).backgroundColor!=='rgba(0, 0, 0, 0)' && getComputedStyle(document.querySelector('#z-workspace-fixture aside')).backdropFilter==='none'";returnByValue=$true}) | ConvertFrom-Json
                    Assert $off.result.result.value 'Turning ZCode readability off left the glass layout behind'
                }
                if ($id -eq 'codex') {
                    $js = @'
(()=>{
 const main=document.querySelector('main'), composer=document.querySelector('[data-composer-surface-variant]');
 const alpha=e=>{const c=getComputedStyle(e).backgroundColor;return c.startsWith('color(')?Number(c.match(/\/\s*([\d.]+)/)?.[1]||1):Number(c.match(/rgba\([^,]+,[^,]+,[^,]+,\s*([\d.]+)/)?.[1]||1)};
 const footer=document.querySelector('[data-thread-scroll-footer]');
 const backdrop=footer.querySelector('[aria-hidden="true"]');
 const fade=document.querySelector('._fade_fixture');
 const light=alpha(main)===.5 && alpha(composer)===.88 && getComputedStyle(main).marginTop==='0px' && getComputedStyle(footer).backgroundColor==='rgba(0, 0, 0, 0)' && getComputedStyle(backdrop).backgroundColor==='rgba(0, 0, 0, 0)' && getComputedStyle(fade).backgroundImage==='none';
 document.documentElement.dataset.theme='dark';
 const dark=getComputedStyle(main).backgroundColor.includes('0.12549')||getComputedStyle(main).backgroundColor.includes('32');
 const nativeText=getComputedStyle(document.documentElement).getPropertyValue('--color-text').trim()==='#eeeeee';
 return light && dark && nativeText;
})()
'@
                    $surface = (Invoke-Cdp $ws 21 'Runtime.evaluate' @{ expression=$js; returnByValue=$true }) | ConvertFrom-Json
                    Assert ($surface.result.result.value -eq $true) 'Codex main surface remains opaque or light palette leaks into dark mode'
                    $readable = New-SkinBootstrapJs codex $pack @{ readability = $true }
                    [void](Invoke-Cdp $ws 22 'Runtime.evaluate' @{ expression=$readable; returnByValue=$true; awaitPromise=$true })
                    $contrastJs = @'
(()=>{
 const tool=document.getElementById('tool'),disabled=document.getElementById('disabled'),send=document.getElementById('send');
 const ctx=document.createElement('canvas').getContext('2d',{willReadFrequently:true});
 const pixel=(css,under,glass='transparent')=>{ctx.clearRect(0,0,1,1);ctx.fillStyle=under;ctx.fillRect(0,0,1,1);ctx.fillStyle=glass;ctx.fillRect(0,0,1,1);ctx.fillStyle=css;ctx.fillRect(0,0,1,1);return [...ctx.getImageData(0,0,1,1).data].slice(0,3)};
 const lum=rgb=>rgb.map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4}).reduce((s,x,i)=>s+x*[.2126,.7152,.0722][i],0);
 const ratios=[];
 for(const mode of ['light','dark']){
  document.documentElement.dataset.theme=mode;
  const s=getComputedStyle(tool),text=lum(pixel(s.color,'#000'));
  for(const wallpaper of ['#000','#fff']){const bg=lum(pixel(s.backgroundColor,wallpaper,getComputedStyle(tool.parentElement).backgroundColor));ratios.push((Math.max(text,bg)+.05)/(Math.min(text,bg)+.05))}
 }
 const before=getComputedStyle(tool).backgroundColor;
 const unboxed=before==='rgba(0, 0, 0, 0)' && getComputedStyle(tool).boxShadow==='none';
 tool.setAttribute('aria-pressed','true');const selected=getComputedStyle(tool).backgroundColor!==before;
 return {pass:Math.min(...ratios)>=4.5 && unboxed && getComputedStyle(disabled).opacity==='0.4' && getComputedStyle(send).backgroundColor==='rgb(20, 127, 153)' && selected,minContrast:Math.min(...ratios)};
})()
'@
                    $contrast = (Invoke-Cdp $ws 23 'Runtime.evaluate' @{ expression=$contrastJs; returnByValue=$true }) | ConvertFrom-Json
                    Assert $contrast.result.result.value.pass ('Control contrast/state check failed: ' + ($contrast.result.result.value | ConvertTo-Json -Compress))
                    [void](Invoke-Cdp $ws 24 'Runtime.evaluate' @{ expression=$scripts.codex; returnByValue=$true; awaitPromise=$true })
                    $toggle = (Invoke-Cdp $ws 25 'Runtime.evaluate' @{ expression="document.documentElement.getAttribute('data-skin-readable')==='off' && getComputedStyle(document.getElementById('tool')).backgroundColor==='rgba(0, 0, 0, 0)'"; returnByValue=$true }) | ConvertFrom-Json
                    Assert $toggle.result.result.value 'Turning readability off left the control overlay behind'
                }
                if ($id -eq 'opencode') {
                    $readable = New-SkinBootstrapJs opencode $pack @{readability=$true;syncAppearance=$false}
                    [void](Invoke-Cdp $ws 36 'Runtime.evaluate' @{expression=$readable;returnByValue=$true})
                    $ocJs = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'opencode-renderer.js'))
                    $oc = (Invoke-Cdp $ws 37 'Runtime.evaluate' @{expression=$ocJs;returnByValue=$true}) | ConvertFrom-Json
                    Assert $oc.result.result.value.pass ('OpenCode glass/contrast/state check failed: ' + ($oc.result.result.value | ConvertTo-Json -Compress))
                    # Reapplying replaces a single style, and removing it restores native surfaces.
                    [void](Invoke-Cdp $ws 38 'Runtime.evaluate' @{expression=$readable;returnByValue=$true})
                    $restoreJs = "(()=>{const single=document.querySelectorAll('#skin-studio-style').length===1;document.getElementById('skin-studio-style').remove();document.documentElement.removeAttribute('data-skin-studio');return single && getComputedStyle(document.body).backgroundImage==='none' && getComputedStyle(document.querySelector('#oc-fixture section')).backgroundColor==='rgb(255, 255, 255)' && document.documentElement.dataset.theme==='oc-2'})()"
                    $restored = (Invoke-Cdp $ws 39 'Runtime.evaluate' @{expression=$restoreJs;returnByValue=$true}) | ConvertFrom-Json
                    Assert $restored.result.result.value 'OpenCode reapplication or native style restoration failed'
                }
                # Native store / settings paths, both appearances, and opt-out.
                $setup = @"
(()=>{const app='$id';const root=document.getElementById('root');delete root.__reactContainer_fixture;
if(app==='codex'){const link=document.createElement('link');link.rel='modulepreload';link.href=new URL('./app-shared-fixture.js',location.href);document.head.appendChild(link)}
else if(app==='opencode'){document.documentElement.dataset.theme='oc-2';document.documentElement.dataset.colorScheme='dark';localStorage.setItem('opencode-color-scheme','dark');window.__fixtureNativeMode='dark';window.addEventListener('storage',e=>{if(e.key==='opencode-color-scheme')window.__fixtureNativeMode=e.newValue})}
else{window.__fixtureThemeState={theme:app==='zcode'?'zai-dark':'mc-dark',setTheme(value){this.theme=value}};root.__reactContainer`$fixture={memoizedProps:{value:{getState:()=>window.__fixtureThemeState}}}}
return true})()
"@
                [void](Invoke-Cdp $ws 40 'Runtime.evaluate' @{expression=$setup;returnByValue=$true})
                foreach ($appearance in @('light','dark')) {
                    $modePack = @{} + $pack
                    $modePack.Meta = ($pack.Meta | ConvertTo-Json -Depth 8) | ConvertFrom-Json
                    $modePack.Meta.appearance = $appearance
                    $autoJs = New-SkinBootstrapJs $id $modePack @{readability=$true;syncAppearance=$true}
                    [void](Invoke-Cdp $ws 41 'Runtime.evaluate' @{expression=$autoJs;returnByValue=$true;awaitPromise=$true})
                    $verify = @"
(()=>{const r=window.__SKIN_STUDIO_APPEARANCE;const expected=['codex','opencode'].includes('$id')?'$appearance':('$id'==='zcode'?'zai-$appearance':'mc-$appearance');const native=['codex','opencode'].includes('$id')?window.__fixtureNativeMode:window.__fixtureThemeState.theme;const oc='$id'!=='opencode'||(localStorage.getItem('opencode-color-scheme')==='$appearance'&&document.documentElement.dataset.colorScheme==='$appearance'&&document.documentElement.dataset.theme==='oc-2');return r?.applied && r.persisted && r.mode==='$appearance' && native===expected && oc})()
"@
                    $auto = (Invoke-Cdp $ws 42 'Runtime.evaluate' @{expression=$verify;returnByValue=$true}) | ConvertFrom-Json
                    Assert $auto.result.result.value ("Native appearance synchronization failed: $id/$appearance")
                }
                $modePack.Meta.appearance = 'light'
                $offJs = New-SkinBootstrapJs $id $modePack @{readability=$false;syncAppearance=$false}
                [void](Invoke-Cdp $ws 43 'Runtime.evaluate' @{expression=$offJs;returnByValue=$true;awaitPromise=$true})
                $unchanged = (Invoke-Cdp $ws 44 'Runtime.evaluate' @{expression="window.__SKIN_STUDIO_APPEARANCE.mode==='dark'";returnByValue=$true}) | ConvertFrom-Json
                Assert $unchanged.result.result.value 'Appearance opt-out changed the app mode'
                $modePack.Meta.appearance = ''
                $unknownJs = New-SkinBootstrapJs $id $modePack @{readability=$false;syncAppearance=$true}
                Assert ($unknownJs -notmatch 'await skinStudioSyncAppearance') 'Unspecified appearance should not trigger a mode change'
                . (Join-Path $PSScriptRoot 'visual-adjustments.ps1')
            } finally { Disconnect-CdpWs $ws }
        }
        . (Join-Path $PSScriptRoot 'work-pages.ps1')
        $errorInfo=@{}
        Assert (-not (Push-ThemeToTarget $target 'throw Error("fixture failure")' (Join-Path $temp 'cdp.log') $errorInfo)) 'JS exceptions reported as successful injection'
        Assert ($errorInfo.message -match 'fixture failure' -and $errorInfo.message -notmatch '^\{"id"') 'Script failure did not expose a readable cause'
    } finally {
        $browser.Refresh()
        if (-not $browser.HasExited) { Stop-Process -InputObject $browser -Force }
        $browser.Dispose()
    }
    Write-Host 'PASS: parsing, config/favorites/visual isolation, thumbnail decode/cache, import, target filtering, endpoint identity, real Chromium injection and error reporting.'
} finally {
    $full = [IO.Path]::GetFullPath($temp)
    if ($full.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $full -Leaf) -like 'SkinStudio-test-*') {
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
    }
}

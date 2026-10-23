# Operation stages and read-only application health. Windows PowerShell 5.1.
function Throw-SkinOperationError([string]$Code, [string]$Detail) {
    $errorObject = New-Object InvalidOperationException($Detail)
    $errorObject.Data['SkinCode'] = $Code
    throw $errorObject
}

function Get-SkinApplicationState {
    param([string]$Application, [string]$AppExe, [int]$Port, [switch]$Discover)
    try {
        if ($Discover -or -not (Test-SkinDesktopExe $Application $AppExe)) { $AppExe = Resolve-SkinAppExe $Application $AppExe }
        if (-not (Test-SkinDesktopExe $Application $AppExe)) { return @{state='missing';exe='';reason='not_found';port=$Port} }
        if (Test-SkinAppAccessDenied $Application $AppExe) { return @{state='unknown';exe=$AppExe;reason='process_access_denied';port=$Port} }
        if (-not @(Get-SkinAppProcesses $AppExe).Count) { return @{state='stopped';exe=$AppExe;reason='not_running';port=$Port} }
        if (-not (Test-SkinCdpOwner $Application $AppExe $Port)) {
            $reason = if (@(Get-SkinPortListeners $Port).Count) { 'port_busy' } else { 'debug_disabled' }
            return @{state='restart';exe=$AppExe;reason=$reason;port=$Port}
        }
        if (-not @(Get-SkinTargets $Application $AppExe $Port).Count) { return @{state='restart';exe=$AppExe;reason='no_renderer';port=$Port} }
        return @{state='connected';exe=$AppExe;reason='ready';port=$Port}
    } catch { return @{state='unknown';exe=$AppExe;reason=$_.Exception.Message;port=$Port} }
}

function Test-TargetSkinEffect {
    param($Target, [string]$Application, [string]$Marker, [bool]$HasWallpaper)
    $ws = $null
    try {
        $appJson = $Application | ConvertTo-Json -Compress
        $markerJson = $Marker | ConvertTo-Json -Compress
        $wallpaperJson = $HasWallpaper.ToString().ToLowerInvariant()
        $expression = @"
(async()=>{
 const app=$appJson,expected=$markerJson;
 const marker=window.__SKIN_STUDIO||window.__ZC_SKIN||'';
 const style=document.getElementById(app==='zcode'?'zc-skin-style':'skin-studio-style');
 if(marker!==expected)return {ok:false,reason:'theme_marker_mismatch'};
 if(!style||!style.isConnected||!style.sheet||style.sheet.disabled||!style.textContent.trim())return {ok:false,reason:'style_missing'};
 if($wallpaperJson){
   const surface=app==='zcode'?document.getElementById('root'):app==='monkeycode'?document.querySelector('.mc-workbench-background'):document.body;
   if(!surface)return {ok:false,reason:'wallpaper_surface_missing'};
   const bg=getComputedStyle(surface).backgroundImage;
   const url=bg.match(/url\(["']?(data:image\/[^"')]+)["']?\)/);
   if(!url)return {ok:false,reason:'wallpaper_not_applied'};
   const loaded=await new Promise(resolve=>{const image=new Image();const timer=setTimeout(()=>resolve(false),4000);image.onload=()=>{clearTimeout(timer);resolve(image.naturalWidth>0)};image.onerror=()=>{clearTimeout(timer);resolve(false)};image.src=url[1]});
   if(!loaded)return {ok:false,reason:'wallpaper_decode_failed'};
 }
 return {ok:true,reason:'verified'};
})()
"@
        $ws = Connect-CdpWs $Target.webSocketDebuggerUrl
        $response = (Invoke-Cdp $ws 71 'Runtime.evaluate' @{expression=$expression;returnByValue=$true;awaitPromise=$true} -TimeoutMs 6000) | ConvertFrom-Json
        if ($response.error -or $response.result.exceptionDetails) { return @{ok=$false;reason='verification_script_failed'} }
        $value = $response.result.result.value
        if ($null -eq $value -or -not $value.ok) { return @{ok=$false;reason=([string]$value.reason)} }
        return @{ok=$true;reason='verified'}
    } catch { return @{ok=$false;reason=$_.Exception.Message} }
    finally { if ($ws) { Disconnect-CdpWs $ws } }
}

function Invoke-SkinOperation {
    param([string]$Application, [string]$AppExe, [int]$Port, [string]$ThemeDir, [string]$LogPath, [switch]$Restore, $Options, [scriptblock]$Progress, [int]$ConnectionTimeoutSec = 40)
    $stage = 'launch'
    $report = {
        param([string]$Phase, [string]$Detail)
        $event = @{stage=$Phase;detail=$Detail;time=[DateTime]::UtcNow}
        if ($LogPath) { Write-ZcLog -Path $LogPath -Message ("OPERATION $Application [$Phase] $Detail") -NoHost }
        if ($Progress) { [void](& $Progress $event) }
    }
    try {
        & $report 'launch' 'checking'
        if (-not (Test-SkinDesktopExe $Application $AppExe)) { Throw-SkinOperationError 'APP_NOT_FOUND' ('Desktop executable not found or invalid: ' + $AppExe) }
        if (Test-SkinAppAccessDenied $Application $AppExe) { Throw-SkinOperationError 'APP_ACCESS_DENIED' 'WorkBuddy process access denied. Run SkinStudio and WorkBuddy at the same privilege level.' }
        if (-not $Restore) {
            try { $pack=Get-ThemePack $ThemeDir; $js=New-SkinBootstrapJs $Application $pack $Options }
            catch { Throw-SkinOperationError 'THEME_INVALID' $_.Exception.Message }
        }
        $owned = Test-SkinCdpOwner $Application $AppExe $Port
        if (-not $Restore -and -not $owned -and @(Get-SkinPortListeners $Port).Count) { Throw-SkinOperationError 'PORT_BUSY' ("Port $Port is occupied by another process. Select another port.") }
        if ($Restore -or -not $owned) {
            $detail = if ($Restore) { 'official' } elseif (@(Get-SkinAppProcesses $AppExe).Count) { 'restarting' } else { 'starting' }
            & $report 'launch' $detail
            try { Stop-SkinApp $Application $AppExe; [void](Start-SkinApp $Application $AppExe $Port -Official:$Restore) }
            catch { Throw-SkinOperationError 'START_FAILED' $_.Exception.Message }
        } else { & $report 'launch' 'reused' }
        $stage = 'connect'; & $report 'connect' $(if ($Restore) { 'official' } else { 'renderer' })
        $deadline = (Get-Date).AddSeconds($ConnectionTimeoutSec)
        $targets = @(); $lastConnectionError = ''
        do {
            if ($Restore) {
                if (@(Get-SkinAppProcesses $AppExe).Count) {
                    & $report 'apply' 'official'; & $report 'verify' 'official'
                    if ($LogPath) { Write-ZcLog -Path $LogPath -Message ("OPERATION $Application COMPLETED: official process running") -NoHost }
                    return @{ok=$true;message='OK_OFFICIAL';stage='verify';targets=0}
                }
            } else {
                try { $targets=@(Get-SkinTargets $Application $AppExe $Port) } catch { $lastConnectionError=$_.Exception.Message }
                if ($targets.Count -and $Application -eq 'workbuddy') {
                    $notReady=@($targets | Where-Object { -not (Test-WorkBuddyTargetReady $_) })
                    if ($notReady.Count) {
                        $lastConnectionError='WorkBuddy renderer is still initializing; waiting for the app UI.'
                        $targets=@()
                    }
                }
                if ($targets.Count) { break }
            }
            if ((Get-Date) -ge $deadline) { break }
            Start-Sleep -Milliseconds 600
        } while ((Get-Date) -lt $deadline)
        if (-not $targets.Count) {
            $code = if ($Restore) { 'START_FAILED' } else { 'CONNECTION_TIMEOUT' }
            Throw-SkinOperationError $code ("No compatible $Application renderer after $ConnectionTimeoutSec seconds on port $Port. $lastConnectionError")
        }
        $stage='apply'; & $report 'apply' 'injecting'
        $applied=@(); $failures=@()
        foreach ($target in $targets) {
            $diagnostic=@{}
            if (Push-ThemeToTarget $target $js $LogPath $diagnostic) { $applied += $target }
            else { $failures += ([string]$target.id + ': ' + $diagnostic.message) }
        }
        if (-not $applied.Count) { Throw-SkinOperationError 'APPLY_FAILED' ($failures -join '; ') }
        $stage='verify'; & $report 'verify' 'checking_style'
        $expected=Get-SkinMarker $pack $Options $Application; $verified=0
        foreach ($target in $applied) {
            $check=Test-TargetSkinEffect $target $Application $expected ([bool]$pack.BgPath)
            if ($check.ok) { $verified++ } else { $failures += ([string]$target.id + ': ' + $check.reason) }
        }
        if ($verified -ne $targets.Count) { Throw-SkinOperationError 'VERIFY_FAILED' ("Verified $verified/$($targets.Count) pages. " + ($failures -join '; ')) }
        if ($LogPath) { Write-ZcLog -Path $LogPath -Message ("OPERATION $Application COMPLETED: $verified pages verified") -NoHost }
        return @{ok=$true;message="OK:$verified";stage='verify';targets=$verified}
    } catch {
        $code = [string]$_.Exception.Data['SkinCode']
        if (-not $code) { $code='UNEXPECTED' }
        if ($LogPath) { Write-ZcLog -Path $LogPath -Message ("OPERATION $Application FAILED [$stage/$code] " + $_.Exception.Message) -NoHost }
        # Keep CLI callers' throwing contract, with structured information for the UI.
        $_.Exception.Data['SkinCode']=$code; $_.Exception.Data['SkinStage']=$stage
        throw
    }
}

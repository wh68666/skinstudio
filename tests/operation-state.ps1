# Exercise orchestration with isolated process/transport doubles. Never launch user apps.
& {
    . (Join-Path $root 'skin-lib.ps1')
    $probe=@{owned=$true;running=$true;listeners=$false;targets=$true;push=$true;verify=$true;starts=0;stops=0;invalid=$false;launchError=$false;official=$false}
    function Test-SkinDesktopExe { param($Application,$Path) return -not $probe.invalid }
    function Resolve-SkinAppExe { param($Application,$Configured) return 'fixture.exe' }
    function Test-SkinCdpOwner { param($Application,$AppExe,$Port) return $probe.owned }
    function Get-SkinPortListeners { param($Port) if ($probe.listeners) { return @{OwningProcess=999} }; return @() }
    function Get-SkinAppProcesses { param($AppExe) if ($probe.running) { return @{Id=1} }; return @() }
    function Get-SkinTargets { param($Application,$AppExe,$Port) if ($probe.targets) { return @{id='fixture';webSocketDebuggerUrl='fixture'} }; return @() }
    function Get-ThemePack { param($ThemeDir) return @{Meta=@{id='fixture';version='1'};Version='1';BgPath='fixture.jpg'} }
    function New-SkinBootstrapJs { param($Application,$ThemePack,$Options) return 'fixture-js' }
    function Stop-SkinApp { param($Application,$AppExe) $probe.stops++ }
    function Start-SkinApp { param($Application,$AppExe,$Port,[switch]$Official) if ($probe.launchError) { throw 'fixture access denied' }; $probe.starts++; $probe.running=$true; $probe.official=[bool]$Official }
    function Push-ThemeToTarget { param($Target,$BootstrapJs,$LogPath,$ErrorInfo) $ErrorInfo.message='fixture script error'; return $probe.push }
    function Test-TargetSkinEffect { param($Target,$Application,$Marker,$HasWallpaper) return @{ok=$probe.verify;reason='fixture style missing'} }
    function Test-SkinAppAccessDenied { param($Application,$AppExe) return $Application -eq 'workbuddy' -and [bool]$probe.accessDenied }
    function Test-WorkBuddyTargetReady { param($Target) return [bool]$probe.rendererReady }
    $spec=@{Application='codex';AppExe='fixture.exe';Port=19223;ThemeDir='fixture';LogPath=(Join-Path $temp 'operation.log');Options=@{};ConnectionTimeoutSec=0}
    $events=New-Object 'Collections.Generic.List[object]'
    $spec.Progress={param($event) $events.Add($event)}
    $result=Invoke-SkinOperation @spec
    Assert ($result.ok -and $result.targets -eq 1 -and $probe.starts -eq 0 -and $probe.stops -eq 0) 'Connected operation restarted an app'
    Assert (($events.stage -join ',') -eq 'launch,launch,connect,apply,verify') 'Actual operation stages are out of order'
    Assert ($events[1].detail -eq 'reused') 'Already connected launch was not marked skipped'
    $probe.owned=$false; $probe.running=$false
    $result=Invoke-SkinOperation @spec
    Assert ($result.ok -and $probe.starts -eq 1) 'Stopped app was not launched'
    $probe.owned=$true
    $result=Invoke-SkinOperation @spec -Restore
    Assert ($result.ok -and $probe.official -and $probe.starts -eq 2) 'Official restore did not verify a normal launch'
    foreach ($case in @(
        @{code='APP_NOT_FOUND';key='invalid';value=$true},
        @{code='PORT_BUSY';key='listeners';value=$true},
        @{code='START_FAILED';key='launchError';value=$true},
        @{code='CONNECTION_TIMEOUT';key='targets';value=$false},
        @{code='APPLY_FAILED';key='push';value=$false},
        @{code='VERIFY_FAILED';key='verify';value=$false}
    )) {
        $probe.invalid=$false; $probe.listeners=$false; $probe.launchError=$false; $probe.targets=$true; $probe.push=$true; $probe.verify=$true; $probe.owned=$false
        $probe[$case.key]=$case.value
        $before=$probe.starts; $caught=$null
        try { Invoke-SkinOperation @spec | Out-Null } catch { $caught=$_ }
        Assert ($caught -and $caught.Exception.Data['SkinCode'] -eq $case.code) ('Operation returned wrong failure: '+$case.code+' / '+$caught)
        Assert ([bool]$caught.Exception.Data['SkinStage']) 'Failure has no stage'
        if ($case.code -eq 'PORT_BUSY') { Assert ($probe.starts -eq $before) 'Port collision launched an app' }
    }
    $probe.invalid=$false; $probe.listeners=$false; $probe.launchError=$false; $probe.targets=$true; $probe.owned=$false
    foreach ($case in @(@{state='missing';invalid=$true;running=$false;owned=$false},@{state='stopped';invalid=$false;running=$false;owned=$false},@{state='restart';invalid=$false;running=$true;owned=$false},@{state='connected';invalid=$false;running=$true;owned=$true})) {
        $probe.invalid=$case.invalid; $probe.running=$case.running; $probe.owned=$case.owned
        $health=Get-SkinApplicationState codex 'fixture.exe' 19223
        Assert ($health.state -eq $case.state) ('Application state incorrect: '+$case.state)
    }
    $probe.invalid=$false;$probe.running=$true;$probe.owned=$true;$probe.targets=$true;$probe.verify=$true;$probe.push=$true
    $spec.Application='workbuddy';$probe.rendererReady=$false;$before=$probe.starts;$caught=$null
    try { Invoke-SkinOperation @spec | Out-Null } catch { $caught=$_ }
    Assert ($caught.Exception.Data['SkinCode'] -eq 'CONNECTION_TIMEOUT' -and $caught.Exception.Data['SkinStage'] -eq 'connect' -and $probe.starts -eq $before) 'Pending WorkBuddy page was injected or reported an apply failure'
    $probe.rendererReady=$true
    Assert (Invoke-SkinOperation @spec).ok 'Initialized WorkBuddy page did not pass the connection barrier'
    $probe.accessDenied=$true
    Assert ((Get-SkinApplicationState workbuddy 'fixture.exe' 19223).reason -eq 'process_access_denied') 'Elevated WorkBuddy was shown stopped'
    $spec.Application='workbuddy';$before=$probe.starts;$beforeStops=$probe.stops;$caught=$null
    try { Invoke-SkinOperation @spec | Out-Null } catch { $caught=$_ }
    Assert ($caught.Exception.Data['SkinCode'] -eq 'APP_ACCESS_DENIED' -and $probe.starts -eq $before -and $probe.stops -eq $beforeStops) 'Inaccessible WorkBuddy was restarted or returned an unclear error'
    $spec.Application='codex';$probe.accessDenied=$false
    $probe.targets=$false
    Assert ((Get-SkinApplicationState codex 'fixture.exe' 19223).state -eq 'restart') 'A port without a compatible page was shown connected'
    function Test-SkinDesktopExe { param($Application,$Path) return $Path -eq 'fixture.exe' }
    Assert ((Get-SkinApplicationState codex 'removed-version.exe' 19223).exe -eq 'fixture.exe') 'App update left status polling an obsolete executable'
}

# Standalone watcher follows the selected app's saved profile.
param([ValidateSet('zcode','monkeycode','codex','opencode')][string]$Application = 'zcode',[string]$DataDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cli-context.ps1')
$mutex = New-Object Threading.Mutex($false, ('Local\SkinStudioInjector-' + $Application))
if (-not $mutex.WaitOne(0)) { return }
try {
    $log = Join-Path $DataRoot ('logs\' + $Application + '-injector.log')
    $cachedTheme = ''; $js = ''; $marker = ''
    while ($true) {
        $settings = Read-SkinSettings (Join-Path $DataRoot 'config.json')
        $profile = $settings.apps[$Application]
        if (-not $profile.currentTheme -or -not $profile.appExe -or -not @(Get-SkinAppProcesses $profile.appExe).Count) { break }
        try {
            $pack = Get-ThemePack (Join-Path (Join-Path $DataRoot 'themes') $profile.currentTheme)
            $nextMarker = Get-SkinMarker $pack $profile
            if ($cachedTheme -ne $nextMarker) { $js = New-SkinBootstrapJs $Application $pack $profile; $marker = $nextMarker; $cachedTheme = $nextMarker }
            foreach ($target in @(Get-SkinTargets $Application $profile.appExe $profile.port)) {
                if ((Get-TargetSkinMarker $target) -ne $marker) { [void](Push-ThemeToTarget $target $js $log) }
            }
        } catch { Write-ZcLog -Path $log -Message $_.Exception.Message }
        Start-Sleep -Seconds 5
    }
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }

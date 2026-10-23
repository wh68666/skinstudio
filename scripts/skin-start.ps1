# Unified launcher. Existing commands default to ZCode.
param(
    [ValidateSet('zcode','monkeycode','codex','opencode')][string]$Application = 'zcode',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$Theme = 'aurora',
    [int]$Port = 0,
    [switch]$Force,
    [string]$AppExe = '',
    [string]$DataDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cli-context.ps1')
$cfgPath = Join-Path $DataRoot 'config.json'
$settings = Read-SkinSettings $cfgPath
$profile = $settings.apps[$Application]
if (-not $Port) { $Port = $profile.port }
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be 1024-65535' }
foreach ($id in $script:SkinApps.Keys) {
    if ($id -ne $Application -and $settings.apps[$id].port -eq $Port) { throw "Port $Port is assigned to $id" }
}
if (-not $AppExe) { $AppExe = Resolve-SkinAppExe $Application $profile.appExe }
if (-not $AppExe) { throw "$Application desktop app not found. Configure it in SkinStudio." }
[void](New-Item (Join-Path $DataRoot 'logs') -ItemType Directory -Force)
$log = Join-Path $DataRoot ('logs\' + $Application + '-launcher.log')
$themesRoot = Join-Path $DataRoot 'themes'
$imports = Join-Path $DataRoot 'imports'
if (Test-Path -LiteralPath $imports) {
    foreach ($zip in @(Get-ChildItem -LiteralPath $imports -Filter *.zip -File)) {
        $result = Import-CodexThemePack -ZipPath $zip.FullName -ThemesRoot $themesRoot
        $done = Join-Path $imports 'done'
        [void](New-Item $done -ItemType Directory -Force)
        Move-Item -LiteralPath $zip.FullName -Destination (Join-Path $done $zip.Name) -Force
        Write-Host ('Imported: ' + $result.Id)
    }
}
if ((Get-SkinAppProcesses $AppExe).Count -and -not (Test-SkinCdpOwner $Application $AppExe $Port) -and -not $Force) {
    $answer = Read-Host "$Application needs a restart. Save your work first. Continue? (y/N)"
    if ($answer -notmatch '^[Yy]$') { return }
}
$result = Invoke-SkinOperation -Application $Application -AppExe $AppExe -Port $Port -ThemeDir (Join-Path $themesRoot $Theme) -LogPath $log -Options (Get-SkinThemeOptions $profile $Theme -Default)
$profile.activeVisual = $null
$profile.appExe = $AppExe; $profile.port = $Port; $profile.currentTheme = $Theme
$settings.activeApp = $Application
Write-SkinSettings $cfgPath $settings
Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'skin-injector.ps1') + '"'), '-Application', $Application, '-DataDirectory', ('"'+$DataRoot+'"')) -WindowStyle Hidden
Write-Host "$Application skin active: $Theme ($($result.message))"

# Restore one application without changing other applications' skins.
param(
    [ValidateSet('zcode','monkeycode','codex','opencode')][string]$Application = 'zcode',
    [string]$AppExe = '',
    [string]$DataDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cli-context.ps1')
$path = Join-Path $DataRoot 'config.json'
$settings = Read-SkinSettings $path
$profile = $settings.apps[$Application]
if (-not $AppExe) { $AppExe = Resolve-SkinAppExe $Application $profile.appExe }
if (-not $AppExe) { throw "$Application desktop app not found" }
$profile.currentTheme = ''
$profile.activeVisual = $null
Write-SkinSettings $path $settings
Stop-SkinApp $Application $AppExe
[void](Start-SkinApp $Application $AppExe -Official)
Write-Host "$Application restored to official appearance."

# skin-import.ps1 - import a Codex Dream Skin theme zip into themes\ (ASCII only)
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-import.ps1 -Zip <path.zip> [-Force]
param(
    [Parameter(Mandatory)][string]$Zip,
    [switch]$Force,
    [string]$DataDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cli-context.ps1')

try {
    $r = Import-CodexThemePack -ZipPath $Zip -ThemesRoot (Join-Path $DataRoot 'themes') -Force:$Force
} catch {
    Write-Host ("IMPORT FAILED: " + $_.Exception.Message)
    exit 1
}

Write-Host ("Imported theme id : " + $r.Id)
Write-Host ("Name              : " + $r.Name)
Write-Host ("Directory         : " + $r.Dir)
Write-Host ("Manifest verified : " + $r.Verified)
if ($r.License) { Write-Host ("License           : " + $r.License) }
Write-Host ("Surface opacity   : " + $r.SurfaceOpacity)
Write-Host ""
Write-Host ('Apply it: powershell -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'skin-start.ps1')+'" -Theme '+$r.Id+' -DataDirectory "'+$DataRoot+'"')

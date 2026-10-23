# Shared CLI paths. Source and packaged GUI use the same user data unless overridden.
$ProjectRoot=Split-Path $PSScriptRoot
$SourceRoot=Join-Path $ProjectRoot 'src'
. (Join-Path $SourceRoot 'skin-lib.ps1')
. (Join-Path $SourceRoot 'skin-storage.ps1')
if(-not $DataDirectory){$DataDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SkinStudio\data'}
$DataRoot=Initialize-SkinDataDirectory $DataDirectory (Join-Path $ProjectRoot 'resources') (Join-Path $ProjectRoot 'data\legacy')

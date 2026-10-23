# Source entry point. SelfTest uses isolated build data; normal runs share desktop settings.
param([switch]$SelfTest,[string]$DataDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if($SelfTest -and -not $DataDirectory){$DataDirectory=Join-Path $root 'build\selftest-data'}
. (Join-Path $root 'src\SkinStudio.app.ps1') -SelfTest:$SelfTest -DataDirectory $DataDirectory

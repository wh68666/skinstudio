# Build one directly runnable EXE. No archive is generated for distribution.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$src=[IO.File]::ReadAllText((Join-Path $root 'src\SkinStudio.app.ps1'))
if($src -notmatch '\$script:AppVersion\s*=\s*''([^'']+)'''){throw 'Missing AppVersion'}
$version=$Matches[1]
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build.ps1')
if($LASTEXITCODE -ne 0){throw 'Build failed'}
$release=Join-Path $root 'dist'
[void][IO.Directory]::CreateDirectory($release)
$exe=Join-Path $release ('SkinStudio-v'+$version+'.exe')
Copy-Item -LiteralPath (Join-Path $root 'build\SkinStudio.exe') -Destination $exe -Force
'EXE: '+$exe

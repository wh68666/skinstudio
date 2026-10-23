# Single-file distribution. The ZIP is a convenience wrapper containing one EXE.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$src=[IO.File]::ReadAllText((Join-Path $root 'SkinStudio.app.ps1'))
if($src -notmatch '\$script:AppVersion\s*=\s*''([^'']+)'''){throw 'Missing AppVersion'}
$version=$Matches[1]
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'app\build.ps1')
if($LASTEXITCODE -ne 0){throw 'Build failed'}
$release=Join-Path $root 'release'
[void][IO.Directory]::CreateDirectory($release)
$exe=Join-Path $release ('SkinStudio-v'+$version+'.exe')
Copy-Item -LiteralPath (Join-Path $root 'SkinStudio.exe') -Destination $exe -Force
Compress-Archive -LiteralPath (Join-Path $root 'SkinStudio.exe') -DestinationPath (Join-Path $release ('SkinStudio-v'+$version+'.zip')) -Force
'EXE: '+$exe
'ZIP: '+(Join-Path $release ('SkinStudio-v'+$version+'.zip'))
# build.ps1 - build SkinStudio.exe with ps2exe (run in PowerShell 5.1)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
Set-Location $root

# 1. icon
Add-Type -AssemblyName System.Drawing
$icoPath = Join-Path $root 'resources\icons\skin-studio.ico'
if (-not (Test-Path $icoPath)) {
    $bmp = New-Object System.Drawing.Bitmap(64, 64)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(64, 64)), [System.Drawing.Color]::FromArgb(255, 34, 38, 68), [System.Drawing.Color]::FromArgb(255, 130, 92, 255))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, 64, 64, 180, 180)
    $path.AddArc(0, 0, 64, 64, 0, 180)
    $g.FillPath($brush, $path)
    $g.DrawString('S', (New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, 14, 8)
    $g.Dispose()
    $ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $fs = [IO.File]::Create($icoPath)
    $ico.Save($fs)
    $fs.Dispose()
    'icon created: ' + $icoPath
}

# 2. ps2exe module
if (-not (Get-Module -ListAvailable ps2exe)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null } catch { }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module ps2exe -Scope CurrentUser -Force
    Import-Module ps2exe
} else {
    Import-Module ps2exe
}

# 3. Package all runtime files, then compile a single-file launcher.
$out = Join-Path $root 'build\SkinStudio.exe'
$source = Get-Content (Join-Path $root 'src\SkinStudio.app.ps1') -Raw -Encoding UTF8
if ($source -notmatch '\$script:AppVersion\s*=\s*''([^'']+)''') { throw 'Missing AppVersion' }
$fileVersion = $Matches[1] + '.0'
$buildRoot=Join-Path $root 'build\intermediate'
[void][IO.Directory]::CreateDirectory($buildRoot)
$stage=Join-Path $buildRoot ('single-build-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
try {
    . (Join-Path $root 'packaging\package-files.ps1')
    foreach($name in $PackageFiles.Keys){$target=Join-Path $stage $PackageFiles[$name];[void][IO.Directory]::CreateDirectory((Split-Path $target));Copy-Item -LiteralPath (Join-Path $root $name) -Destination $target}
    [void][IO.Directory]::CreateDirectory((Join-Path $stage 'themes'))
    Copy-Item -LiteralPath (Join-Path $root 'resources\themes\aurora') -Destination (Join-Path $stage 'themes') -Recurse
    $payload=Join-Path $buildRoot ('payload-'+[guid]::NewGuid().ToString('N')+'.zip')
    try {
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payload
        $hash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()
        $launcher=[IO.File]::ReadAllText((Join-Path $root 'packaging\launcher.ps1')).Replace('__SKINSTUDIO_PAYLOAD__',[Convert]::ToBase64String([IO.File]::ReadAllBytes($payload))).Replace('__SKINSTUDIO_PACKAGE_HASH__',$hash)
        $generated=Join-Path $buildRoot 'single-launcher.ps1'
        [IO.File]::WriteAllText($generated,$launcher,[Text.UTF8Encoding]::new($true))
        Invoke-ps2exe -inputFile $generated -outputFile $out -noConsole -STA -iconFile $icoPath -title 'SkinStudio' -description 'ZCode, MonkeyCode, Codex and OpenCode desktop theme manager' -version $fileVersion | Out-Null
    }finally{if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload}}
}finally{
    $resolved=[IO.Path]::GetFullPath($stage)
    if($resolved.StartsWith([IO.Path]::GetFullPath($buildRoot).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'single-build-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if (Test-Path $out) { 'BUILT: ' + $out + ' (' + [math]::Round((Get-Item $out).Length / 1KB) + ' KB)' } else { 'BUILD FAILED' }

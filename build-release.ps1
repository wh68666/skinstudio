# Build a portable Windows release without user data.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src = Get-Content (Join-Path $root 'SkinStudio.app.ps1') -Raw -Encoding UTF8
if ($src -notmatch '\$script:AppVersion\s*=\s*''([^'']+)''') { throw 'Missing AppVersion' }
$version = $Matches[1]
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'app\build.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
$release = Join-Path $root 'release'
[void](New-Item $release -ItemType Directory -Force)
$stage = Join-Path $release ('stage-' + [guid]::NewGuid().ToString('N'))
[void](New-Item $stage -ItemType Directory)
try {
    foreach ($name in @('SkinStudio.exe','SkinStudio.app.ps1','ZCodeSkin.app.ps1','skin-lib.ps1','skin-platforms.ps1','skin-operation.ps1','skin-status-ui.ps1','skin-opencode.ps1','skin-visuals.ps1','skin-visual-ui.ps1','skin-theme-browser.ps1','skin-thumbnails.ps1','theme-cards.xaml','skin-appearance.js','skin-start.ps1','skin-clear.ps1','skin-injector.ps1','skin-import.ps1','README.md','THIRD_PARTY_NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $stage
    }
    [void](New-Item (Join-Path $stage 'themes') -ItemType Directory)
    Copy-Item -LiteralPath (Join-Path $root 'RELEASE_NOTES.md') -Destination $stage
    foreach($name in @('skin-manager-theme.ps1','skin-manager-theme.xaml')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $stage}
    foreach($name in @('skin-compatibility.ps1','skin-compatibility-ui.ps1','skin-workpage-audit.js','compatibility-baseline.json','COMPATIBILITY.md')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $stage}
    if (Test-Path -LiteralPath (Join-Path $root 'themes\aurora')) {
        Copy-Item -LiteralPath (Join-Path $root 'themes\aurora') -Destination (Join-Path $stage 'themes') -Recurse
    } else {
        # The user can delete the bundled theme from their library; package the repository copy.
        $builtin=Join-Path $stage 'builtin.zip'
        & git -C $root archive --format=zip --output=$builtin HEAD themes/aurora
        if ($LASTEXITCODE -ne 0) { throw 'Bundled Aurora theme unavailable' }
        Expand-Archive -LiteralPath $builtin -DestinationPath $stage -Force
        Remove-Item -LiteralPath $builtin
    }
    $zip = Join-Path $release ('SkinStudio-v' + $version + '.zip')
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
    Write-Host ('RELEASE ZIP: ' + $zip)
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($release).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

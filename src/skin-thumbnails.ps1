# Bounded wallpaper thumbnail decode/download. No UI state is required here.
function Read-ThemeThumbnail([string]$Path) {
    Add-Type -AssemblyName PresentationCore,WindowsBase
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnDemand)
        $frame = $decoder.Frames[0]
        if ([double]$frame.PixelWidth * $frame.PixelHeight -gt 100000000) { throw 'Wallpaper dimensions exceed preview limits' }
        $width = [Math]::Max(1,[int]([Math]::Min(1.0,[Math]::Min(320.0/$frame.PixelWidth,240.0/$frame.PixelHeight)) * $frame.PixelWidth))
        $stream.Position = 0
        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit(); $bitmap.CacheOption = 'OnLoad'; $bitmap.DecodePixelWidth = $width; $bitmap.StreamSource = $stream; $bitmap.EndInit(); $bitmap.Freeze()
        return $bitmap
    } finally { $stream.Dispose() }
}

function Get-RemoteThemeThumbnail([string]$VersionId, [string]$CacheDir) {
    if ($VersionId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid gallery version ID' }
    [void](New-Item -ItemType Directory -Path $CacheDir -Force)
    $cache = Join-Path $CacheDir ($VersionId + '-v1.jpg')
    if (Test-Path -LiteralPath $cache -PathType Leaf) {
        try { return Read-ThemeThumbnail $cache } catch { Remove-Item -LiteralPath $cache -Force }
    }
    $temp = Join-Path $CacheDir ([guid]::NewGuid().ToString('N') + '.download')
    $encoded = $temp + '.jpg'
    $response = $null; $network = $null; $file = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $request = [Net.HttpWebRequest]::Create('https://api.dreamskin.cc/v1/themes/' + [Uri]::EscapeDataString($VersionId) + '/preview/background')
        $request.Timeout = 7000; $request.ReadWriteTimeout = 5000; $request.AllowAutoRedirect = $false; $request.UserAgent = 'SkinStudio'
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200 -or $response.ContentType -notmatch '^image/(jpeg|png|webp)(?:;|$)' -or $response.ContentLength -gt 12MB) { throw 'Unsupported preview response' }
        $network = $response.GetResponseStream(); $file = [IO.File]::Create($temp)
        $buffer = New-Object byte[] 16384; $total = 0; $timer = [Diagnostics.Stopwatch]::StartNew()
        while (($count = $network.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if ($total -gt 12MB -or $timer.Elapsed.TotalSeconds -gt 15) { throw 'Preview download exceeded limits' }
            $file.Write($buffer,0,$count)
        }
        $file.Dispose(); $file = $null
        $bitmap = Read-ThemeThumbnail $temp
        $encoder = New-Object Windows.Media.Imaging.JpegBitmapEncoder
        $encoder.QualityLevel = 82; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $file = [IO.File]::Create($encoded); $encoder.Save($file); $file.Dispose(); $file = $null
        Move-Item -LiteralPath $encoded -Destination $cache -Force
        return $bitmap
    } finally {
        if ($file) { $file.Dispose() }; if ($network) { $network.Dispose() }; if ($response) { $response.Dispose() }
        foreach ($path in @($temp,$encoded)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
    }
}

$script:ThemeThumbnailWorker = {
    param($spec)
    try {
        . $spec.Module
        $bitmap = if ($spec.Remote) { Get-RemoteThemeThumbnail $spec.Id $spec.CacheDir } else { Read-ThemeThumbnail $spec.Path }
        return @{ ok = $true; key = $spec.Key; bitmap = $bitmap }
    } catch { return @{ ok = $false; key = $spec.Key; message = $_.Exception.Message } }
}

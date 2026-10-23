# Compiled single-file entry point. Payload and hashes are inserted only at build time.
param([switch]$SelfTest,[string]$DataDirectory)
$ErrorActionPreference='Stop'
try {
    try {Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop}catch{}
    $packageBytes=[Convert]::FromBase64String('__SKINSTUDIO_PAYLOAD__')
    $packageHash='__SKINSTUDIO_PACKAGE_HASH__'
    $local=[Environment]::GetFolderPath('LocalApplicationData')
    if(-not $DataDirectory){$DataDirectory=Join-Path $local 'SkinStudio\data'}
    $DataDirectory=[IO.Path]::GetFullPath($DataDirectory)
    $runtimeRoot=Join-Path $local 'SkinStudio\runtime'
    $runtime=Join-Path $runtimeRoot $packageHash
    Add-Type -AssemblyName System.IO.Compression
    $lock=New-Object Threading.Mutex($false,('Local\SkinStudioPayload-'+$packageHash))
    $locked=$false;$archive=$null;$memory=$null
    try {
        try {$locked=$lock.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Another instance is preparing SkinStudio. Try again shortly.'}
        $memory=[IO.MemoryStream]::new($packageBytes,$false)
        $archive=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Read)
        foreach($entry in $archive.Entries) {
            if(-not $entry.Name){continue}
            $path=[IO.Path]::GetFullPath((Join-Path $runtime $entry.FullName))
            if(-not $path.StartsWith($runtime.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid embedded resource path'}
            $stream=$entry.Open();$buffer=New-Object IO.MemoryStream
            try {$stream.CopyTo($buffer);$expected=$buffer.ToArray()}finally{$buffer.Dispose();$stream.Dispose()}
            $valid=$false;$sha=[Security.Cryptography.SHA256]::Create()
            try {
                if([IO.File]::Exists($path)){
                    $existing=[IO.File]::OpenRead($path)
                    try{$actualHash=[BitConverter]::ToString($sha.ComputeHash($existing))}finally{$existing.Dispose()}
                    $valid=$actualHash -eq [BitConverter]::ToString($sha.ComputeHash($expected))
                }
            } finally {$sha.Dispose()}
            if(-not $valid){
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
                $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
                [IO.File]::WriteAllBytes($temp,$expected)
                if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}
            }
        }
    } finally {
        if($archive){$archive.Dispose()};if($memory){$memory.Dispose()}
        if($locked){$lock.ReleaseMutex()};$lock.Dispose()
    }
    $exeDirectory=[AppDomain]::CurrentDomain.BaseDirectory
    $previousError=Join-Path $DataDirectory 'startup-error.txt'
    if(Test-Path -LiteralPath $previousError){Remove-Item -LiteralPath $previousError -Force}
    . (Join-Path $runtime 'SkinStudio.app.ps1') -SelfTest:$SelfTest -DataDirectory $DataDirectory -LegacyDirectory $exeDirectory
} catch {
    try {[void][IO.Directory]::CreateDirectory($DataDirectory);[IO.File]::WriteAllText((Join-Path $DataDirectory 'startup-error.txt'),[string]$_)}catch{}
    if(-not $SelfTest){Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'SkinStudio')}
    exit 1
}

# Build first. These probes run only SelfTest, with isolated user data.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'SkinStudio.app.ps1'))
if($source -notmatch '\$script:AppVersion\s*=\s*''([^'']+)'''){throw 'Missing version'}
$version=$Matches[1]
$temp=Join-Path ([IO.Path]::GetTempPath()) ('SkinStudio-single-'+[guid]::NewGuid().ToString('N'))
$before=if(Test-Path (Join-Path $root 'config.json')){(Get-FileHash (Join-Path $root 'config.json')).Hash}else{''}
try {
    $exeDir=Join-Path $temp 'exe only';[void][IO.Directory]::CreateDirectory($exeDir)
    Expand-Archive -LiteralPath (Join-Path $root ('release\SkinStudio-v'+$version+'.zip')) -DestinationPath $exeDir
    if(@(Get-ChildItem -LiteralPath $exeDir -Force).Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $exeDir 'SkinStudio.exe'))){throw 'Distribution must contain exactly one EXE'}
    $exe=Join-Path $exeDir 'SkinStudio.exe';$data=Join-Path $temp 'isolated user data'
    if((Get-FileHash $exe).Hash -ne (Get-FileHash (Join-Path $root ('release\SkinStudio-v'+$version+'.exe'))).Hash){throw 'ZIP and standalone EXE differ'}
    foreach($round in 1..2){
        $process=Start-Process $exe -ArgumentList @('-SelfTest','-DataDirectory',('"'+$data+'"')) -WorkingDirectory $env:WINDIR -PassThru -WindowStyle Hidden
        if(-not $process.WaitForExit(45000)){Stop-Process -Id $process.Id -Force;throw 'Single-file UI self-test timeout'}
        if($process.ExitCode -ne 0){throw ('Single-file UI self-test failed: '+[IO.File]::ReadAllText((Join-Path $data 'startup-error.txt')))}
        $log=[IO.File]::ReadAllText((Join-Path $data 'logs\selftest.txt'))
        if($log -notmatch ('SkinStudio '+[regex]::Escape($version)) -or $log -notmatch 'opencode: bootstrap bytes='){throw 'Incomplete embedded runtime'}
        if($log -notmatch '(?m)^resources=(.+)$'){throw 'Missing resource diagnostics'}
        $runtime=$Matches[1].Trim()
        $resource=Join-Path $runtime 'skin-appearance.js'
        if($round -eq 1){$hash=(Get-FileHash $resource).Hash;[IO.File]::WriteAllText($resource,'corrupt cache fixture')}
        elseif((Get-FileHash $resource).Hash -ne $hash){throw 'Corrupted runtime cache was not repaired'}
    }
    if(@(Get-ChildItem -LiteralPath $exeDir -Force).Count -ne 1){throw 'Program scattered dependencies next to the EXE'}
    foreach($name in @('config.json','compatibility.json','compatibility-versions.json','startup-error.txt')){if(Test-Path -LiteralPath (Join-Path $data $name)){throw ('Self-test wrote unexpected data: '+$name)}}
    if($before -and (Get-FileHash (Join-Path $root 'config.json')).Hash -ne $before){throw 'Self-test changed real user settings'}
    if((Get-Item $exe).VersionInfo.FileVersion -ne ($version+'.0')){throw 'Executable version mismatch'}
    'PASS: standalone EXE, ZIP contains one EXE, embedded four-app/WPF tests, paths with spaces, arbitrary working directory, cache repair, no settings leakage.'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'SkinStudio-single-*'){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}

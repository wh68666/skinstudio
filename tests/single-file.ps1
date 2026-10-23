# Build first. These probes run only SelfTest, with isolated user data.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'src\SkinStudio.app.ps1'))
if($source -notmatch '\$script:AppVersion\s*=\s*''([^'']+)'''){throw 'Missing version'}
$version=$Matches[1]
$temp=Join-Path ([IO.Path]::GetTempPath()) ('SkinStudio-single-'+[guid]::NewGuid().ToString('N'))
$configPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SkinStudio\data\config.json'
$before=if(Test-Path -LiteralPath $configPath){(Get-FileHash -LiteralPath $configPath).Hash}else{''}
try {
    $exeDir=Join-Path $temp 'exe only';[void][IO.Directory]::CreateDirectory($exeDir)
    $distribution=Join-Path $root ('dist\SkinStudio-v'+$version+'.exe')
    if(Test-Path -LiteralPath (Join-Path $root ('dist\SkinStudio-v'+$version+'.zip'))){throw 'This version must be distributed as EXE only'}
    Copy-Item -LiteralPath $distribution -Destination (Join-Path $exeDir 'SkinStudio.exe')
    $exe=Join-Path $exeDir 'SkinStudio.exe';$data=Join-Path $temp 'isolated user data'
    if((Get-FileHash $exe).Hash -ne (Get-FileHash $distribution).Hash){throw 'Standalone executable copy differs'}
    foreach($round in 1..2){
        $process=Start-Process $exe -ArgumentList @('-SelfTest','-DataDirectory',('"'+$data+'"')) -WorkingDirectory $env:WINDIR -PassThru -WindowStyle Hidden
        if(-not $process.WaitForExit(45000)){Stop-Process -Id $process.Id -Force;throw 'Single-file UI self-test timeout'}
        if($process.ExitCode -ne 0){throw ('Single-file UI self-test failed: '+[IO.File]::ReadAllText((Join-Path $data 'startup-error.txt')))}
        $log=[IO.File]::ReadAllText((Join-Path $data 'logs\selftest.txt'))
        if($log -notmatch ('SkinStudio '+[regex]::Escape($version)) -or ($log -notmatch 'opencode: bootstrap bytes=' -or $log -notmatch 'workbuddy: bootstrap bytes=')){throw 'Incomplete embedded runtime'}
        if($log -notmatch '(?m)^resources=(.+)$'){throw 'Missing resource diagnostics'}
        $runtime=$Matches[1].Trim()
        $resource=Join-Path $runtime 'skin-appearance.js'
        if($round -eq 1){$hash=(Get-FileHash $resource).Hash;[IO.File]::WriteAllText($resource,'corrupt cache fixture')}
        elseif((Get-FileHash $resource).Hash -ne $hash){throw 'Corrupted runtime cache was not repaired'}
    }
    if(@(Get-ChildItem -LiteralPath $exeDir -Force).Count -ne 1){throw 'Program scattered dependencies next to the EXE'}
    foreach($name in @('config.json','compatibility.json','compatibility-versions.json','startup-error.txt')){if(Test-Path -LiteralPath (Join-Path $data $name)){throw ('Self-test wrote unexpected data: '+$name)}}
    if($before -and (Get-FileHash -LiteralPath $configPath).Hash -ne $before){throw 'Self-test changed real user settings'}
    if((Get-Item $exe).VersionInfo.FileVersion -ne ($version+'.0')){throw 'Executable version mismatch'}
    'PASS: EXE-only distribution, embedded five-app/WPF tests, paths with spaces, arbitrary working directory, cache repair, no settings leakage.'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'SkinStudio-single-*'){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
}

# Sequential checks: UI and packaged self-tests share an application mutex.
param([switch]$IncludePackage)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\verify.ps1')
if($LASTEXITCODE -ne 0){throw 'Regression checks failed'}
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'dev.ps1') -SelfTest
if($LASTEXITCODE -ne 0){throw 'Source UI checks failed'}
if($IncludePackage){
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\single-file.ps1')
    if($LASTEXITCODE -ne 0){throw 'Single-file distribution checks failed'}
}
'PASS: repository regression and source UI checks.'

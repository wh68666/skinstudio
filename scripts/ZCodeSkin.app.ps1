# Compatibility entry point for existing script users.
param([switch]$SelfTest)
. (Join-Path $PSScriptRoot 'dev.ps1') -SelfTest:$SelfTest

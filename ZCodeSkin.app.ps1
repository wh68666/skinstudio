# Compatibility entry point for existing script users.
param([switch]$SelfTest)
& (Join-Path $PSScriptRoot 'SkinStudio.app.ps1') -SelfTest:$SelfTest

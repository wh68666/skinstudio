& {
    . (Join-Path $root 'skin-storage.ps1')
    $resources=Join-Path $temp 'resources'
    [void][IO.Directory]::CreateDirectory((Join-Path $resources 'themes\aurora'))
    [IO.File]::WriteAllText((Join-Path $resources 'themes\aurora\theme.json'),'builtin')
    $fresh=Join-Path $temp 'fresh data'
    [void](Initialize-SkinDataDirectory $fresh $resources '')
    Assert (Test-Path -LiteralPath (Join-Path $fresh 'themes\aurora\theme.json')) 'Fresh single-file install did not seed built-in theme'
    $legacy=Join-Path $temp 'legacy'
    [void][IO.Directory]::CreateDirectory((Join-Path $legacy 'themes\custom'))
    $config='{"schemaVersion":4,"managerTheme":"pine","favorites":["custom"],"apps":{"codex":{"currentTheme":"custom","themeAdjustments":{"custom":{"panelOpacity":42,"blur":2,"position":"center"}}}}}'
    [IO.File]::WriteAllText((Join-Path $legacy 'config.json'),$config)
    [IO.File]::WriteAllText((Join-Path $legacy 'themes\custom\theme.json'),'custom')
    $migrated=Join-Path $temp 'migrated data'
    [void](Initialize-SkinDataDirectory $migrated $resources $legacy)
    $settings=Read-SkinSettings (Join-Path $migrated 'config.json')
    Assert ($settings.managerTheme -eq 'pine' -and $settings.apps.codex.themeAdjustments.custom.panelOpacity -eq 42 -and $settings.favorites -contains 'custom') 'Migration lost settings or adjustments'
    Assert ((Test-Path -LiteralPath (Join-Path $migrated 'themes\custom\theme.json')) -and -not (Test-Path -LiteralPath (Join-Path $migrated 'themes\aurora'))) 'Migration resurrected a deleted builtin theme'
    [IO.File]::WriteAllText((Join-Path $legacy 'config.json'),'changed old settings')
    [void](Initialize-SkinDataDirectory $migrated $resources $legacy)
    Assert ([IO.File]::ReadAllText((Join-Path $migrated 'config.json')) -eq $config) 'A later launch overwrote migrated settings'
    $openInfo=New-SkinDataFolderStartInfo $migrated
    Assert ($openInfo.UseShellExecute -and $openInfo.Verb -eq 'open' -and $openInfo.FileName -eq $migrated -and -not $openInfo.Arguments) 'Data folder must open through the shell without command-line quoting'
    Assert ([IO.File]::ReadAllText((Join-Path $migrated 'config.json')) -eq $config) 'Opening the data directory changed saved data'
    $missingFolder=Join-Path $temp 'folder with spaces\数据目录'
    $missingInfo=New-SkinDataFolderStartInfo $missingFolder
    Assert ([IO.Directory]::Exists($missingFolder) -and $missingInfo.FileName -eq $missingFolder) 'Missing data directory was not prepared before opening'
    $blockedFolder=Join-Path $temp 'not a directory'
    [IO.File]::WriteAllText($blockedFolder,'keep')
    Assert-Throws { New-SkinDataFolderStartInfo $blockedFolder } 'A file in place of the data directory should report an error'
    Assert ([IO.File]::ReadAllText($blockedFolder) -eq 'keep') 'Preparing the data directory overwrote a blocking file'
    $isolated=Join-Path $temp 'selftest data'
    [void](Initialize-SkinDataDirectory $isolated $resources $legacy -SelfTest)
    Assert (-not (Test-Path -LiteralPath (Join-Path $isolated 'config.json'))) 'Self-test imported real legacy settings'
}

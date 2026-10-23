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
    $isolated=Join-Path $temp 'selftest data'
    [void](Initialize-SkinDataDirectory $isolated $resources $legacy -SelfTest)
    Assert (-not (Test-Path -LiteralPath (Join-Path $isolated 'config.json'))) 'Self-test imported real legacy settings'
}

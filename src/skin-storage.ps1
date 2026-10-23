# Keep immutable program resources separate from persistent user data.
function Initialize-SkinDataDirectory {
    param([string]$DataDirectory,[string]$ResourceDirectory,[string]$LegacyDirectory,[switch]$SelfTest)
    $data=[IO.Path]::GetFullPath($DataDirectory)
    $legacy=if($LegacyDirectory){[IO.Path]::GetFullPath($LegacyDirectory)}else{''}
    $hasData=(Test-Path -LiteralPath $data) -and @(Get-ChildItem -LiteralPath $data -Force).Count -gt 0
    if(-not $SelfTest -and -not $hasData -and $legacy -and $legacy -ne $data -and (Test-Path -LiteralPath (Join-Path $legacy 'config.json'))) {
        $stage=$data+'.migration-'+[guid]::NewGuid().ToString('N')
        [void][IO.Directory]::CreateDirectory($stage)
        try {
            foreach($name in @('config.json','compatibility.json','compatibility-versions.json','themes','imports')) {
                $from=Join-Path $legacy $name
                if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination $stage -Recurse -Force -ErrorAction Stop}
            }
            if(Test-Path -LiteralPath $data){[IO.Directory]::Delete($data,$false)}
            [IO.Directory]::Move($stage,$data)
        } catch {
            # Keep the staged copy for recovery; never delete or change legacy data.
            throw ('Cannot migrate existing settings: '+$_.Exception.Message)
        }
    }
    [void][IO.Directory]::CreateDirectory($data)
    $themes=Join-Path $data 'themes'
    if(-not (Test-Path -LiteralPath $themes)) {
        [void][IO.Directory]::CreateDirectory($themes)
        $builtin=Join-Path $ResourceDirectory 'themes\aurora'
        if(Test-Path -LiteralPath $builtin){Copy-Item -LiteralPath $builtin -Destination $themes -Recurse}
    }
    return $data
}

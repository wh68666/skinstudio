# Publish the exact pushed commit. Credentials remain in memory, never in output/files.
param([string]$NotesPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Set-Location $root
$source=[IO.File]::ReadAllText((Join-Path $root 'src\SkinStudio.app.ps1'))
if($source -notmatch '\$script:AppVersion\s*=\s*''([^'']+)'''){throw 'Missing AppVersion'}
$version=$Matches[1];$tag='v'+$version;$repo='wh68666/skinstudio'
$assetName='SkinStudio-v'+$version+'.exe';$exePath=Join-Path $root ('dist\'+$assetName)
if(-not (Test-Path -LiteralPath $exePath)){throw 'Build the standalone executable first'}
if(-not $NotesPath){$NotesPath=Join-Path $root 'docs\RELEASE_NOTES.md'}
$notes=[IO.File]::ReadAllText($NotesPath)
$head=git rev-parse HEAD
if($LASTEXITCODE -ne 0){throw 'Cannot read commit'}
$credentialLines="protocol=https`nhost=github.com`n`n" | git credential fill
if($LASTEXITCODE -ne 0){throw 'GitHub credential lookup failed'}
$token=$null
foreach($line in $credentialLines){if($line -match '^password=(.+)$'){$token=$Matches[1]}}
if(-not $token){throw 'No GitHub credential found'}
$headers=@{Authorization='Bearer '+$token;Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28';'User-Agent'='SkinStudio-publisher'}
$api='https://api.github.com/repos/'+$repo
$branch=Invoke-RestMethod -Uri ($api+'/git/ref/heads/main') -Headers $headers
if($branch.object.sha -ne $head){throw 'Push the release commit to origin/main first'}
$tagRef=$null
try {$tagRef=Invoke-RestMethod -Uri ($api+'/git/ref/tags/'+$tag) -Headers $headers}
catch {if([int]$_.Exception.Response.StatusCode -ne 404){throw}}
if($tagRef){
    $tagCommit=$tagRef.object.sha
    if($tagRef.object.type -eq 'tag'){$tagCommit=(Invoke-RestMethod -Uri ($api+'/git/tags/'+$tagRef.object.sha) -Headers $headers).object.sha}
    if($tagCommit -ne $head){throw 'Remote release tag points to a different commit'}
}else{
    $tagBody=@{ref='refs/tags/'+$tag;sha=$head}|ConvertTo-Json
    $tagRef=Invoke-RestMethod -Uri ($api+'/git/refs') -Method Post -Headers $headers -Body $tagBody -ContentType 'application/json'
}
$existing=git tag -l $tag
if($existing){if((git rev-list -n 1 $tag) -ne $head){throw 'Local release tag points to a different commit'}}
else{git tag $tag $head;if($LASTEXITCODE -ne 0){throw 'Local tag creation failed'}}
$release=$null
try {$release=Invoke-RestMethod -Uri ($api+'/releases/tags/'+$tag) -Headers $headers}
catch {if([int]$_.Exception.Response.StatusCode -ne 404){throw}}
if(-not $release){
    $body=@{tag_name=$tag;target_commitish=$head;name='SkinStudio '+$tag;body=$notes;draft=$true;prerelease=$false}|ConvertTo-Json
    $release=Invoke-RestMethod -Uri ($api+'/releases') -Method Post -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8'
}
foreach($kind in @('exe')){
    $assetName='SkinStudio-v'+$version+'.'+$kind
    $assetPath=Join-Path $root ('dist\'+$assetName)
    if(-not (Test-Path -LiteralPath $assetPath)){throw ('Build asset missing: '+$assetName)}
    $sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($assetPath)
    try {$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
    $asset=@($release.assets|Where-Object name -eq $assetName)|Select-Object -First 1
    if($asset){
        if($asset.size -ne (Get-Item -LiteralPath $assetPath).Length -or ($asset.digest -and $asset.digest -ne ('sha256:'+$hash))){throw 'Existing release asset differs; it was not replaced'}
    }else{
        $upload='https://uploads.github.com/repos/'+$repo+'/releases/'+$release.id+'/assets?name='+[Uri]::EscapeDataString($assetName)
        $asset=Invoke-RestMethod -Uri $upload -Method Post -Headers $headers -InFile $assetPath -ContentType 'application/octet-stream'
    }
    if($asset.size -ne (Get-Item -LiteralPath $assetPath).Length -or $asset.state -ne 'uploaded'){throw 'Uploaded asset verification failed'}
    if($asset.digest -and $asset.digest -ne ('sha256:'+$hash)){throw 'Uploaded asset checksum mismatch'}
    'Verified '+$assetName+' SHA256: '+$hash
}
$body=@{name='SkinStudio '+$tag;body=$notes;draft=$false;prerelease=$false;make_latest='true'}|ConvertTo-Json
$release=Invoke-RestMethod -Uri ($api+'/releases/'+$release.id) -Method Patch -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8'
if($release.draft){throw 'Release is still a draft'}
'Release: '+$release.html_url
foreach($publishedAsset in $release.assets){'Asset: '+$publishedAsset.browser_download_url}

$headers=$null;$token=$null;$credentialLines=$null

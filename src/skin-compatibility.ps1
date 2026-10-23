# Compatibility evidence is separate from skin settings and scoped to an exact app build.
$script:SkinCompatibilityDir=$PSScriptRoot
$script:SkinCompatibilitySuite='work-pages-v1'
$script:SkinCompatibilityScenes=@('long-chat','code','composer','split','context','menu','settings')
function Get-SkinCompatibilityFileHash([string]$Path) {
    $stream=[IO.File]::OpenRead($Path); $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Get-SkinAppIdentity {
    param([string]$Application,[string]$AppExe,$Previous)
    if (-not (Test-SkinDesktopExe $Application $AppExe)) { return $null }
    $files=@(Get-Item -LiteralPath $AppExe)
    $asar=Join-Path (Split-Path $AppExe) 'resources\app.asar'
    if (Test-Path -LiteralPath $asar -PathType Leaf) { $files += Get-Item -LiteralPath $asar }
    $stamp=(@($files | ForEach-Object {$_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks}) -join ';')
    if ($Previous -and $Previous.stamp -eq $stamp) { return @{application=$Application;version=$Previous.version;fingerprint=$Previous.fingerprint;stamp=$stamp;adapter=(Get-SkinAdapterRevision $Application);suite=$script:SkinCompatibilitySuite} }
    $version=[string]$files[0].VersionInfo.ProductVersion
    if ($Application -eq 'codex' -and $AppExe -match 'OpenAI\.Codex_([0-9.]+)_') { $version=$Matches[1] }
    if (-not $version) { $version=[string]$files[0].VersionInfo.FileVersion }
    if (-not $version) { $version='unknown' }
    $hashes=@($files | ForEach-Object {(Get-SkinCompatibilityFileHash $_.FullName).ToUpperInvariant()})
    $bytes=[Text.Encoding]::UTF8.GetBytes($Application+'|'+$version+'|'+($hashes -join '|'))
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $fingerprint=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()}
    return @{application=$Application;version=$version;fingerprint=$fingerprint;stamp=$stamp;adapter=(Get-SkinAdapterRevision $Application);suite=$script:SkinCompatibilitySuite}
}
function Read-SkinCompatibilityRecords([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $data=[IO.File]::ReadAllText($Path) | ConvertFrom-Json
    if ($data.schemaVersion -ne 1) { throw 'Unsupported compatibility evidence format' }
    return @($data.records | Where-Object { $_.application -in @('zcode','monkeycode','codex','opencode','workbuddy') -and $_.fingerprint -match '^[a-f0-9]{64}$' -and $_.scene -in $script:SkinCompatibilityScenes -and $_.mode -in @('light','dark') -and $_.result -in @('pass','fail') -and $_.source -in @('manual','maintainer') })
}
function Get-SkinCompatibilityStatus {
    param($Identity,[string]$StorePath)
    if (-not $Identity) { return @{state='unknown';passed=0;total=14;records=@();identity=$null} }
    $all=@()
    try {
        $all += @(Read-SkinCompatibilityRecords (Join-Path $script:SkinCompatibilityDir 'compatibility-baseline.json'))
        $all += @(Read-SkinCompatibilityRecords $StorePath)
    } catch { return @{state='evidence_error';passed=0;total=14;records=@();identity=$Identity;error=$_.Exception.Message} }
    $appRecords=@($all | Where-Object application -eq $Identity.application)
    $current=@($appRecords | Where-Object {$_.fingerprint -eq $Identity.fingerprint -and $_.adapter -eq $Identity.adapter -and $_.suite -eq $Identity.suite})
    $latest=@{}
    foreach ($record in ($current | Sort-Object checkedAt)) { $latest[$record.mode+'/'+$record.scene]=$record }
    $records=@($latest.Values); $passed=@($records | Where-Object result -eq 'pass').Count
    $observedPath=Join-Path (Split-Path $StorePath) 'compatibility-versions.json'
    $observed=$null
    if(Test-Path -LiteralPath $observedPath){try{$observed=([IO.File]::ReadAllText($observedPath)|ConvertFrom-Json).apps.($Identity.application)}catch{return @{state='evidence_error';passed=$passed;total=14;records=$records;identity=$Identity;error=$_.Exception.Message}}}
    $changed=$observed -and $observed.current -eq $Identity.fingerprint -and $observed.previous
    $state=if (@($records | Where-Object result -eq 'fail').Count) { 'issues' } elseif ($passed -eq 14) { 'verified' } elseif ($records.Count) { 'partial' } elseif ($changed -or @($appRecords | Where-Object fingerprint -ne $Identity.fingerprint).Count) { 'updated' } elseif ($appRecords.Count) { 'adapter_changed' } else { 'untested' }
    return @{state=$state;passed=$passed;total=14;records=$records;identity=$Identity}
}
function Update-SkinCompatibilityObservation([string]$Path,$Identity) {
    if(-not $Identity){return}
    $apps=@{}
    if(Test-Path -LiteralPath $Path){$old=[IO.File]::ReadAllText($Path)|ConvertFrom-Json;if($old.schemaVersion -ne 1){throw 'Unsupported version observation format'};foreach($entry in $old.apps.PSObject.Properties){$apps[$entry.Name]=$entry.Value}}
    $previous=$apps[$Identity.application]
    if($previous -and $previous.current -eq $Identity.fingerprint){return}
    $apps[$Identity.application]=@{current=$Identity.fingerprint;version=$Identity.version;previous=$(if($previous){$previous.current}else{''});previousVersion=$(if($previous){$previous.version}else{''});observedAt=[DateTime]::UtcNow.ToString('o')}
    $temp=$Path+'.tmp'
    [IO.File]::WriteAllText($temp,(@{schemaVersion=1;apps=$apps}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Save-SkinCompatibilityReview {
    param([string]$Path,$Identity,[string]$Scene,[string]$Mode,[string]$Result,[string]$Note,[string]$EvidencePath,[string]$ThemeId,[string]$Source='manual')
    if (-not $Identity -or $Scene -notin $script:SkinCompatibilityScenes -or $Mode -notin @('light','dark') -or $Result -notin @('pass','fail') -or $Source -notin @('manual','maintainer')) { throw 'Invalid compatibility review' }
    if ($Note.Trim().Length -lt 4) { throw 'A review note is required' }
    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) { throw 'Screenshot evidence is required' }
    $record=@{application=$Identity.application;version=$Identity.version;fingerprint=$Identity.fingerprint;adapter=$Identity.adapter;suite=$Identity.suite;scene=$Scene;mode=$Mode;result=$Result;note=$Note;source=$Source;theme=$ThemeId;checkedAt=[DateTime]::UtcNow.ToString('o');evidence=[IO.Path]::GetFullPath($EvidencePath);evidenceHash=(Get-SkinCompatibilityFileHash $EvidencePath)}
    # Parse errors are never treated as an empty file; do not silently destroy evidence.
    $records=@(Read-SkinCompatibilityRecords $Path | Where-Object { -not ($_.application -eq $Identity.application -and $_.fingerprint -eq $Identity.fingerprint -and $_.adapter -eq $Identity.adapter -and $_.suite -eq $Identity.suite -and $_.scene -eq $Scene -and $_.mode -eq $Mode) })
    $records += $record
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,(@{schemaVersion=1;records=$records}|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $temp) {Remove-Item -LiteralPath $temp -Force} }
    return $record
}
function Get-SkinWorkPageAudit {
    param([string]$Application,[string]$AppExe,[int]$Port,[string]$EvidenceDir)
    $targets=@(Get-SkinTargets $Application $AppExe $Port)
    if (-not $targets.Count) { throw 'No owned compatible page. Connect the app before checking work pages.' }
    [void](New-Item $EvidenceDir -ItemType Directory -Force)
    Start-Sleep -Milliseconds 300
    $pages=@()
    foreach ($target in $targets) {
        $ws=Connect-CdpWs $target.webSocketDebuggerUrl
        try {
            $js=[IO.File]::ReadAllText((Join-Path $script:SkinCompatibilityDir 'skin-workpage-audit.js'))
            $response=(Invoke-Cdp $ws 81 'Runtime.evaluate' @{expression=$js;returnByValue=$true;awaitPromise=$true} -TimeoutMs 6000)|ConvertFrom-Json
            if ($response.error -or $response.result.exceptionDetails) { throw 'Work page audit script failed' }
            $audit=$response.result.result.value
            $shot=(Invoke-Cdp $ws 82 'Page.captureScreenshot' @{format='png';captureBeyondViewport=$false} -TimeoutMs 6000)|ConvertFrom-Json
            if (-not $shot.result.data) { throw 'Page screenshot unavailable' }
            $file=Join-Path $EvidenceDir ($Application+'-'+[guid]::NewGuid().ToString('N')+'.png')
            [IO.File]::WriteAllBytes($file,[Convert]::FromBase64String($shot.result.data))
            $pages += @{audit=$audit;screenshot=$file;target=$target.id}
        } finally { Disconnect-CdpWs $ws }
    }
    # This snapshot is automatic evidence, never a human acceptance record.
    return @{application=$Application;capturedAt=[DateTime]::UtcNow.ToString('o');pages=$pages}
}

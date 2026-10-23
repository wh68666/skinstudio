& {
    Assert ((Get-SkinAdapterRevision workbuddy) -eq '2.8.2' -and (Get-SkinAdapterRevision monkeycode) -eq $script:SkinRuntimeRevision) 'WorkBuddy update changed another app adapter revision'
    $identity=@{application='codex';version='test-1';fingerprint=('a'*64);adapter=$script:SkinRuntimeRevision;suite=$script:SkinCompatibilitySuite}
    $store=Join-Path $temp 'compatibility.json'
    $versions=Join-Path $temp 'compatibility-versions.json'
    Assert ((Get-SkinCompatibilityStatus $identity $store).state -eq 'untested') 'Unknown build reported verified'
    Update-SkinCompatibilityObservation $versions $identity
    $shot=Join-Path $temp 'evidence.png';[IO.File]::WriteAllBytes($shot,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6WQAAAABJRU5ErkJggg=='))
    Assert ((Get-SkinCompatibilityFileHash $shot) -eq (Get-FileHash -LiteralPath $shot -Algorithm SHA256).Hash.ToLowerInvariant()) 'Portable hash differs from SHA256'
    Assert-Throws {Save-SkinCompatibilityReview $store $identity 'composer' light pass '' $shot 'fixture'} 'Empty review note accepted'
    foreach($mode in @('light','dark')){foreach($scene in $script:SkinCompatibilityScenes){[void](Save-SkinCompatibilityReview $store $identity $scene $mode pass 'Visual test fixture review' $shot fixture)}}
    Assert ((Get-SkinCompatibilityStatus $identity $store).state -eq 'verified') 'Complete fourteen-item review not recognized'
    [void](Save-SkinCompatibilityReview $store $identity 'code' dark fail 'Fixture clipping issue' $shot fixture)
    $status=Get-SkinCompatibilityStatus $identity $store
    Assert ($status.state -eq 'issues' -and $status.passed -eq 13) 'Failure overwritten by historical pass'
    $next=@{}+$identity;$next.fingerprint='b'*64;$next.version='test-2'
    Update-SkinCompatibilityObservation $versions $next
    Assert ((Get-SkinCompatibilityStatus $next $store).state -eq 'updated') 'Updated app inherited old acceptance'
    $next.adapter='future-adapter'
    Assert ((Get-SkinCompatibilityStatus $next $store).passed -eq 0) 'Changed adapter inherited old acceptance'
    [IO.File]::WriteAllText($store,'broken evidence')
    Assert ((Get-SkinCompatibilityStatus $identity $store).state -eq 'evidence_error') 'Corrupt evidence silently treated as compatible'
    Assert-Throws {Save-SkinCompatibilityReview $store $identity 'code' dark pass 'Do not overwrite broken evidence' $shot fixture} 'Review overwrote corrupt evidence'
    Remove-Item -LiteralPath $store
    Remove-Item -LiteralPath $versions
}

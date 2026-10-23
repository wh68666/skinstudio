# Shared local/gallery thumbnail cards. Network/decode work stays off the UI thread.
if (-not ('SkinStudioThemeCard' -as [type])) {
    Add-Type -ReferencedAssemblies @([Windows.Media.ImageSource].Assembly.Location, [Windows.DependencyObject].Assembly.Location, 'System.dll') -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Windows.Media;
public sealed class SkinStudioThemeCard : INotifyPropertyChanged {
 public string Id {get;set;} public string ThemeId {get;set;} public string Name {get;set;}
 public string Detail {get;set;} public string Tooltip {get;set;} public string ModeLabel {get;set;}
 public string ModeBackground {get;set;} public string ModeForeground {get;set;}
 public string StateLabel {get;set;} public string StateVisibility {get;set;} public string ThumbKey {get;set;}
 private ImageSource image; private string glyph,tip,hint; private double width=208;
 public ImageSource Thumbnail {get{return image;}set{image=value;Changed("Thumbnail");Changed("PlaceholderVisibility");}}
 public string PlaceholderVisibility {get{return image==null?"Visible":"Collapsed";}}
 public string FavoriteGlyph {get{return glyph;}set{glyph=value;Changed("FavoriteGlyph");}}
 public string FavoriteTip {get{return tip;}set{tip=value;Changed("FavoriteTip");}}
 public string PreviewHint {get{return hint;}set{hint=value;Changed("PreviewHint");}}
 public double CardWidth {get{return width;}set{if(Math.Abs(width-value)<1)return;width=value;Changed("CardWidth");Changed("ThumbnailHeight");}}
 public double ThumbnailHeight {get{return Math.Round(width*9/16);}}
 public event PropertyChangedEventHandler PropertyChanged;
 private void Changed(string name){if(PropertyChanged!=null)PropertyChanged(this,new PropertyChangedEventArgs(name));}
}
'@
}
$dictionary = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $AppDir 'theme-cards.xaml')))
$window.Resources.MergedDictionaries.Add($dictionary)
foreach ($list in @($themeList,$galleryList)) {
    $list.ItemTemplate = $dictionary['ThemeCardTemplate']; $list.ItemContainerStyle = $dictionary['ThemeCardContainer']; $list.ItemsPanel = $dictionary['ThemeCardPanel']
    [Windows.Controls.ScrollViewer]::SetHorizontalScrollBarVisibility($list,'Disabled')
    [Windows.Controls.ScrollViewer]::SetVerticalScrollBarVisibility($list,'Auto')
    [Windows.Controls.ScrollViewer]::SetCanContentScroll($list,$false)
    $list.Background = [Windows.Media.Brushes]::Transparent
    $list.BorderThickness = '0'
}
foreach ($name in @('ThemeSearch','ThemeSearchHint','ThemeSearchClear','ThemeFavoritesOnly','ThemeCount','ThemeEmpty','GallerySearch','GallerySearchHint','GallerySearchClear','GalleryFavoritesOnly','GalleryCount','GalleryEmpty')) { Set-Variable -Scope Script -Name $name -Value $window.FindName($name) }
$script:LocalCards = @(); $script:GalleryCards = @{}
$script:BrowserSelection = @{}; $script:BrowserDrafts = @{}
$script:BrowserDisplayedApp = ''
$script:ThumbnailMemory = @{}; $script:ThumbnailQueued = @{}
$script:ThumbnailQueue = New-Object Collections.Queue
$script:ThumbnailJobs = 0
$script:GalleryVisibleLimit = 24
$script:GalleryMatchedCount = 0
$script:ThumbnailCacheDir = Join-Path $AppDir 'assets\thumbnails'
. (Join-Path $AppDir 'skin-thumbnails.ps1')
$script:ThumbnailFailures = @{}

function Request-ThemeThumbnail($Card, [string]$Path, [switch]$Remote) {
    $spec = @{ Module = (Join-Path $AppDir 'skin-thumbnails.ps1'); Remote = [bool]$Remote; Id = $Card.Id; Path = $Path; CacheDir = $script:ThumbnailCacheDir }
    if ($Remote) {
        if ($Card.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { $Card.PreviewHint=(Get-ThemeBrowserLabels).unavailable; return }
        $key = 'remote:' + $Card.Id
    } else {
        if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { $Card.PreviewHint=(Get-ThemeBrowserLabels).unavailable; return }
        $info = Get-Item -LiteralPath $Path
        $key = 'local:' + $info.FullName + ':' + $info.LastWriteTimeUtc.Ticks + ':' + $info.Length
    }
    $spec.Key = $key; $Card.ThumbKey = $key
    if ($script:ThumbnailMemory.ContainsKey($key)) { $Card.Thumbnail = $script:ThumbnailMemory[$key]; return }
    if ($SelfTest) {
        if (-not $Remote) {
            try { $Card.Thumbnail=Read-ThemeThumbnail $Path; $script:ThumbnailMemory[$key]=$Card.Thumbnail } catch { $Card.PreviewHint=(Get-ThemeBrowserLabels).unavailable }
        } else { $Card.PreviewHint=(Get-ThemeBrowserLabels).unavailable }
        return
    }
    if ($script:ThumbnailFailures.ContainsKey($key) -and ((Get-Date)-$script:ThumbnailFailures[$key]).TotalSeconds -lt 60) { $Card.PreviewHint=(Get-ThemeBrowserLabels).unavailable; return }
    if (-not $script:ThumbnailQueued[$key]) { $script:ThumbnailQueued[$key]=$true; $script:ThumbnailQueue.Enqueue($spec) }
}

function Start-ThemeThumbnailJobs {
    if ($SelfTest) { return }
    while ($script:ThumbnailJobs -lt 2 -and $script:ThumbnailQueue.Count) {
        $spec = $script:ThumbnailQueue.Dequeue()
        $needed = @(@($script:LocalCards)+@($script:GalleryCards.Values) | Where-Object ThumbKey -eq $spec.Key).Count -gt 0
        if (-not $needed) { $script:ThumbnailQueued.Remove([string]$spec.Key); continue }
        $script:ThumbnailJobs++
        Start-BackgroundJob $script:ThemeThumbnailWorker $spec {
            param($out)
            $r=$out | Select-Object -Last 1
            $script:ThumbnailJobs--
            if ($r -and $r.key) {
                $script:ThumbnailQueued.Remove([string]$r.key)
                if ($r.ok) {
                    if ($script:ThumbnailMemory.Count -ge 192) { $script:ThumbnailMemory.Clear() }
                    $script:ThumbnailMemory[[string]$r.key]=$r.bitmap
                } else { $script:ThumbnailFailures[[string]$r.key]=Get-Date }
                foreach ($card in @($script:LocalCards)+@($script:GalleryCards.Values)) {
                    if ($card.ThumbKey -eq $r.key) {
                        if ($r.ok) { $card.Thumbnail=$r.bitmap } else { $card.PreviewHint=(Get-ThemeBrowserLabels).unavailable }
                    }
                }
            }
            Start-ThemeThumbnailJobs
        }
    }
}

function Get-ThemeBrowserLabels {
    if ($Cfg.lang -eq 'zh-CN') { return @{ search='搜索主题名称或 ID'; remoteSearch='搜索远程主题或作者'; favorites='仅收藏'; empty='没有匹配的主题'; noLocal='暂无主题，可导入 ZIP 主题包'; noRemote='尚未加载主题，或没有匹配结果'; searching='正在加载主题目录…'; light='☀ 浅色'; dark='☾ 深色'; unknown='未标注'; active='当前使用'; installed='已安装'; otherVersion='已安装其他版本'; add='收藏主题'; remove='取消收藏'; loading='加载预览…'; unavailable='暂无预览' } }
    if ($Cfg.lang -eq 'zh-TW') { return @{ search='搜尋主題名稱或 ID'; remoteSearch='搜尋遠端主題或作者'; favorites='僅收藏'; empty='沒有相符的主題'; noLocal='尚無主題，可匯入 ZIP 主題包'; noRemote='尚未載入主題，或沒有相符結果'; searching='正在載入主題目錄…'; light='☀ 淺色'; dark='☾ 深色'; unknown='未標註'; active='目前使用'; installed='已安裝'; otherVersion='已安裝其他版本'; add='收藏主題'; remove='取消收藏'; loading='載入預覽…'; unavailable='暫無預覽' } }
    return @{ search='Search theme name or ID'; remoteSearch='Search remote themes or authors'; favorites='Favorites only'; empty='No matching themes'; noLocal='No themes yet. Import a ZIP to get started.'; noRemote='No loaded or matching themes'; searching='Loading theme catalog…'; light='☀ Light'; dark='☾ Dark'; unknown='Unspecified'; active='In use'; installed='Installed'; otherVersion='Other version installed'; add='Favorite theme'; remove='Remove favorite'; loading='Loading preview…'; unavailable='Preview unavailable' }
}

function Get-ThemeCardWidth($List) {
    $available = [Math]::Max(220,$List.ActualWidth - 28)
    $columns = [Math]::Max(1,[Math]::Min(5,[Math]::Floor($available / 215)))
    return [Math]::Max(180,[Math]::Floor($available / $columns) - 18)
}

function Set-ThemeCardFavorite($Card) {
    $labels = Get-ThemeBrowserLabels
    $favorite = $Settings.favorites -contains $Card.ThemeId
    $Card.FavoriteGlyph = if ($favorite) { '★' } else { '☆' }
    $Card.FavoriteTip = if ($favorite) { $labels.remove } else { $labels.add }
}

function New-ThemeCard($Item, [switch]$Remote) {
    $labels = Get-ThemeBrowserLabels
    $card = New-Object SkinStudioThemeCard
    $card.Id = [string]$Item.Id
    $card.ThemeId = if ($Remote -and $Item.ThemeId) { [string]$Item.ThemeId } else { [string]$Item.Id }
    $card.Name = ([string]$Item.Name -replace '\s*\[(light|dark)\]\s*$','').Trim()
    if (-not $card.Name) { $card.Name = $card.ThemeId }
    $card.Detail = if ($Remote) { [string]$Item.Author + ' · v' + $Item.Version } else { $card.ThemeId + ' · v' + $Item.Version }
    $card.Tooltip = $card.Name + "`n" + $card.ThemeId + "`n" + $card.Detail
    $mode = ([string]$Item.Appearance).Trim().ToLowerInvariant()
    switch ($mode) {
        'light' { $card.ModeLabel=$labels.light; $card.ModeBackground='#FFF3C7'; $card.ModeForeground='#854D0E' }
        'dark' { $card.ModeLabel=$labels.dark; $card.ModeBackground='#E0E7FF'; $card.ModeForeground='#3730A3' }
        default { $card.ModeLabel=$labels.unknown; $card.ModeBackground='#F1F5F9'; $card.ModeForeground='#475569' }
    }
    $installed = @($State.Themes | Where-Object Id -eq $card.ThemeId | Select-Object -First 1)
    $sameVersion = $installed.Count -and [string]$installed[0].Version -eq [string]$Item.Version
    $card.StateLabel = if ($State.Current -eq $card.ThemeId -and (-not $Remote -or $sameVersion)) { $labels.active } elseif ($Remote -and $sameVersion) { $labels.installed } elseif ($Remote -and $installed.Count) { $labels.otherVersion } else { '' }
    $card.StateVisibility = if ($card.StateLabel) { 'Visible' } else { 'Collapsed' }
    $card.PreviewHint = $labels.loading
    $card.CardWidth = Get-ThemeCardWidth $(if ($Remote) { $galleryList } else { $themeList })
    Set-ThemeCardFavorite $card
    return $card
}

function Test-ThemeCardMatch($Card, [string]$Query, [bool]$FavoritesOnly) {
    if ($FavoritesOnly -and $Settings.favorites -notcontains $Card.ThemeId) { return $false }
    if (-not $Query.Trim()) { return $true }
    $haystack = $Card.Name + ' ' + $Card.ThemeId + ' ' + $Card.Detail
    foreach ($word in ($Query.Trim() -split '\s+')) { if ($haystack.IndexOf($word,[StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }
    return $true
}

function Refresh-LocalThemeCards([switch]$PreserveDraft) {
    if (-not $script:ThemeSearch) { return }
    $labels = Get-ThemeBrowserLabels
    $appId = [string]$Settings.activeApp
    $selected = if ($script:BrowserDisplayedApp -eq $appId -and $themeList.SelectedItem) { [string]$themeList.SelectedItem.Id } elseif ($script:BrowserSelection[$appId]) { [string]$script:BrowserSelection[$appId] } else { [string]$State.Current }
    $script:BrowserDisplayedApp = $appId
    if ($selected) { $script:BrowserSelection[$appId] = $selected }
    $draftKey = $appId + '/' + $selected
    if ($PreserveDraft -and $themeList.SelectedItem -and $script:VisualEditor) { $script:BrowserDrafts[$draftKey] = Get-SkinVisualDraft }
    if (-not $PreserveDraft) { $script:BrowserDrafts.Remove($draftKey) }
    $script:RefreshingThemes = $true
    try {
        $ThemeSearchHint.Text=$labels.search; $ThemeFavoritesOnly.Content=$labels.favorites
        $ThemeSearchHint.Visibility = if ($ThemeSearch.Text) { 'Collapsed' } else { 'Visible' }
        $cards = @(); $themeList.Items.Clear()
        foreach ($item in $State.Themes) {
            $card = New-ThemeCard $item
            $cards += $card
            if (Test-ThemeCardMatch $card $ThemeSearch.Text ([bool]$ThemeFavoritesOnly.IsChecked)) {
                Request-ThemeThumbnail $card $item.BgPath
                [void]$themeList.Items.Add($card)
                if ($card.Id -eq $selected) { $themeList.SelectedItem = $card }
            }
        }
        $script:LocalCards = $cards
        $ThemeCount.Text = [string]$themeList.Items.Count + ' / ' + $cards.Count
        $ThemeEmpty.Text = if ($cards.Count) { $labels.empty } else { $labels.noLocal }
        $ThemeEmpty.Visibility = if ($themeList.Items.Count) { 'Collapsed' } else { 'Visible' }
    } finally { $script:RefreshingThemes = $false }
    Sync-SkinVisualUi
    if ($themeList.SelectedItem) { $themeList.ScrollIntoView($themeList.SelectedItem) }
    if ($PreserveDraft -and $themeList.SelectedItem -and $script:BrowserDrafts[$draftKey]) {
        $script:UpdatingVisual = $true
        try { Set-SkinVisualDraft $script:BrowserDrafts[$draftKey] } finally { $script:UpdatingVisual = $false }
    }
    Start-ThemeThumbnailJobs
}

function Refresh-GalleryCards {
    if (-not $script:GallerySearch) { return }
    $labels = Get-ThemeBrowserLabels
    $selected = if ($galleryList.SelectedItem) { [string]$galleryList.SelectedItem.Id } else { $script:GallerySelection }
    if ($selected) { $script:GallerySelection = $selected }
    $GallerySearchHint.Text=$labels.remoteSearch; $GalleryFavoritesOnly.Content=$labels.favorites
    $GallerySearchHint.Visibility = if ($GallerySearch.Text) { 'Collapsed' } else { 'Visible' }
    $galleryList.Items.Clear(); $script:GalleryCards = @{}; $script:GalleryMatchedCount=0
    foreach ($item in $State.Gallery) {
        $card = New-ThemeCard $item -Remote
        $script:GalleryCards[$card.Id] = $card
        if (Test-ThemeCardMatch $card $GallerySearch.Text ([bool]$GalleryFavoritesOnly.IsChecked)) {
            $script:GalleryMatchedCount++
            if ($script:GalleryMatchedCount -gt $script:GalleryVisibleLimit) { continue }
            Request-ThemeThumbnail $card '' -Remote
            [void]$galleryList.Items.Add($card)
            if ($card.Id -eq $selected) { $galleryList.SelectedItem = $card }
        }
    }
    $GalleryCount.Text = [string]$galleryList.Items.Count + ' / ' + $script:GalleryMatchedCount
    $GalleryCount.ToolTip = [string]$State.Gallery.Count + ' / ' + $State.GalleryTotal
    $GalleryEmpty.Text=if ($State.GalleryBusy) { $labels.searching } else { $labels.noRemote }
    $GalleryEmpty.Visibility = if ($galleryList.Items.Count) { 'Collapsed' } else { 'Visible' }
    $btnMore.IsEnabled = -not $State.GalleryBusy -and ($galleryList.Items.Count -lt $script:GalleryMatchedCount -or $State.GalleryOffset -lt $State.GalleryTotal)
    Start-ThemeThumbnailJobs
}

function Toggle-ThemeFavorite([string]$ThemeId) {
    if ($ThemeId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { return }
    if ($Settings.favorites -contains $ThemeId) { $Settings.favorites = @($Settings.favorites | Where-Object { $_ -ne $ThemeId }) }
    else { $Settings.favorites = @($Settings.favorites) + $ThemeId }
    Save-Cfg
    foreach ($card in @($script:LocalCards) + @($script:GalleryCards.Values)) { if ($card.ThemeId -eq $ThemeId) { Set-ThemeCardFavorite $card } }
    if ($ThemeFavoritesOnly.IsChecked) { Refresh-LocalThemeCards -PreserveDraft }
    if ($GalleryFavoritesOnly.IsChecked) { Refresh-GalleryCards }
}

function Get-ThemeFavoriteButton($node) {
    while ($node -is [Windows.DependencyObject]) {
        if ($node -is [Windows.Controls.Button] -and $node.Name -eq 'ThemeFavoriteButton') { return $node }
        if ($node -is [Windows.Media.Visual]) { $node = [Windows.Media.VisualTreeHelper]::GetParent($node) }
        else { $node = [Windows.LogicalTreeHelper]::GetParent($node) }
    }
    return $null
}

function Test-ThemeFavoriteOrigin($Event) {
    return $null -ne (Get-ThemeFavoriteButton $Event.OriginalSource)
}

foreach ($list in @($themeList,$galleryList)) {
    $list.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent,[Windows.RoutedEventHandler]{
        param($sender,$e)
        $button = Get-ThemeFavoriteButton $e.OriginalSource
        if ($button) { Toggle-ThemeFavorite ([string]$button.DataContext.ThemeId); $e.Handled=$true }
    })
    $list.Add_SizeChanged({
        param($sender,$e)
        $width = Get-ThemeCardWidth $sender
        foreach ($card in $sender.Items) { $card.CardWidth = $width }
    })
}
$themeList.Add_SelectionChanged({ if (-not $script:RefreshingThemes -and $themeList.SelectedItem) { $script:BrowserSelection[[string]$Settings.activeApp]=[string]$themeList.SelectedItem.Id } })
$ThemeSearch.Add_TextChanged({ if (-not $script:BrowserUpdating) { Refresh-LocalThemeCards -PreserveDraft } })
$GallerySearch.Add_TextChanged({ if (-not $script:BrowserUpdating) { $script:GalleryVisibleLimit=24; Refresh-GalleryCards } })
$ThemeSearchClear.Add_Click({ $ThemeSearch.Text='' })
$GallerySearchClear.Add_Click({ $GallerySearch.Text='' })
$ThemeFavoritesOnly.Add_Click({ Refresh-LocalThemeCards -PreserveDraft })
$GalleryFavoritesOnly.Add_Click({ $script:GalleryVisibleLimit=24; Refresh-GalleryCards })
$script:GallerySearchTimer = New-Object Windows.Threading.DispatcherTimer
$script:GallerySearchTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$script:GallerySearchTimer.Add_Tick({
    $script:GallerySearchTimer.Stop()
    if (-not $SelfTest -and ($GallerySearch.Text.Trim() -or $GalleryFavoritesOnly.IsChecked) -and -not $State.GalleryBusy -and $State.GalleryOffset -lt $State.GalleryTotal) { Start-GalleryLoad 1 -All }
})
$GallerySearch.Add_TextChanged({ if (-not $SelfTest -and -not $script:BrowserUpdating) { $script:GallerySearchTimer.Stop(); $script:GallerySearchTimer.Start() } })
$GalleryFavoritesOnly.Add_Click({ if (-not $SelfTest) { $script:GallerySearchTimer.Stop(); $script:GallerySearchTimer.Start() } })

function Show-MoreGalleryCards {
    $script:GalleryVisibleLimit += 12
    Refresh-GalleryCards
    if (-not $State.GalleryBusy -and $script:GalleryMatchedCount -lt $script:GalleryVisibleLimit -and $State.GalleryOffset -lt $State.GalleryTotal) {
        if ($GallerySearch.Text.Trim() -or $GalleryFavoritesOnly.IsChecked) { Start-GalleryLoad 1 -All }
        else { Start-GalleryLoad 1 }
    }
}

function Test-ThemeBrowser {
    $oldFavorites=@($Settings.favorites); $oldGallery=$State.Gallery; $oldCurrent=$State.Current
    $oldTotal=$State.GalleryTotal; $oldOffset=$State.GalleryOffset
    try {
        $Settings.favorites=@()
        $ThemeSearch.Text=''; $ThemeFavoritesOnly.IsChecked=$false
        Refresh-ThemeList
        $aurora=@($themeList.Items | Where-Object Id -eq 'aurora')[0]
        if (-not $aurora -or -not $aurora.Thumbnail -or $aurora.Thumbnail.PixelWidth -le 1) { throw 'Local card wallpaper thumbnail missing' }
        $themeList.SelectedItem=$aurora
        $VisualOpacity.Value=43; $VisualBlur.Value=2; $VisualPosition.SelectedIndex=4
        $ThemeSearch.Text='AuRoRa'
        if ($themeList.SelectedItem.Id -ne 'aurora' -or $VisualOpacity.Value -ne 43) { throw 'Search lost selection or unsaved visual draft' }
        $ThemeSearch.Text='no-match-'+[guid]::NewGuid().ToString('N')
        if ($themeList.Items.Count -ne 0 -or $ThemeEmpty.Visibility -ne 'Visible' -or $VisualApplySave.IsEnabled) { throw 'Empty search left the wrong theme actionable' }
        $ThemeSearch.Text=''
        if ($themeList.SelectedItem.Id -ne 'aurora' -or $VisualOpacity.Value -ne 43 -or $VisualBlur.Value -ne 2) { throw 'Clearing search lost the selected theme draft' }
        $State.Gallery=@(
            @{Id='ver-fixture-a';ThemeId='aurora';Name='Aurora remote';Version='1.0.0';Appearance='dark';Author='UniqueAuthor'},
            @{Id='ver-fixture-b';ThemeId='other-fixture';Name='Other remote';Version='1.0.0';Appearance='light';Author='Different'}
        )
        $State.GalleryTotal=2; $State.GalleryOffset=2
        $script:ThumbnailMemory['remote:ver-fixture-a']=$aurora.Thumbnail
        $script:ThumbnailMemory['remote:ver-fixture-b']=$aurora.Thumbnail
        Refresh-GalleryCards
        Toggle-ThemeFavorite aurora
        if ($Settings.favorites -notcontains 'aurora' -or $script:GalleryCards['ver-fixture-a'].FavoriteGlyph -ne '★') { throw 'Favorite was not shared with the remote theme ID' }
        $GallerySearch.Text='UniqueAuthor'
        if ($galleryList.Items.Count -ne 1) { throw 'Remote author search failed' }
        $GallerySearch.Text=''
        $GalleryFavoritesOnly.IsChecked=$true; Refresh-GalleryCards
        if ($galleryList.Items.Count -ne 1 -or $galleryList.Items[0].ThemeId -ne 'aurora') { throw 'Remote favorites filter failed' }
        $window.Content.Measure([Windows.Size]::new(760,660)); $window.Content.Arrange([Windows.Rect]::new(0,0,760,660)); $window.Content.UpdateLayout()
        $container=$themeList.ItemContainerGenerator.ContainerFromItem($themeList.SelectedItem)
        $find=New-Object Collections.Queue; $find.Enqueue($container); $star=$null
        while ($find.Count) {
            $node=$find.Dequeue()
            if ($node -is [Windows.Controls.Button] -and $node.Name -eq 'ThemeFavoriteButton') { $star=$node; break }
            if ($node -is [Windows.Media.Visual]) { for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$i++) { $find.Enqueue([Windows.Media.VisualTreeHelper]::GetChild($node,$i)) } }
        }
        if (-not $star -or -not (Test-ThemeFavoriteOrigin ([pscustomobject]@{OriginalSource=$star}))) { throw 'Card favorite button is not isolated from apply gestures' }
        $star.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($Settings.favorites -contains 'aurora' -or $galleryList.Items.Count -ne 0) { throw ('Card star did not remove a favorite: favorites=' + ($Settings.favorites -join ',') + ' count=' + $galleryList.Items.Count + ' tag=' + $star.Tag + ' context=' + $star.DataContext.ThemeId) }
        $ThemeFavoritesOnly.IsChecked=$true; Refresh-LocalThemeCards -PreserveDraft
        if ($themeList.Items.Count) { throw 'Local favorites-only empty state failed' }
        Toggle-ThemeFavorite aurora
        if ($themeList.Items.Count -ne 1 -or $themeList.Items[0].Id -ne 'aurora') { throw 'Local favorite filter did not update' }
        $State.Current='aurora'
        $current=New-ThemeCard $State.Gallery[0] -Remote
        if ($current.StateLabel -ne (Get-ThemeBrowserLabels).active) { throw 'Remote current-use badge failed' }
        $different=New-ThemeCard @{Id='ver-other';ThemeId='aurora';Name='Other';Version='2.0.0';Appearance=''} -Remote
        if ($different.StateLabel -ne (Get-ThemeBrowserLabels).otherVersion -or $different.ModeLabel -ne (Get-ThemeBrowserLabels).unknown) { throw 'Version/unspecified mode badge is misleading' }
        $missing=New-ThemeCard @{Id='missing-fixture';Name='Missing';Version='1';Appearance=''}
        Request-ThemeThumbnail $missing ''
        if ($missing.PlaceholderVisibility -ne 'Visible' -or $missing.PreviewHint -ne (Get-ThemeBrowserLabels).unavailable) { throw 'Missing wallpaper did not produce a usable placeholder' }
        foreach ($lang in $script:LangCodes) {
            Set-Lang $lang
            if ($ThemeFavoritesOnly.Content -ne (Get-ThemeBrowserLabels).favorites -or $galleryList.Items.Count -ne 1) { throw 'Browser localization lost favorites filtering' }
        }
        # Exercise the actual decode runspace and observable VM image handoff.
        $row=$themeList.Items[0]; $key=$row.ThumbKey; $row.Thumbnail=$null
        $script:ThumbnailQueue.Enqueue(@{Module=(Join-Path $AppDir 'skin-thumbnails.ps1');Remote=$false;Key=$key;Path=(Join-Path $ThemesDir 'aurora\background.jpg')})
        $script:ThumbnailQueued[$key]=$true
        $originalSelfTest=$script:SelfTest
        try { $script:SelfTest=$false; Start-ThemeThumbnailJobs } finally { $script:SelfTest=$originalSelfTest }
        $frame=New-Object Windows.Threading.DispatcherFrame; $deadline=(Get-Date).AddSeconds(10)
        $timer=New-Object Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromMilliseconds(30)
        $timer.Add_Tick({ if ($script:ThumbnailJobs -eq 0 -or (Get-Date) -gt $deadline) { $frame.Continue=$false } }.GetNewClosure())
        $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame); $timer.Stop()
        if ($script:ThumbnailJobs -ne 0 -or -not $row.Thumbnail -or $row.Thumbnail.PixelWidth -le 1) { throw 'Background preview did not update the card' }
        $ThemeFavoritesOnly.IsChecked=$false; Refresh-LocalThemeCards -PreserveDraft
        while ($themeList.Items.Count -lt 3) {
            $layout=New-ThemeCard @{Id=('layout-'+$themeList.Items.Count);Name='Layout test';Version='1';Appearance='dark'}
            $layout.Thumbnail=$row.Thumbnail; [void]$themeList.Items.Add($layout)
        }
        $window.Content.Measure([Windows.Size]::new(760,660)); $window.Content.Arrange([Windows.Rect]::new(0,0,760,660)); $window.Content.UpdateLayout()
        $first=$themeList.ItemContainerGenerator.ContainerFromIndex(0); $second=$themeList.ItemContainerGenerator.ContainerFromIndex(1)
        if ([Math]::Abs($first.TranslatePoint([Windows.Point]::new(0,0),$themeList).Y-$second.TranslatePoint([Windows.Point]::new(0,0),$themeList).Y) -gt 1) { throw 'Cards collapsed into a one-column list' }
        $GalleryFavoritesOnly.IsChecked=$false
        $State.Gallery=@(1..50 | ForEach-Object { @{Id=('ver-catalog-'+$_);ThemeId=('catalog-'+$_);Name=('Catalog '+$_);Version='1';Appearance='light';Author='Fixture'} })
        $State.GalleryOffset=50; $State.GalleryTotal=50; $script:GalleryVisibleLimit=24
        Refresh-GalleryCards
        if ($galleryList.Items.Count -ne 24 -or $script:GalleryMatchedCount -ne 50) { throw 'Remote preview pagination downloaded/rendered the whole catalog' }
        Show-MoreGalleryCards
        if ($galleryList.Items.Count -ne 36) { throw 'Load more failed after the catalog was indexed' }
        $GallerySearch.Text='Catalog 49'
        if ($galleryList.Items.Count -ne 1 -or $galleryList.Items[0].ThemeId -ne 'catalog-49') { throw 'Full catalog search failed for indexed but initially hidden themes' }
    } finally {
        $Settings.favorites=$oldFavorites; $State.Gallery=$oldGallery; $State.Current=$oldCurrent
        $State.GalleryTotal=$oldTotal; $State.GalleryOffset=$oldOffset
        $script:BrowserUpdating=$true
        try { $ThemeSearch.Text=''; $GallerySearch.Text=''; $ThemeFavoritesOnly.IsChecked=$false; $GalleryFavoritesOnly.IsChecked=$false } finally { $script:BrowserUpdating=$false }
        $script:BrowserDrafts.Clear()
        $script:GalleryVisibleLimit=24
        Refresh-ThemeList
    }
}

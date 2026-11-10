# ============================================================
#  Habit Widget - 바탕화면 습관 트래커 (Windows PowerShell 5.1 + WPF)
#  실행: HabitWidget.vbs 더블클릭
#  데이터: %APPDATA%\HabitWidget\data.json
# ============================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---- 중복 실행 방지 ----
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\HabitWidget_Singleton')
if (-not $script:Mutex.WaitOne(0, $false)) { exit }

$script:DataDir    = Join-Path $env:APPDATA 'HabitWidget'
$script:DataFile   = Join-Path $script:DataDir 'data.json'
$script:Utf8       = New-Object System.Text.UTF8Encoding($false)
$script:StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'HabitWidget.lnk'

$script:Habits    = New-Object System.Collections.ArrayList
$script:Log       = @{}
$script:WinPos    = $null
$script:Today     = (Get-Date).Date
$script:ViewMonth = $script:Today.AddDays(1 - $script:Today.Day)

# ---- 스타일 ----
function New-Brush([string]$hex) {
    $b = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex)
    $b.Freeze(); return $b
}
$script:C = @{
    Bg     = New-Brush '#F2161A20'
    Edge   = New-Brush '#2EFFFFFF'
    Line   = New-Brush '#14FFFFFF'
    Text   = New-Brush '#FFE6EDF3'
    Sub    = New-Brush '#FF8B949E'
    Faint  = New-Brush '#FF484F58'
    Empty  = New-Brush '#FF262C34'
    L1     = New-Brush '#FF0E4429'
    L2     = New-Brush '#FF006D32'
    L3     = New-Brush '#FF26A641'
    L4     = New-Brush '#FF39D353'
    Hover  = New-Brush '#12FFFFFF'
    Input  = New-Brush '#16FFFFFF'
    Danger = New-Brush '#FFF85149'
    Dark   = New-Brush '#FF0B1F10'
    Ring   = New-Brush '#CCFFFFFF'
    Clear  = [System.Windows.Media.Brushes]::Transparent
}
$script:FontUI   = New-Object System.Windows.Media.FontFamily('Segoe UI, Malgun Gothic')
$script:FontIcon = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
$script:G = @{
    Check  = [string][char]0xE73E
    Pin    = [string][char]0xE718
    Pinned = [string][char]0xE840
    Close  = [string][char]0xE8BB
    Add    = [string][char]0xE710
    Prev   = [string][char]0xE76B
    Next   = [string][char]0xE76C
    Remove = [string][char]0xE711
}
$script:DayNames = @('일','월','화','수','목','금','토')
$script:Hand = [System.Windows.Input.Cursors]::Hand

# ---- 데이터 ----
function Get-Key([datetime]$d) { return $d.ToString('yyyy-MM-dd') }
function New-Id { return [guid]::NewGuid().ToString('N').Substring(0, 8) }

function Load-Data {
    if (-not (Test-Path -LiteralPath $DataFile)) {
        $t = Get-Key $Today
        foreach ($n in @('물 2L 마시기', '30분 운동', '책 20쪽 읽기')) {
            [void]$Habits.Add(@{ id = (New-Id); name = $n; created = $t })
        }
        return
    }
    try {
        $j = [IO.File]::ReadAllText($DataFile, $Utf8) | ConvertFrom-Json
        foreach ($h in @($j.habits)) {
            if ($null -eq $h) { continue }
            $cr = if ($h.created) { [string]$h.created } else { '2000-01-01' }
            [void]$Habits.Add(@{ id = [string]$h.id; name = [string]$h.name; created = $cr })
        }
        if ($null -ne $j.log) {
            foreach ($p in $j.log.PSObject.Properties) {
                $list = New-Object 'System.Collections.Generic.List[string]'
                foreach ($v in @($p.Value)) { if ($v) { $list.Add([string]$v) } }
                $Log[$p.Name] = $list
            }
        }
        if ($null -ne $j.window) { $script:WinPos = $j.window }
    } catch {
        Copy-Item -LiteralPath $DataFile -Destination ("$DataFile.broken-" + (Get-Date -Format 'yyyyMMddHHmmss')) -ErrorAction SilentlyContinue
        [void][System.Windows.MessageBox]::Show("데이터 파일을 읽지 못해 백업해 두고 새로 시작합니다.`n`n$($_.Exception.Message)", 'Habit Widget')
    }
}

function Save-Data {
    try {
        if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
        $logOut = [ordered]@{}
        foreach ($k in ($Log.Keys | Sort-Object)) {
            if ($Log[$k].Count -gt 0) { $logOut[$k] = [string[]]$Log[$k].ToArray() }
        }
        $hs = @()
        foreach ($h in $Habits) { $hs += [ordered]@{ id = $h.id; name = $h.name; created = $h.created } }
        $obj = [ordered]@{
            version = 1
            habits  = $hs
            log     = $logOut
            window  = [ordered]@{ left = [int]$win.Left; top = [int]$win.Top; topmost = [bool]$win.Topmost }
        }
        $json = ConvertTo-Json -InputObject $obj -Depth 6
        $tmp = "$DataFile.tmp"
        [IO.File]::WriteAllText($tmp, $json, $Utf8)
        Move-Item -LiteralPath $tmp -Destination $DataFile -Force
    } catch { }
}

function Test-Done([string]$id, [string]$k) {
    return ($Log.ContainsKey($k) -and $Log[$k].Contains($id))
}

function Switch-Done([string]$id, [string]$k) {
    if (-not $Log.ContainsKey($k)) { $Log[$k] = New-Object 'System.Collections.Generic.List[string]' }
    if ($Log[$k].Contains($id)) { [void]$Log[$k].Remove($id) } else { $Log[$k].Add($id) }
    Save-Data; Render
}

function Add-Habit([string]$name) {
    $name = $name.Trim()
    if (-not $name) { return }
    [void]$Habits.Add(@{ id = (New-Id); name = $name; created = (Get-Key $Today) })
    Save-Data; Render
}

function Remove-Habit([string]$id) {
    $h = $null
    foreach ($x in $Habits) { if ($x.id -eq $id) { $h = $x } }
    if ($null -eq $h) { return }
    $r = [System.Windows.MessageBox]::Show($win, "'$($h.name)' 습관을 삭제할까요?`n기록도 함께 지워집니다.", '습관 삭제', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $Habits.Remove($h)
    foreach ($k in @($Log.Keys)) { [void]$Log[$k].Remove($id) }
    Save-Data; Render
}

# 그날 기준 [완료 수, 대상 습관 수]
function Get-DayStat([datetime]$d) {
    $k = Get-Key $d; $total = 0; $done = 0
    foreach ($h in $Habits) {
        $isDone = Test-Done $h.id $k
        if ($h.created -le $k -or $isDone) {
            $total++
            if ($isDone) { $done++ }
        }
    }
    return @($done, $total)
}

function Get-LevelBrush([int]$done, [int]$total) {
    if ($total -le 0 -or $done -le 0) { return $C.Empty }
    $r = $done / $total
    if ($r -ge 1)    { return $C.L4 }
    if ($r -ge 0.66) { return $C.L3 }
    if ($r -ge 0.33) { return $C.L2 }
    return $C.L1
}

# ---- UI 헬퍼 ----
function New-Text([string]$t, [double]$size = 12, $brush = $null, [string]$weight = 'Normal') {
    if ($null -eq $brush) { $brush = $C.Text }
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $t; $tb.FontSize = $size; $tb.Foreground = $brush; $tb.FontFamily = $FontUI
    $tb.FontWeight = [System.Windows.FontWeights]::$weight
    $tb.VerticalAlignment = 'Center'
    return $tb
}

function New-Glyph([string]$g, [double]$size = 11, $brush = $null) {
    if ($null -eq $brush) { $brush = $C.Sub }
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $g; $t.FontFamily = $FontIcon; $t.FontSize = $size; $t.Foreground = $brush
    $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'
    return $t
}

function New-IconButton([string]$g, [string]$tip, [double]$size = 26) {
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $size; $b.Height = $size; $b.CornerRadius = 6
    $b.Background = $C.Clear; $b.Cursor = $Hand; $b.ToolTip = $tip
    $b.Child = New-Glyph $g 10
    $b.Add_MouseEnter({ param($s, $e) $s.Background = $C.Hover })
    $b.Add_MouseLeave({ param($s, $e) $s.Background = $C.Clear })
    return $b
}

function Add-Col($grid, $width) {
    $cd = New-Object System.Windows.Controls.ColumnDefinition
    if ($width -eq '*') { $cd.Width = New-Object System.Windows.GridLength(1, 'Star') }
    elseif ($width -eq 'auto') { $cd.Width = [System.Windows.GridLength]::Auto }
    else { $cd.Width = New-Object System.Windows.GridLength([double]$width) }
    $grid.ColumnDefinitions.Add($cd)
}

function Set-Col($el, [int]$col) { [System.Windows.Controls.Grid]::SetColumn($el, $col) }

function New-RowGrid {
    # 체크 | 이름 | 이번 주 7칸 | 삭제
    $g = New-Object System.Windows.Controls.Grid
    Add-Col $g 22; Add-Col $g '*'; Add-Col $g 'auto'; Add-Col $g 22
    return $g
}

# ---- 창 ----
$win = New-Object System.Windows.Window
$win.Title = 'Habit Widget'
$win.WindowStyle = 'None'; $win.AllowsTransparency = $true; $win.Background = $C.Clear
$win.ShowInTaskbar = $false; $win.ResizeMode = 'NoResize'; $win.SizeToContent = 'Height'
$win.Width = 340; $win.FontFamily = $FontUI
[System.Windows.Media.TextOptions]::SetTextFormattingMode($win, 'Display')

$shell = New-Object System.Windows.Controls.Border
$shell.Margin = 10; $shell.CornerRadius = 14
$shell.Background = $C.Bg; $shell.BorderBrush = $C.Edge; $shell.BorderThickness = 1
$shell.Padding = New-Object System.Windows.Thickness(16, 14, 16, 16)
$fx = New-Object System.Windows.Media.Effects.DropShadowEffect
$fx.BlurRadius = 18; $fx.ShadowDepth = 2; $fx.Opacity = 0.45; $fx.Color = [System.Windows.Media.Colors]::Black
$shell.Effect = $fx
$win.Content = $shell

$root = New-Object System.Windows.Controls.StackPanel
$shell.Child = $root

# 헤더
$header = New-Object System.Windows.Controls.Grid
Add-Col $header '*'; Add-Col $header 'auto'
$titleStack = New-Object System.Windows.Controls.StackPanel
[void]$titleStack.Children.Add((New-Text '오늘의 습관' 15 $C.Text 'SemiBold'))
$script:SubText = New-Text '' 11.5 $C.Sub
$SubText.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
[void]$titleStack.Children.Add($SubText)
$header.Children.Add($titleStack) | Out-Null

$btnStack = New-Object System.Windows.Controls.StackPanel
$btnStack.Orientation = 'Horizontal'; $btnStack.VerticalAlignment = 'Top'
Set-Col $btnStack 1
$script:PinBtn = New-IconButton $G.Pin '항상 위에 표시'
$closeBtn = New-IconButton $G.Close '닫기'
[void]$btnStack.Children.Add($PinBtn); [void]$btnStack.Children.Add($closeBtn)
$header.Children.Add($btnStack) | Out-Null
[void]$root.Children.Add($header)

# 진행 막대
$script:ProgGrid = New-Object System.Windows.Controls.Grid
$ProgGrid.Height = 4; $ProgGrid.Margin = New-Object System.Windows.Thickness(0, 10, 0, 10)
[void]$root.Children.Add($ProgGrid)

# 습관 목록
$script:ListPanel = New-Object System.Windows.Controls.StackPanel
[void]$root.Children.Add($ListPanel)

# 추가 입력칸
$inputBorder = New-Object System.Windows.Controls.Border
$inputBorder.CornerRadius = 8; $inputBorder.Background = $C.Input
$inputBorder.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
$inputBorder.Padding = New-Object System.Windows.Thickness(10, 0, 6, 0)
$inputGrid = New-Object System.Windows.Controls.Grid
Add-Col $inputGrid 16; Add-Col $inputGrid '*'
$inputGrid.Children.Add((New-Glyph $G.Add 10)) | Out-Null
$script:InputBox = New-Object System.Windows.Controls.TextBox
$InputBox.Background = $C.Clear; $InputBox.BorderThickness = 0; $InputBox.Foreground = $C.Text
$InputBox.CaretBrush = $C.Text; $InputBox.FontSize = 12.5; $InputBox.MaxLength = 30
$InputBox.Padding = New-Object System.Windows.Thickness(4, 7, 4, 7)
$InputBox.VerticalContentAlignment = 'Center'
Set-Col $InputBox 1
$script:Placeholder = New-Text '새 습관 입력 후 Enter' 12 $C.Faint
$Placeholder.IsHitTestVisible = $false; $Placeholder.Margin = New-Object System.Windows.Thickness(7, 0, 0, 0)
Set-Col $Placeholder 1
$inputGrid.Children.Add($InputBox) | Out-Null
$inputGrid.Children.Add($Placeholder) | Out-Null
$inputBorder.Child = $inputGrid
[void]$root.Children.Add($inputBorder)

$InputBox.Add_TextChanged({
    $Placeholder.Visibility = if ($InputBox.Text.Length -gt 0) { 'Collapsed' } else { 'Visible' }
})
$InputBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') {
        $name = $s.Text; $s.Text = ''
        Add-Habit $name
    } elseif ($e.Key -eq 'Escape') {
        $s.Text = ''
        [System.Windows.Input.Keyboard]::ClearFocus()
    }
})

# 구분선
$sep = New-Object System.Windows.Controls.Border
$sep.Height = 1; $sep.Background = $C.Line
$sep.Margin = New-Object System.Windows.Thickness(0, 16, 0, 12)
[void]$root.Children.Add($sep)

# 월간 잔디 헤더
$monthHeader = New-Object System.Windows.Controls.Grid
Add-Col $monthHeader '*'; Add-Col $monthHeader 'auto'
$monthTitleStack = New-Object System.Windows.Controls.StackPanel
$script:MonthTitle = New-Text '' 13 $C.Text 'SemiBold'
$script:MonthStat = New-Text '' 11 $C.Sub
$MonthStat.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
[void]$monthTitleStack.Children.Add($MonthTitle)
[void]$monthTitleStack.Children.Add($MonthStat)
$monthHeader.Children.Add($monthTitleStack) | Out-Null
$navStack = New-Object System.Windows.Controls.StackPanel
$navStack.Orientation = 'Horizontal'; $navStack.VerticalAlignment = 'Top'
Set-Col $navStack 1
$prevBtn = New-IconButton $G.Prev '이전 달' 24
$script:NextBtn = New-IconButton $G.Next '다음 달' 24
[void]$navStack.Children.Add($prevBtn); [void]$navStack.Children.Add($NextBtn)
$monthHeader.Children.Add($navStack) | Out-Null
[void]$root.Children.Add($monthHeader)

# 요일 라벨 (월요일 시작)
$dowGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
$dowGrid.Columns = 7; $dowGrid.Margin = New-Object System.Windows.Thickness(0, 10, 0, 2)
foreach ($n in @('월','화','수','목','금','토','일')) {
    $t = New-Text $n 10 $C.Faint; $t.HorizontalAlignment = 'Center'
    [void]$dowGrid.Children.Add($t)
}
[void]$root.Children.Add($dowGrid)

$script:MonthGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
$MonthGrid.Columns = 7
[void]$root.Children.Add($MonthGrid)

# 범례
$legend = New-Object System.Windows.Controls.StackPanel
$legend.Orientation = 'Horizontal'; $legend.HorizontalAlignment = 'Right'
$legend.Margin = New-Object System.Windows.Thickness(0, 8, 2, 0)
$lt1 = New-Text '적음' 10 $C.Faint; $lt1.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
[void]$legend.Children.Add($lt1)
foreach ($b in @($C.Empty, $C.L1, $C.L2, $C.L3, $C.L4)) {
    $sq = New-Object System.Windows.Controls.Border
    $sq.Width = 10; $sq.Height = 10; $sq.CornerRadius = 2.5; $sq.Background = $b
    $sq.Margin = New-Object System.Windows.Thickness(1.5, 0, 1.5, 0)
    [void]$legend.Children.Add($sq)
}
$lt2 = New-Text '전부' 10 $C.Faint; $lt2.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
[void]$legend.Children.Add($lt2)
[void]$root.Children.Add($legend)

# ---- 렌더링 ----
function Render-Header {
    $todayKey = Get-Key $Today
    $stat = Get-DayStat $Today
    $SubText.Text = '{0}월 {1}일 ({2}) · {3}/{4} 완료' -f $Today.Month, $Today.Day, $DayNames[[int]$Today.DayOfWeek], $stat[0], $stat[1]

    $ProgGrid.Children.Clear(); $ProgGrid.ColumnDefinitions.Clear()
    $track = New-Object System.Windows.Controls.Border
    $track.CornerRadius = 2; $track.Background = $C.Empty
    [System.Windows.Controls.Grid]::SetColumnSpan($track, 2)
    $cd1 = New-Object System.Windows.Controls.ColumnDefinition
    $cd2 = New-Object System.Windows.Controls.ColumnDefinition
    $done = [double]$stat[0]; $rest = [double]([Math]::Max(0, $stat[1] - $stat[0]))
    if ($stat[1] -eq 0) { $rest = 1 }
    $cd1.Width = New-Object System.Windows.GridLength($done, 'Star')
    $cd2.Width = New-Object System.Windows.GridLength($rest, 'Star')
    $ProgGrid.ColumnDefinitions.Add($cd1); $ProgGrid.ColumnDefinitions.Add($cd2)
    [void]$ProgGrid.Children.Add($track)
    if ($done -gt 0) {
        $fill = New-Object System.Windows.Controls.Border
        $fill.CornerRadius = 2; $fill.Background = $C.L4
        [void]$ProgGrid.Children.Add($fill)
    }

    $PinBtn.Child.Text = if ($win.Topmost) { $G.Pinned } else { $G.Pin }
    $PinBtn.Child.Foreground = if ($win.Topmost) { $C.L4 } else { $C.Sub }
}

function Render-List {
    $ListPanel.Children.Clear()
    $todayKey = Get-Key $Today

    if ($Habits.Count -eq 0) {
        $empty = New-Text '아래에 첫 습관을 추가해 보세요.' 12 $C.Sub
        $empty.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
        [void]$ListPanel.Children.Add($empty)
        return
    }

    # 최근 7일 요일 라벨
    $lab = New-RowGrid
    $lab.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
    $labStack = New-Object System.Windows.Controls.StackPanel
    $labStack.Orientation = 'Horizontal'
    Set-Col $labStack 2
    for ($i = 6; $i -ge 0; $i--) {
        $d = $Today.AddDays(-$i)
        $t = New-Text $DayNames[[int]$d.DayOfWeek] 9 $(if ($i -eq 0) { $C.Sub } else { $C.Faint })
        $t.Width = 13; $t.TextAlignment = 'Center'
        $t.Margin = New-Object System.Windows.Thickness(1, 0, 1, 0)
        [void]$labStack.Children.Add($t)
    }
    [void]$lab.Children.Add($labStack)
    $labWrap = New-Object System.Windows.Controls.Border
    $labWrap.Padding = New-Object System.Windows.Thickness(6, 0, 6, 0)
    $labWrap.Margin = New-Object System.Windows.Thickness(-6, 0, -6, 0)
    $labWrap.Child = $lab
    [void]$ListPanel.Children.Add($labWrap)

    foreach ($h in $Habits) {
        $doneToday = Test-Done $h.id $todayKey

        $row = New-Object System.Windows.Controls.Border
        $row.CornerRadius = 8; $row.Background = $C.Clear
        $row.Padding = New-Object System.Windows.Thickness(6, 5, 6, 5)
        $row.Margin = New-Object System.Windows.Thickness(-6, 1, -6, 1)
        $g = New-RowGrid
        $row.Child = $g

        # 체크박스
        $chk = New-Object System.Windows.Controls.Border
        $chk.Width = 20; $chk.Height = 20; $chk.CornerRadius = 6; $chk.Cursor = $Hand
        $chk.HorizontalAlignment = 'Left'
        if ($doneToday) {
            $chk.Background = $C.L4
            $chk.Child = New-Glyph $G.Check 11 $C.Dark
        } else {
            $chk.Background = $C.Clear; $chk.BorderBrush = $C.Faint; $chk.BorderThickness = 1.5
        }
        $chk.Tag = @{ id = $h.id; key = $todayKey }
        $chk.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Switch-Done $s.Tag.id $s.Tag.key })
        [void]$g.Children.Add($chk)

        # 이름
        $nm = New-Text $h.name 13 $(if ($doneToday) { $C.Sub } else { $C.Text })
        $nm.Margin = New-Object System.Windows.Thickness(8, 0, 8, 0)
        $nm.TextTrimming = 'CharacterEllipsis'; $nm.ToolTip = $h.name; $nm.Cursor = $Hand
        if ($doneToday) { $nm.TextDecorations = [System.Windows.TextDecorations]::Strikethrough }
        $nm.Tag = @{ id = $h.id; key = $todayKey }
        $nm.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Switch-Done $s.Tag.id $s.Tag.key })
        Set-Col $nm 1
        [void]$g.Children.Add($nm)

        # 이번 주 잔디 (최근 7일, 클릭으로 지난 날 수정)
        $week = New-Object System.Windows.Controls.StackPanel
        $week.Orientation = 'Horizontal'; $week.VerticalAlignment = 'Center'
        Set-Col $week 2
        for ($i = 6; $i -ge 0; $i--) {
            $d = $Today.AddDays(-$i); $k = Get-Key $d
            $isDone = Test-Done $h.id $k
            $cell = New-Object System.Windows.Controls.Border
            $cell.Width = 13; $cell.Height = 13; $cell.CornerRadius = 3; $cell.Cursor = $Hand
            $cell.Margin = New-Object System.Windows.Thickness(1, 0, 1, 0)
            $cell.Background = if ($isDone) { $C.L3 } else { $C.Empty }
            if ($i -eq 0) { $cell.BorderBrush = $C.Ring; $cell.BorderThickness = 1 }
            $cell.ToolTip = '{0}/{1} ({2}) {3}' -f $d.Month, $d.Day, $DayNames[[int]$d.DayOfWeek], $(if ($isDone) { '완료' } else { '미완료' })
            $cell.Tag = @{ id = $h.id; key = $k }
            $cell.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Switch-Done $s.Tag.id $s.Tag.key })
            [void]$week.Children.Add($cell)
        }
        [void]$g.Children.Add($week)

        # 삭제 버튼 (항상 표시, 마우스 올리면 빨간색)
        $del = New-Object System.Windows.Controls.Border
        $del.Width = 20; $del.Height = 20; $del.CornerRadius = 5; $del.Cursor = $Hand
        $del.HorizontalAlignment = 'Right'; $del.ToolTip = '삭제'
        $del.Background = $C.Clear   # 배경이 있어야 칸 전체가 클릭됨
        $del.Child = New-Glyph $G.Remove 9 $C.Faint
        $del.Tag = $h.id
        $del.Add_MouseEnter({ param($s, $e) $s.Background = $C.Hover; $s.Child.Foreground = $C.Danger })
        $del.Add_MouseLeave({ param($s, $e) $s.Background = $C.Clear; $s.Child.Foreground = $C.Faint })
        $del.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Remove-Habit $s.Tag })
        Set-Col $del 3
        [void]$g.Children.Add($del)

        # 습관 줄 우클릭 메뉴: 삭제
        $rowMenu = New-Object System.Windows.Controls.ContextMenu
        $miDel = New-Object System.Windows.Controls.MenuItem
        $miDel.Header = "'$($h.name)' 삭제"; $miDel.Tag = $h.id
        $miDel.Add_Click({ param($s, $e) Remove-Habit $s.Tag })
        [void]$rowMenu.Items.Add($miDel)
        $row.ContextMenu = $rowMenu

        $row.Add_MouseEnter({ param($s, $e) $s.Background = $C.Hover })
        $row.Add_MouseLeave({ param($s, $e) $s.Background = $C.Clear })
        [void]$ListPanel.Children.Add($row)
    }
}

function Render-Month {
    $MonthGrid.Children.Clear()
    $first = $ViewMonth
    $days = [DateTime]::DaysInMonth($first.Year, $first.Month)
    $MonthTitle.Text = '{0}년 {1}월' -f $first.Year, $first.Month

    $curMonth = $Today.AddDays(1 - $Today.Day)
    $NextBtn.Opacity = if ($first -ge $curMonth) { 0.3 } else { 1 }

    $lead = ([int]$first.DayOfWeek + 6) % 7
    for ($i = 0; $i -lt $lead; $i++) {
        [void]$MonthGrid.Children.Add((New-Object System.Windows.Controls.Border))
    }

    $sumDone = 0; $sumTotal = 0; $perfect = 0
    for ($dd = 1; $dd -le $days; $dd++) {
        $d = $first.AddDays($dd - 1)
        $cell = New-Object System.Windows.Controls.Border
        $cell.Height = 30; $cell.CornerRadius = 6
        $cell.Margin = New-Object System.Windows.Thickness(2)
        $num = New-Text ([string]$dd) 10.5 $C.Sub
        $num.HorizontalAlignment = 'Center'
        $cell.Child = $num

        if ($d -gt $Today) {
            $cell.Background = $C.Clear; $cell.BorderBrush = $C.Line; $cell.BorderThickness = 1
            $num.Foreground = $C.Faint
        } else {
            $st = Get-DayStat $d
            $sumDone += $st[0]; $sumTotal += $st[1]
            if ($st[1] -gt 0 -and $st[0] -eq $st[1]) { $perfect++ }
            $br = Get-LevelBrush $st[0] $st[1]
            $cell.Background = $br
            if ($br -eq $C.L3 -or $br -eq $C.L4) { $num.Foreground = $C.Dark; $num.FontWeight = [System.Windows.FontWeights]::SemiBold }
            elseif ($br -ne $C.Empty) { $num.Foreground = $C.Text }
            $cell.ToolTip = '{0}월 {1}일 ({2}) · {3}/{4} 완료' -f $d.Month, $d.Day, $DayNames[[int]$d.DayOfWeek], $st[0], $st[1]
            if ($d -eq $Today) { $cell.BorderBrush = $C.Ring; $cell.BorderThickness = 1.5 }
        }
        [void]$MonthGrid.Children.Add($cell)
    }

    if ($sumTotal -gt 0) {
        $MonthStat.Text = '달성률 {0}% · 모두 완료한 날 {1}일' -f [int][Math]::Round(100.0 * $sumDone / $sumTotal), $perfect
    } else {
        $MonthStat.Text = '기록 없음'
    }
}

function Render {
    try { Render-Header; Render-List; Render-Month } catch {
        [void][System.Windows.MessageBox]::Show("화면을 그리는 중 오류: $($_.Exception.Message)", 'Habit Widget')
    }
}

# ---- 자동 실행 ----
function Test-Autostart { return (Test-Path -LiteralPath $StartupLnk) }
function Set-Autostart([bool]$on) {
    if ($on) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($StartupLnk)
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $lnk.Arguments = '"' + (Join-Path $PSScriptRoot 'HabitWidget.vbs') + '"'
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.Description = 'Habit Widget'
        $lnk.Save()
    } else {
        Remove-Item -LiteralPath $StartupLnk -ErrorAction SilentlyContinue
    }
}

# ---- 이벤트 ----
$shell.Add_MouseLeftButtonDown({
    try { $win.DragMove() } catch { }
    Save-Data
})

$PinBtn.Add_MouseLeftButtonDown({
    param($s, $e) $e.Handled = $true
    $win.Topmost = -not $win.Topmost
    Save-Data; Render-Header
})
$closeBtn.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $win.Close() })

$prevBtn.Add_MouseLeftButtonDown({
    param($s, $e) $e.Handled = $true
    $script:ViewMonth = $ViewMonth.AddMonths(-1); Render-Month
})
$NextBtn.Add_MouseLeftButtonDown({
    param($s, $e) $e.Handled = $true
    $curMonth = $Today.AddDays(1 - $Today.Day)
    if ($ViewMonth -lt $curMonth) { $script:ViewMonth = $ViewMonth.AddMonths(1); Render-Month }
})

# 오른쪽 클릭 메뉴
$menu = New-Object System.Windows.Controls.ContextMenu
$miTop = New-Object System.Windows.Controls.MenuItem
$miTop.Header = '항상 위에 표시'; $miTop.IsCheckable = $true
$miAuto = New-Object System.Windows.Controls.MenuItem
$miAuto.Header = 'Windows 시작 시 자동 실행'; $miAuto.IsCheckable = $true
$miFolder = New-Object System.Windows.Controls.MenuItem
$miFolder.Header = '데이터 폴더 열기'
$miExit = New-Object System.Windows.Controls.MenuItem
$miExit.Header = '종료'
foreach ($m in @($miTop, $miAuto, $miFolder)) { [void]$menu.Items.Add($m) }
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miExit)
$shell.ContextMenu = $menu

$menu.Add_Opened({
    $miTop.IsChecked = $win.Topmost
    $miAuto.IsChecked = Test-Autostart
})
$miTop.Add_Click({ $win.Topmost = $miTop.IsChecked; Save-Data; Render-Header })
$miAuto.Add_Click({
    try { Set-Autostart $miAuto.IsChecked } catch {
        [void][System.Windows.MessageBox]::Show("자동 실행 설정 실패: $($_.Exception.Message)", 'Habit Widget')
    }
})
$miFolder.Add_Click({
    if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    Start-Process explorer.exe $DataDir
})
$miExit.Add_Click({ $win.Close() })

$win.Add_Closing({ Save-Data })

# 자정이 지나면 날짜 갱신
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({
    $now = (Get-Date).Date
    if ($now -ne $Today) {
        $wasCurrent = ($ViewMonth -eq $Today.AddDays(1 - $Today.Day))
        $script:Today = $now
        if ($wasCurrent) { $script:ViewMonth = $now.AddDays(1 - $now.Day) }
        Render
    }
})

# ---- 시작 ----
Load-Data

$wa = [System.Windows.SystemParameters]::WorkArea
$left = $wa.Right - $win.Width - 12
$top  = $wa.Top + 40
if ($null -ne $WinPos) {
    try {
        $l = [double]$WinPos.left; $t = [double]$WinPos.top
        $vl = [System.Windows.SystemParameters]::VirtualScreenLeft
        $vt = [System.Windows.SystemParameters]::VirtualScreenTop
        $vw = [System.Windows.SystemParameters]::VirtualScreenWidth
        $vh = [System.Windows.SystemParameters]::VirtualScreenHeight
        if ($l -ge ($vl - 20) -and $l -le ($vl + $vw - 80) -and $t -ge ($vt - 20) -and $t -le ($vt + $vh - 80)) {
            $left = $l; $top = $t
        }
        $win.Topmost = [bool]$WinPos.topmost
    } catch { }
}
$win.WindowStartupLocation = 'Manual'
$win.Left = $left; $win.Top = $top

Render
$timer.Start()
Save-Data
[void]$win.ShowDialog()
$timer.Stop()
$script:Mutex.ReleaseMutex()

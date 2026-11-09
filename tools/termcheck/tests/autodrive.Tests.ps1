# autodrive.Tests.ps1 -- offline checks of tools/termcheck/autodrive.ps1 (plain asserts).
#
#     pwsh -NoProfile -File tools/termcheck/tests/autodrive.Tests.ps1
#
# Nothing here opens a window or sends input: the driver is loaded with -LibraryOnly,
# the wrapper stays in dry mode (TcAuto.Inj.Live = false, checked first), and the
# dry-run cases run autodrive.ps1 without -Live. termcheck --list-items runs under
# C:\bin\Git\bin\bash.exe and needs no terminal. Exit 0 = all PASS.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$driver = Join-Path $here '..\autodrive.ps1'
$scratch = if ($env:AUTODRIVE_TEST_TMP) { $env:AUTODRIVE_TEST_TMP } else { Join-Path ([System.IO.Path]::GetTempPath()) ("autodrive-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

$script:pass = 0; $script:fail = 0
function Ok([string]$title, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Output "PASS: $title" }
    else { $script:fail++; Write-Output ("FAIL: $title" + ($detail ? "  -- $detail" : '')) }
}

. $driver -LibraryOnly
Ok 'the wrapper is in dry mode after loading (Live = false)' (-not [TcAuto.Inj]::Live)
if ([TcAuto.Inj]::Live) { Write-Output 'refusing to go on with Live set'; exit 1 }

# ---- key table vs termcheck --list-items --------------------------------------------
$table = Get-KeyTable
$list = Get-ListItems
Ok "--list-items gives 117 lines ($($list.Count))" ($list.Count -eq 117)
$p = Test-KeyTable $table $list
Ok 'every termcheck item has a table entry and every entry is an item' ($p.Count -eq 0) ($p -join '; ')
Ok 'the table has no Alt+F4' (-not $table.Contains('Alt+F4'))
$danger = & $script:GitBash (Join-Path $here '..\termcheck.sh') --list-items --with-dangerous
$p = Test-KeyTable $table @($danger)
Ok 'with --with-dangerous the check reports the missing Alt+F4 entry' (($p -join ';') -match "no table entry for item 'Alt\+F4'") ($p -join '; ')
$p = Test-KeyTable $table (@($list) + "arrows`tMeta+Up`tkey`tkbMetaUp")
Ok 'an unknown termcheck item is reported' (($p -join ';') -match "Meta\+Up") ($p -join '; ')
$p = Test-KeyTable $table @($list | Where-Object { $_ -notmatch "`tF7`t" })
Ok 'a table entry without an item is reported' (($p -join ';') -match "table entry 'F7'") ($p -join '; ')
Ok 'arrows are extended (E0) keys' ((New-KeyBatch @() 'Up')[0].Ext)
Ok 'F5 is not extended' (-not (New-KeyBatch @() 'F5')[0].Ext)
Ok 'keypad 5 NumLock off = VK_CLEAR scan 0x4C, not extended' ($table['Keypad5-NumLockOff'].Key -eq 'KpClear' -and $KeyDefs.KpClear[0] -eq 0x0C -and $KeyDefs.KpClear[1] -eq 0x4C -and $KeyDefs.KpClear[2] -eq 0)
Ok 'keypad 5 NumLock on = VK_NUMPAD5 scan 0x4C' ($KeyDefs.Kp5[0] -eq 0x65 -and $KeyDefs.Kp5[1] -eq 0x4C -and $table['Keypad5-NumLockOn'].NumLock -eq 'on')
Ok 'keypad Enter = VK_RETURN scan 0x1C extended' ($KeyDefs.KpEnter[0] -eq 0x0D -and $KeyDefs.KpEnter[2] -eq 1)
Ok 'NumLock is toggled with the extended flag (scan 0x45)' ($KeyDefs.NumLock[1] -eq 0x45 -and $KeyDefs.NumLock[2] -eq 1)
$b = New-KeyBatch @('LAlt', 'LShift') 'X'
Ok 'Alt+Shift+X: modifiers held around the key, released in reverse' ((($b | ForEach-Object { $_.ToString().Substring(0, 3) }) -join ' ') -eq '+LA +LS +X( -X( -LS -LA')
$z = New-UniBatch 0x0436
Ok 'zhe: KEYEVENTF_UNICODE with wVk 0 and wScan 0x0436, down and up' ($z.Count -eq 2 -and $z[0].Kind -eq 'uni' -and $z[0].Vk -eq 0 -and $z[0].Scan -eq 0x0436 -and $z[1].Up)
Ok 'mintty skip-list is Alt+F2, Alt+F3, Alt+F8' ((($SkipList['msys2']) -join ',') -eq 'Alt+F2,Alt+F3,Alt+F8')

# ---- the forbidden keys: refused by the wrapper, nothing recorded ---------------------
$forbidden = [ordered]@{
    'Win (left)' = @(@(), 'LWin'); 'Win (right)' = @(@(), 'RWin'); 'Menu key' = @(@(), 'Apps')
    'Alt+Tab' = @(@('LAlt'), 'Tab'); 'Alt+Esc' = @(@('LAlt'), 'Esc'); 'Alt+Space' = @(@('LAlt'), 'Space')
    'Alt+F4' = @(@('LAlt'), 'F4'); 'Ctrl+Esc' = @(@('LCtrl'), 'Esc'); 'Ctrl+Shift+Esc' = @(@('LCtrl', 'LShift'), 'Esc')
    'Ctrl+Alt+Del' = @(@('LCtrl', 'LAlt'), 'Del'); 'Right Shift' = @(@(), 'RShift'); 'Right Ctrl' = @(@(), 'RCtrl')
}
foreach ($k in $forbidden.Keys) {
    [TcAuto.Inj]::Plan.Clear()
    $batch = New-KeyBatch $forbidden[$k][0] $forbidden[$k][1]
    $threw = $false
    try { [TcAuto.Inj]::Send($batch) } catch { $threw = $true }
    Ok "forbidden: $k is refused by the wrapper, nothing recorded, nothing held" ($threw -and [TcAuto.Inj]::Plan.Count -eq 0 -and [TcAuto.Inj]::Held.Count -eq 0)
}
$t = New-KeyBatch @('LAlt') 'Tab'
Ok 'forbidden: Alt then Tab in two batches is refused too (held modifiers are tracked)' ($null -eq [TcAuto.Inj]::Check(@($t[0])) -and $null -ne [TcAuto.Inj]::Check($t))
foreach ($id in $table.Keys) {
    $e = $table[$id]
    if ($e.Kind -ne 'key') { continue }
    $why = [TcAuto.Inj]::Check((New-KeyBatch $e.Mods $e.Key))
    if ($why) { Ok "table entry $id passes the wrapper" $false $why }
}
Ok 'every key entry of the table passes the forbidden-key check' $true
[TcAuto.Inj]::Plan.Clear()
[TcAuto.Inj]::Aborted = $true
$threw = $false
try { [TcAuto.Inj]::Send((New-KeyBatch @() 'Up')) } catch { $threw = $true }
Ok 'after an abort a key-down is refused' ($threw -and [TcAuto.Inj]::Plan.Count -eq 0)
[TcAuto.Inj]::Send(@((New-KeyEv 'LCtrl' $true), (New-MouseEv up 1)))
Ok 'after an abort key-ups and mouse-ups pass' ([TcAuto.Inj]::Plan.Count -eq 1)
[TcAuto.Inj]::Aborted = $false
[TcAuto.Inj]::Plan.Clear()
[TcAuto.Inj]::Send(@((New-KeyEv 'LCtrl' $false)))
[TcAuto.Inj]::ReleaseAll()
Ok 'ReleaseAll releases a modifier the driver holds' ([TcAuto.Inj]::Held.Count -eq 0 -and ([TcAuto.Inj]::Plan[-1] -match '^release: .*-release\(vk=0xA2'))

# ---- sync lines -------------------------------------------------------------------------
$r = ConvertFrom-SyncLine 'ready arrows Shift+Up'
Ok 'sync: ready key line' ($r.Type -eq 'ready' -and $r.Group -eq 'arrows' -and $r.Id -eq 'Shift+Up' -and $null -eq $r.Target)
$r = ConvertFrom-SyncLine 'ready mouse Drag target 10 16 60 18 screen 80 24'
Ok 'sync: ready drag line with four target numbers and the screen' (($r.Target -join ',') -eq '10,16,60,18' -and ($r.Screen -join 'x') -eq '80x24')
$r = ConvertFrom-SyncLine 'done Drag OK cell 10 16 cell2 60 18'
Ok 'sync: done with cell and cell2' ($r.Result -eq 'OK' -and ($r.Cell -join ',') -eq '10,16' -and ($r.Cell2 -join ',') -eq '60,18')
$r = ConvertFrom-SyncLine 'retry Click-Left DIFF cell 13 6'
Ok 'sync: retry line' ($r.Type -eq 'retry' -and $r.Id -eq 'Click-Left' -and ($r.Cell -join ',') -eq '13,6')
$r = ConvertFrom-SyncLine 'done Alt+F2 NONE skipped'
Ok 'sync: skipped' ($r.Skipped -and $r.Result -eq 'NONE')
$r = ConvertFrom-SyncLine 'done Ctrl+\ OK'
Ok 'sync: an id with a backslash' ($r.Id -eq 'Ctrl+\')
$r = ConvertFrom-SyncLine 'done Resize OK screen 83 26'
Ok 'sync: resize done with the new screen' (($r.Screen -join 'x') -eq '83x26')
$r = ConvertFrom-SyncLine 'end incomplete 130'
Ok 'sync: end line' ($r.Type -eq 'end' -and $r.Status -eq 'incomplete' -and $r.Rc -eq 130)
Ok 'sync: finish-wait' ((ConvertFrom-SyncLine 'finish-wait').Type -eq 'finish-wait')
Ok 'sync: unknown line' ((ConvertFrom-SyncLine 'hello world').Type -eq 'unknown')

# the reader: only LF-terminated lines, while the writer keeps the file open
$sf = Join-Path $scratch 'sync-reader.txt'
$w = [System.IO.FileStream]::new($sf, 'Create', 'Write', 'ReadWrite')
$bytes = [System.Text.Encoding]::UTF8.GetBytes("ready arrows Up`ndone Up OK`nready arrows Do")
$w.Write($bytes, 0, $bytes.Length); $w.Flush()
$rd = [SyncReader]::new($sf)
$got = $rd.ReadLines()
Ok 'reader: two complete lines while the writer holds the file' ($got.Count -eq 2 -and $got[1] -eq 'done Up OK') ($got -join '|')
$bytes = [System.Text.Encoding]::UTF8.GetBytes("wn`n")
$w.Write($bytes, 0, $bytes.Length); $w.Flush()
$got = $rd.ReadLines()
Ok 'reader: the partial line is completed by the next write' ($got.Count -eq 1 -and $got[0] -eq 'ready arrows Down') ($got -join '|')
Ok 'reader: nothing new = no lines' ($rd.ReadLines().Count -eq 0)
$w.Dispose()

# ---- calibration ---------------------------------------------------------------------
Ok 'Norm: left edge 0, right edge 65535' ([TcAuto.Inj]::Norm(0, 0, 1920) -eq 0 -and [TcAuto.Inj]::Norm(1919, 0, 1920) -eq 65535)
Ok 'Norm: a virtual desktop starting left of 0' ([TcAuto.Inj]::Norm(-1920, -1920, 3840) -eq 0 -and [TcAuto.Inj]::Norm(0, -1920, 3840) -eq 32776)
$client = [TcAuto.RECT]@{ Left = 100; Top = 200; Right = 100 + 8 + 800 + 24; Bottom = 200 + 48 + 480 + 8 }
$g = Get-InitialGrids $client 80 24 'wt' 1.0
Ok 'initial grid: WT padding taken off (x0 108, cw 10, y0 248, ch 20)' ($g.X.Origin -eq 108 -and $g.X.Cell -eq 10 -and $g.Y.Origin -eq 248 -and $g.Y.Cell -eq 20) ("{0} {1} {2} {3}" -f $g.X.Origin, $g.X.Cell, $g.Y.Origin, $g.Y.Cell)
Ok 'cell -> pixel is the cell centre' ((Get-Pixel (New-Grid 108 10) 12) -eq 233)
# a true grid 104 + 10.5*c; the first guess 100 + 10*c: hit cells computed as a terminal would
$true0 = 104.0; $trueW = 10.5
function Hit([double]$p) { [int][math]::Floor(($p - $true0) / $trueW) }
$guess = New-Grid 100 10
$s = [System.Collections.Generic.List[object]]::new()
$p1 = Get-Pixel $guess 12; $s.Add(@($p1, (Hit $p1)))
$g1 = Update-Grid $guess $s
Ok 'one sample: only the origin moves, the cell size stays' ($g1.Cell -eq 10 -and $g1.Origin -ne 100) ("{0} {1}" -f $g1.Origin, $g1.Cell)
$p2 = Get-Pixel $g1 60; $s.Add(@($p2, (Hit $p2)))
$p3 = Get-Pixel $g1 40; $s.Add(@($p3, (Hit $p3)))
$g2 = Update-Grid $g1 $s
$ok = $true
foreach ($c in 10, 12, 15, 20, 30, 40, 45, 50, 55, 60) { if ((Hit (Get-Pixel $g2 $c)) -ne $c) { $ok = $false } }
Ok 'three samples: the fitted grid hits every termcheck target column (10..60) of the true grid' $ok ("x0={0} cw={1}" -f $g2.Origin, $g2.Cell)
$p4 = Get-Pixel $g2 79; $s.Add(@($p4, (Hit $p4)))
$g4 = Update-Grid $g2 $s
$ok = $true
foreach ($c in 0..79) { if ((Hit (Get-Pixel $g4 $c)) -ne $c) { $ok = $false } }
Ok 'with a sample near the right edge every column 0..79 is hit' $ok ("x0={0} cw={1}" -f $g4.Origin, $g4.Cell)
$bad = [System.Collections.Generic.List[object]]::new(); $bad.Add(@(100, 0)); $bad.Add(@(101, 50))
$g3 = Update-Grid (New-Grid 100 10) $bad
Ok 'an absurd cell size from the fit is ignored' ($g3.Cell -eq 10)

# ---- item steps ---------------------------------------------------------------------
$grids = @{ X = (New-Grid 100 10); Y = (New-Grid 200 20) }
$rd = ConvertFrom-SyncLine 'ready mouse Ctrl+Click target 15 11 screen 80 24'
$st = Get-ItemSteps $table['Ctrl+Click'] $rd $grids
Ok 'Ctrl+Click: the move alone, then one batch with Ctrl held around down/up' ($st.Count -eq 2 -and ([TcAuto.Inj]::Describe($st[0].Batch)) -eq 'SendInput[1] move(255,430)' -and ([TcAuto.Inj]::Describe($st[1].Batch)) -match '^SendInput\[4\] \+LCtrl.* \+LButton -LButton -LCtrl') ([TcAuto.Inj]::Describe($st[1].Batch))
$rd = ConvertFrom-SyncLine 'ready mouse Drag target 10 16 60 18 screen 80 24'
$st = Get-ItemSteps $table['Drag'] $rd $grids
$moves = @($st | Where-Object { $_.Batch.Count -eq 1 -and $_.Batch[0].Kind -eq 'move' }).Count
Ok "drag: move, down, >= 5 intermediate moves 20 ms apart, move, up ($moves moves)" ($moves -ge 7 -and $st[1].Batch[0].Kind -eq 'down' -and $st[-1].Batch[0].Kind -eq 'up' -and $st[2].WaitMs -eq 20)
Ok 'every mouse move of every mouse item is a batch of its own' (@($table.Keys | Where-Object { $table[$_].Kind -eq 'mouse' } | ForEach-Object {
            $tg = $_ -eq 'Drag' ? 'target 10 16 60 18' : 'target 12 6'
            (Get-ItemSteps $table[$_] (ConvertFrom-SyncLine "ready mouse $_ $tg screen 80 24") $grids) | ForEach-Object { $_ } } | Where-Object { @($_.Batch | Where-Object Kind -eq 'move').Count -gt 0 -and $_.Batch.Count -gt 1 }).Count -eq 0)
$rd = ConvertFrom-SyncLine 'ready mouse Triple-Click target 45 9 screen 80 24'
$st = Get-ItemSteps $table['Triple-Click'] $rd $grids
Ok 'triple click: a move, then three click batches 80 ms apart (inside 0.44 s)' ($st.Count -eq 4 -and $st[1].WaitMs -eq 80 -and $st[2].WaitMs -eq 80 -and $st[3].Batch.Count -eq 2)
$rd = ConvertFrom-SyncLine 'ready mouse Wheel-Down target 50 14 screen 80 24'
$st = Get-ItemSteps $table['Wheel-Down'] $rd $grids
Ok 'wheel down: mouseData -120' ($st[1].Batch[0].Kind -eq 'wheel' -and $st[1].Batch[0].Wheel -eq -120)
Ok 'a move and a click in one batch are refused by the wrapper' ($null -ne [TcAuto.Inj]::Check(@((New-MouseEv move 1 1), (New-MouseEv down 1))))

# ---- Guard / Idle through the seam: fake desktop, no input --------------------------------
# the target window covers 0..999 x 0..799, its client area 100..899 x 100..699
$script:fg = [IntPtr]100; $script:cur = @(150, 150); $script:down = @{}; $script:frontOk = $false; $script:frontCalls = 0
[TcAuto.Inj]::Foreground = [Func[IntPtr]] { $script:fg }
[TcAuto.Inj]::Cursor = [Func[TcAuto.POINT]] { [TcAuto.POINT]@{ X = $script:cur[0]; Y = $script:cur[1] } }
[TcAuto.Inj]::KeyDown = [Func[int, bool]] { param($vk) [bool]$script:down[[int]$vk] }
[TcAuto.Inj]::RootAt = [Func[int, int, IntPtr]] { param($x, $y) if ($x -ge 0 -and $x -lt 1000 -and $y -ge 0 -and $y -lt 800) { [IntPtr]100 } else { [IntPtr]200 } }
[TcAuto.Inj]::IsWin = [Func[IntPtr, bool]] { param($h) $true }
[TcAuto.Inj]::ClientOf = [Func[IntPtr, TcAuto.RECT]] { param($h) [TcAuto.RECT]@{ Left = 100; Top = 100; Right = 900; Bottom = 700 } }
[TcAuto.Inj]::BringToFront = [Func[IntPtr, bool]] { param($h) $script:frontCalls++; $script:frontOk }
function Reset-Fake {
    $script:fg = [IntPtr]100; $script:cur = @(150, 150); $script:down = @{}; $script:frontOk = $false; $script:frontCalls = 0
    [TcAuto.Inj]::Target = [IntPtr]100; [TcAuto.Inj]::AllowFrontRecovery = $false
    [TcAuto.Inj]::HaveLast = $true; [TcAuto.Inj]::LastX = 150; [TcAuto.Inj]::LastY = 150
    [TcAuto.Inj]::LastSend = [DateTime]::MinValue; [TcAuto.Inj]::Held.Clear()
}
$key = New-KeyBatch @() 'Up'
$mv = @((New-MouseEv move 500 400))
$click = @((New-MouseEv down 1), (New-MouseEv up 1))
Reset-Fake
Ok 'guard: all fine -> null' ($null -eq [TcAuto.Inj]::Guard($key))
Reset-Fake; $script:fg = [IntPtr]300
$g = [TcAuto.Inj]::Guard($key)
Ok 'guard: another window in front -> refused, no focus fight after the first item' ($g -match 'lost the foreground' -and $script:frontCalls -eq 0) $g
Reset-Fake; $script:fg = [IntPtr]300; $script:frontOk = $true; [TcAuto.Inj]::AllowFrontRecovery = $true
$g = [TcAuto.Inj]::Guard($key)
Ok 'guard: before the first item the window is brought back once' ($null -eq $g -and $script:frontCalls -eq 1 -and -not [TcAuto.Inj]::AllowFrontRecovery) $g
$g = [TcAuto.Inj]::Guard($key)
Ok 'guard: a second loss is refused without another attempt' ($g -match 'lost the foreground' -and $script:frontCalls -eq 1) $g
Reset-Fake; $script:fg = [IntPtr]300; $script:frontOk = $false; [TcAuto.Inj]::AllowFrontRecovery = $true
Ok 'guard: a failed bring-to-front is refused' ([TcAuto.Inj]::Guard($key) -match 'not in front')
Reset-Fake; $script:cur = @(1500, 900); [TcAuto.Inj]::LastX = 1500; [TcAuto.Inj]::LastY = 900
$g = [TcAuto.Inj]::Guard($mv)
Ok 'guard (BUG 1): a move batch needs only its point over the client area, not the current cursor' ($null -eq $g) $g
Ok 'guard: a click with the cursor outside the target -> refused' ([TcAuto.Inj]::Guard($click) -match 'cursor is not over')
Reset-Fake; $script:cur = @(950, 750); [TcAuto.Inj]::LastX = 950; [TcAuto.Inj]::LastY = 750
Ok 'guard: a click with the cursor on the target but outside its client area -> refused' ([TcAuto.Inj]::Guard($click) -match 'client area')
Reset-Fake
Ok 'guard: a move point on the target window outside the client area -> refused' ([TcAuto.Inj]::Guard(@((New-MouseEv move 950 750))) -match 'client area')
Ok 'guard: a move point over another window -> refused' ([TcAuto.Inj]::Guard(@((New-MouseEv move 1500 900))) -match 'not over')
Reset-Fake; $script:cur = @(160, 150)
Ok 'guard: the mouse moved by hand (10 px) -> refused' ([TcAuto.Inj]::Guard($key) -match 'moved by hand')
Reset-Fake; $script:cur = @(152, 151)
Ok 'guard: within the 2 px tolerance -> fine' ($null -eq [TcAuto.Inj]::Guard($key))
Reset-Fake; $script:down[0xA1] = $true; $script:down[0xA3] = $true
Ok 'guard: Right Shift + Right Ctrl held -> abort keys' ([TcAuto.Inj]::Guard($key) -match 'abort keys')
foreach ($vk in 0xA2, 0xA4, 0xA0, 0xA1, 0x5B, 0x5C, 0xA3, 0xA5) {
    Reset-Fake; $script:down[$vk] = $true
    $g = [TcAuto.Inj]::Idle()
    Ok ("idle: vk 0x{0:X2} held by hand (not by the driver) -> refused" -f $vk) ($g -match 'held by hand') $g
}
Reset-Fake; $script:down[0xA2] = $true; [void][TcAuto.Inj]::Held.Add(0xA2)
Ok 'idle: LCtrl down because the driver holds it -> fine' ($null -eq [TcAuto.Inj]::Idle())
Reset-Fake; $script:down[0xA2] = $true; [TcAuto.Inj]::LastSend = [DateTime]::UtcNow
Ok 'idle: right after a send a lagging key-up is not taken for a hand' ($null -eq [TcAuto.Inj]::Idle())
# the move-first path: move -> cursor arrives -> click passes; cursor not there -> refused
Reset-Fake
Ok 'move-first: the move passes' ($null -eq [TcAuto.Inj]::Guard($mv))
[TcAuto.Inj]::LastX = 500; [TcAuto.Inj]::LastY = 400; $script:cur = @(500, 400)
Ok 'move-first: the cursor is at the point -> the click passes' ($null -eq [TcAuto.Inj]::Guard($click))
$script:cur = @(150, 150)
Ok 'move-first: the cursor did not arrive -> the click is refused' ([TcAuto.Inj]::Guard($click) -match 'moved by hand')
Reset-Fake; [TcAuto.Inj]::Target = [IntPtr]100; [TcAuto.Inj]::IsWin = [Func[IntPtr, bool]] { param($h) $false }
Ok 'guard: the target window is gone -> refused' ([TcAuto.Inj]::Guard($key) -match 'gone')
[TcAuto.Inj]::ResetProviders(); [TcAuto.Inj]::Target = [IntPtr]::Zero; [TcAuto.Inj]::Held.Clear(); [TcAuto.Inj]::HaveLast = $false
Ok 'the seam is reset; the wrapper is still dry' (-not [TcAuto.Inj]::Live)

# ---- allow-list and KEYEVENTF_UNICODE control characters -------------------------------------
foreach ($c in 0x00, 0x03, 0x09, 0x0A, 0x0D, 0x1B, 0x1F, 0x7F) {
    Ok ("uni: U+{0:X4} (control character) is refused" -f $c) ($null -ne [TcAuto.Inj]::Check((New-UniBatch $c)))
}
Ok 'uni: U+0020 and U+0436 pass' ($null -eq [TcAuto.Inj]::Check((New-UniBatch 0x20)) -and $null -eq [TcAuto.Inj]::Check((New-UniBatch 0x0436)))
function New-RawKey([int]$vk, [bool]$up) { $e = [TcAuto.Ev]::new(); $e.Kind = 'key'; $e.Vk = $vk; $e.Up = $up; $e.Name = 'raw'; $e }
foreach ($vk in 0x51, 0x7C, 0x2C, 0xAD, 0x5F, 0x13) {
    Ok ("allow-list: vk 0x{0:X2} (not used by the table) is refused" -f $vk) ([TcAuto.Inj]::Check(@((New-RawKey $vk $false))) -match 'allow-list')
}
Ok 'allow-list: the release of a key outside the list is refused' ([TcAuto.Inj]::Check(@((New-RawKey 0x51 $true))) -match 'allow-list')
Ok 'allow-list: the releases of the right-side modifiers pass (cleanup)' ($null -eq [TcAuto.Inj]::Check(@((New-RawKey 0xA1 $true), (New-RawKey 0xA3 $true), (New-RawKey 0xA5 $true))))
$allowed = @([TcAuto.Inj]::Allowed)
Ok "allow-list: exactly the table's keys plus C, Esc, NumLock, CapsLock and the left modifiers ($($allowed.Count))" ($allowed.Count -eq (Get-AllowedVks $table).Count -and $allowed -contains 0x43 -and $allowed -contains 0x90 -and $allowed -notcontains 0x5B)

# ---- cleanup order, window identity, hotkeys, calibration bound -----------------------------------
$script:order = @()
$failed = Invoke-Cleanup @(          # the same form as the driver's finally block
    , @('one', { $script:order += 'one' })
    , @('two', { throw 'boom' })
    , @('three', { $script:order += 'three' })
)
Ok 'cleanup: a throwing step is reported and the next steps still run, in order' (($script:order -join ',') -eq 'one,three' -and ($failed -join ',') -eq 'two') ("order=$($script:order -join ',') failed=$($failed -join ',')")
$win = @{ Hwnd = [IntPtr]5; Class = 'mintty'; Pid = 42; Nonce = 'abc' }
Ok 'same window: all match -> true' (Test-SameWindow $win @{ IsWindow = $true; Class = 'mintty'; Pid = 42; Title = 'termcheck-abc' })
Ok 'same window: gone -> false' (-not (Test-SameWindow $win @{ IsWindow = $false; Class = 'mintty'; Pid = 42; Title = 'termcheck-abc' }))
Ok 'same window: another class -> false' (-not (Test-SameWindow $win @{ IsWindow = $true; Class = 'ConsoleWindowClass'; Pid = 42; Title = 'termcheck-abc' }))
Ok 'same window: another pid -> false' (-not (Test-SameWindow $win @{ IsWindow = $true; Class = 'mintty'; Pid = 43; Title = 'termcheck-abc' }))
Ok 'same window: another title -> false' (-not (Test-SameWindow $win @{ IsWindow = $true; Class = 'mintty'; Pid = 42; Title = 'MINGW64:/c/x' }))
$taken = Get-TakenHotkeys $table { param($m, $vk) -not (($m -eq 0 -and $vk -eq 0x7B) -or ($m -eq 1 -and $vk -eq 0x21) -or ($m -eq 4 -and $vk -eq 0x7B)) }
Ok 'hotkeys: the taken combos are found (F12, Shift+F12, Alt+PgUp)' ((($taken | Sort-Object) -join ',') -eq 'Alt+PgUp,F12,Shift+F12') ($taken -join ',')
$rs = New-RunScript 'wt' 'C:\x\r' 'n1' 6 '' $taken
Ok 'hotkeys: taken combos go into TERMCHECK_SKIP as ID:taken-hotkey' ($rs -match "TERMCHECK_SKIP='[^']*F12:taken-hotkey" -and $rs -match 'Alt\+PgUp:taken-hotkey')
Ok 'sync: a skip reason is parsed' ((ConvertFrom-SyncLine 'done F12 NONE skipped taken-hotkey').Reason -eq 'taken-hotkey')
$g = Limit-Grid (New-Grid 50 10) (New-Grid 110 10) 100 900
Ok 'calibration: a fit whose origin leaves the client area is refused' ($g.Origin -eq 110)
Ok 'calibration: a fit inside the client area is kept' ((Limit-Grid (New-Grid 120 10) (New-Grid 110 10) 100 900).Origin -eq 120)
$out = & pwsh -NoProfile -File $driver -Restore (Join-Path $scratch 'no-such-run') 2>&1
Ok '-Restore without state.json stops with a message (changes nothing)' (($out -join ' ') -match 'no state.json')

# ---- kill.sh against a real process tree (Git-bash; everything reaped) ----------------------------
$kd = Join-Path $scratch 'kill'; $dd = Join-Path $scratch 'decoy'
New-Item -ItemType Directory -Force -Path $kd, $dd | Out-Null
Write-LfFile (Join-Path $kd 'run.sh') "#!/bin/bash`nprintf '%s\n' `"`$`$`" > `"`$(dirname `"`$0`")/bash.pid`"`nsleep 37 & k1=`$!`nsleep 38 & k2=`$!`nprintf '%s %s\n' `"`$k1`" `"`$k2`" > `"`$(dirname `"`$0`")/kids.txt`"`nwait`n"
Write-LfFile (Join-Path $kd 'kill.sh') (New-KillScript $kd)
Write-LfFile (Join-Path $dd 'kill.sh') (New-KillScript $dd)
$probe = @'
d=$1; dd=$2
bash "$d/run.sh" & bg=$!
for i in $(seq 100); do [ -s "$d/kids.txt" ] && break; sleep 0.05; done
root=$(cat "$d/bash.pid"); read -r k1 k2 < "$d/kids.txt"
sleep 39 & decoy=$!
printf '%s\n' "$decoy" > "$dd/bash.pid"
bash "$dd/kill.sh"
if kill -0 "$decoy" 2>/dev/null; then echo decoy-alive; else echo decoy-killed; fi
kill "$decoy" 2>/dev/null; wait "$decoy" 2>/dev/null
bash "$d/kill.sh" >/dev/null
wait "$bg" 2>/dev/null
sleep 0.3
n=0; for p in "$root" "$k1" "$k2"; do kill -0 "$p" 2>/dev/null && n=$((n + 1)); done
echo "alive-after-kill=$n"
for p in "$root" "$k1" "$k2"; do kill -KILL "$p" 2>/dev/null; done
exit 0
'@
Write-LfFile (Join-Path $scratch 'killprobe.sh') $probe
$out = & $script:GitBash (ConvertTo-PosixPath (Join-Path $scratch 'killprobe.sh') '/') (ConvertTo-PosixPath $kd '/') (ConvertTo-PosixPath $dd '/') 2>&1
$txt = $out -join "`n"
Ok 'kill.sh: a pid whose cmdline is not run.sh is left alone' ($txt -match 'is not run\.sh' -and $txt -match 'decoy-alive') $txt
Ok 'kill.sh: the run.sh bash and both children are gone' ($txt -match 'alive-after-kill=0') $txt

# ---- launch commands and run.sh ----------------------------------------------------------
$rs = New-RunScript 'msys2' 'C:\x\run dir' 'abc123' 6 'arrows,mouse'
Ok 'run.sh: no CR' (-not $rs.Contains("`r"))
Ok 'run.sh: paths converted with cygpath -u inside' ($rs -match "cygpath -u 'C:\\x\\run dir'")
Ok 'run.sh: TERMCHECK_SYNC, NONCE, the mintty skip-list, --timeout, --only' ($rs -match 'TERMCHECK_SYNC=\$tc_run/sync.txt TERMCHECK_NONCE=abc123 TERMCHECK_SKIP=''Alt\+F2,Alt\+F3,Alt\+F8''' -and $rs -match '--timeout 6 --out "\$tc_run" --only arrows,mouse')
Ok 'run.sh: stty -g before and after, stty-restored side file, pid file' ($rs -match 'stty -g' -and $rs -match 'stty-restored=%s' -and $rs -match 'bash.pid')
Ok 'run.sh: no --with-dangerous' ($rs -notmatch 'with-dangerous')
$l = Get-LaunchCommand 'wt' 'C:\x\r\run.sh' 'n1'
Ok 'wt: new window, title, Git bash -l with the POSIX path, no semicolon' ($l.Args -match '^-w new new-tab --title termcheck-n1 ' -and $l.Args -match '-l "/c/x/r/run.sh"$' -and -not $l.Args.Contains(';'))
$l = Get-LaunchCommand 'cygwin' 'C:\x\r\run.sh' 'n1'
Ok 'cygwin: mintty -h never -t title, /cygdrive path' ($l.Exe -eq 'C:\bin\cygwin64\bin\mintty.exe' -and $l.Args -eq '-h never -t termcheck-n1 -e /bin/bash -l "/cygdrive/c/x/r/run.sh"') $l.Args
$l = Get-LaunchCommand 'conhost' 'C:\x\r\run.sh' 'n1'
Ok 'conhost: conhost.exe with Git bash' ($l.Exe -eq 'conhost.exe' -and $l.Args -eq '"C:\bin\Git\bin\bash.exe" -l "/c/x/r/run.sh"') $l.Args
Ok 'kill.sh: only the tree of bash.pid' ((New-KillScript 'C:\x\r') -match 'bash.pid' -and -not (New-KillScript 'C:\x\r').Contains("`r"))

# ---- dry runs: whole plan, replay with a calibration retry ----------------------------------
$out = & pwsh -NoProfile -File $driver -Terminals wt 2>&1
$txt = $out -join "`n"
Ok 'dry run: rc 0' ($LASTEXITCODE -eq 0) ($txt.Substring(0, [math]::Min(400, $txt.Length)))
Ok 'dry run: says no window and no input' ($txt -match 'DRY RUN: no window is opened and no input is sent')
Ok 'dry run: the launch command is printed' ($txt -match 'launch: wt\.exe -w new new-tab --title termcheck-NONCE')
$n = ([regex]::Matches($txt, '(?m)^SendInput\[')).Count
Ok "dry run: one SendInput batch per key item, plus mouse and Ctrl+C ($n)" ($n -ge 110)
Ok 'dry run: no release batch (nothing was left held)' ($txt -notmatch '(?m)^release:')
Ok 'dry run: Ctrl+C at finish-wait' ($txt -match '\[finish\] Ctrl\+C #1')
Ok 'dry run: no Win/Alt+F4/Alt+Tab key in the plan' ($txt -notmatch 'LWin|RWin|\+F4\(vk=0x73.*LAlt|LAlt.*\+Tab\(')
$rp = Join-Path $scratch 'replay.txt'
[System.IO.File]::WriteAllText($rp, "ready mouse Click-Left target 12 6 screen 80 24`nretry Click-Left DIFF cell 11 5`nready mouse Click-Left target 12 6 screen 80 24`ndone Click-Left OK cell 12 6`nfinish-wait`nend complete 130`n")
$out = & pwsh -NoProfile -File $driver -Terminals conhost -ReplaySync $rp 2>&1
$txt = $out -join "`n"
$mv = [regex]::Matches($txt, 'move\((\d+),(\d+)\)')
Ok 'replay: two clicks planned' ($mv.Count -eq 2) ($txt)
if ($mv.Count -eq 2) {
    Ok 'replay: after the retry the click moves one cell right and down' ([int]$mv[1].Groups[1].Value -gt [int]$mv[0].Groups[1].Value -and [int]$mv[1].Groups[2].Value -gt [int]$mv[0].Groups[2].Value) ("$($mv[0].Value) -> $($mv[1].Value)")
}
Ok 'replay: the calibration is logged' ($txt -match 'calibration after retry Click-Left cell 11,5')
[System.IO.File]::WriteAllText($rp, "ready mouse Click-Left target 12 6 screen 80 24`nretry Click-Left DIFF cell 13 7`nready mouse Click-Left target 12 6 screen 80 24`ndone Click-Left OK cell 12 6`nfinish-wait`nend complete 130`n")
$txt = (& pwsh -NoProfile -File $driver -Terminals conhost -ReplaySync $rp 2>&1) -join "`n"
Ok 'replay: a fit that would put the grid origin left of the client area is refused' ($txt -match 'calibration refused: origin') $txt
Ok 'replay: results line' ($txt -match 'results: OK=1; end: complete 130')

if (-not $env:AUTODRIVE_TEST_TMP) { Remove-Item -Recurse -Force $scratch }
Write-Output "== $script:pass PASS, $script:fail FAIL =="
exit ([int]($script:fail -gt 0))

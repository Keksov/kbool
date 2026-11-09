# termcheck - what does my terminal really send?

Terminals disagree about what happens when you press a key or click the mouse.
Arrow keys with Ctrl, F-keys with Shift, the mouse wheel, a double click: each
terminal sends its own bytes. The text-mode screens being built for kbool have
to recognise all of them.

`termcheck` asks you, one by one, to press about a hundred keys and do a few
mouse actions. It writes a **log file** with what arrived. You send that file
back, and the key tables are fixed from it.

* **Time:** 8-10 minutes in one terminal, up to 20 if many items time out.
* **It changes nothing on the system.** It only writes the log file, in the
  folder where you run it. It installs nothing and touches no settings. It puts
  the terminal back to normal when it ends.
* **It needs:** a terminal window of at least 80 columns by 24 rows, and bash
  5.1 or newer (every bash on this machine is new enough).

## Run it

From the repository folder (`C:\projects\kkbot\kbool`):

    bash tools/termcheck/termcheck.sh

That is the whole command. Do it once in **each** terminal you use. The steps to
open each terminal are below.

## Open the terminal, then go to the folder

Pick one terminal at a time. After the first line, type the `cd` line, then the
command above.

### 1. Windows Terminal, Git Bash profile

1. Start menu, type `Terminal`, press Enter.
2. Click the small arrow (v) next to the `+` tab button and choose `Git Bash`.
   (No such entry? In the same menu choose `PowerShell`, then run
   `& 'C:\bin\Git\bin\bash.exe' --login -i` and press Enter.)
3. Type: `cd /c/projects/kkbot/kbool`

### 2. Git Bash window (its own window, mintty)

1. Start menu, type `Git Bash`, press Enter. (Or run `C:\bin\Git\git-bash.exe`.)
2. Type: `cd /c/projects/kkbot/kbool`

### 3. VS Code integrated terminal, Git Bash

1. In VS Code: menu `Terminal` > `New Terminal`.
2. If the prompt starts with `PS`, it is PowerShell. Either click the arrow
   next to the `+` in the terminal panel and pick `Git Bash`, or type
   `& 'C:\bin\Git\bin\bash.exe'` and press Enter.
3. Type: `cd /c/projects/kkbot/kbool`

### 4. Classic console window (conhost)

This is the old black Windows console, not Windows Terminal.

1. Press `Win+R`, type `conhost.exe C:\bin\Git\bin\bash.exe`, press Enter.
   (Plain `C:\bin\Git\bin\bash.exe` also works, but Windows 11 may open it in
   Windows Terminal instead. A window without tabs is the classic console.)
2. If you want every console to open the classic way: Settings > System > For
   developers > Terminal: choose `Windows Console Host`. Change it back after
   the check if you like.
3. Type: `cd /c/projects/kkbot/kbool`

### 5. MSYS2 window

1. Press `Win+R`, type `C:\bin\msys64\msys2.exe`, press Enter.
2. Type: `cd /c/projects/kkbot/kbool`

### 6. Cygwin terminal

1. Press `Win+R`, type `C:\bin\cygwin64\bin\mintty.exe -`, press Enter.
2. Type: `cd /cygdrive/c/projects/kkbot/kbool`

### 7. Optional: WSL, or a Linux machine over SSH

* WSL: Start menu, `Ubuntu` (or your distribution). Then
  `cd /mnt/c/projects/kkbot/kbool`.
* Linux over SSH: connect, then `cd` to a checkout of the repository
  (`git clone --recurse-submodules` if there is none).

In every case, check that `ls tools/termcheck` shows `termcheck.sh`. If it says
"No such file", you are in the wrong folder.

## During the run

* Each screen shows one request, for example `Press: Shift+Left`. **Do exactly
  that.** The result flashes for a moment (OK, DIFF, NONE), then the next request
  comes by itself.
* A **countdown** runs (10 seconds per request). If a key does nothing, the
  terminal swallowed it, or you do not have it, just wait. The request is
  recorded as "nothing arrived" and the next one comes. Nothing is wrong.
* If the terminal reacts on its own (a menu opens, the window goes full screen,
  the keyboard layout changes), ignore it and wait for the countdown. Known cases:
  `F11` and `Alt+F11` may go full screen (press the key again to come back);
  `Alt+F2` may open something; `Alt+Shift` may switch the keyboard layout;
  `Shift+Insert` may paste clipboard text (harmless, it is recorded as extra
  input). `Alt+F4` is **not** asked, it would close the window.
* **Keyboard groups:** arrows, Home/End/PageUp/PageDown/Insert/Delete, F1-F12
  (each with Shift, Ctrl and Alt), special keys (Tab, Enter, Esc, Backspace...),
  a few letters, and the number keypad.
* **Keypad:** the requests say "NumLock OFF" or "NumLock ON". Switch NumLock
  with its key before you press. No keypad (laptop)? Just wait; each costs 10
  seconds.
* **The letter ж:** switch the keyboard to the Russian layout first
  (`Win+Space`), then press the key that types ж. Switch back afterwards.
* **Mouse:** a small `[X]` appears on the screen. Click exactly on the
  highlighted X, with the button asked. Then: wheel up and down over the X, a
  drag from `A` to `B` (press on A, hold, move, release on B), a double click, a
  triple click, Ctrl+click and Shift+click (terminals often keep Shift+click
  for themselves; then nothing arrives, which is fine).
  If your window is at least 230 columns wide, one more X appears at the far
  right; click it too. (A narrow window skips it.)
* **Resize:** near the end you are asked to resize the window: drag a corner and
  let go. Keep it at 80x24 or bigger.
* At the end: **Press Ctrl+C to finish.** Press Ctrl+C. That is also a test.

To repeat only a part: `bash tools/termcheck/termcheck.sh --only arrows,mouse`.
Groups are `arrows`, `nav`, `fkeys`, `special`, `chars`, `keypad`, `mouse`,
`resize`. A shorter wait per request: `--timeout 5`.

## After Ctrl+C - look at the terminal

The program prints where the log file is and a one-line count. Then check:

1. The normal prompt is back (not a black empty screen).
2. Type a few letters: you can see them as you type.
3. No strange characters appear when you move the mouse or scroll the wheel.
4. The cursor is visible.

If something is wrong, type `reset` (you may not see the letters) and press
Enter. If that fails, type `stty sane` and press Enter. **Write down what was
broken**, in which terminal. That is an important result too.

## What to send back

The log file, one for every terminal you tried. It is in the folder where you
ran the command (the repository folder), and its name looks like

    fv_termcheck_20261109-153012_WT-MINGW64.log

(date, time, then a short name of the terminal). Attach the files in the chat.
Add one line per terminal: how you opened it, and anything odd (a key that
opened a menu, a broken screen afterwards, a window action). A run that was cut
short is still useful: send the file, it marks where it stopped
(`incomplete at ...`).

**Privacy:** the log holds the computer name (the output of `uname -a`), the
bash version and these environment variables: `TERM`, `COLORTERM`,
`TERM_PROGRAM`, `TERM_PROGRAM_VERSION`, `WT_SESSION` (only "set" or "not set"),
`MSYSTEM`, `OSTYPE`, `WSL_DISTRO_NAME`, `LANG`, `LC_ALL`, `LC_CTYPE`,
`FV_ESC_TIMEOUT`, and whether an SSH connection is in use. Nothing else. It is a
plain text file: open it in Notepad to see.

## If something goes wrong

* **`termcheck: no terminal`** - you ran it from something that is not a
  terminal window (a script runner, a pipe). Open one of the terminals above.
* **`enlarge the window to at least 80x24`** - make the window bigger and run it
  again.
* **`No such file or directory`** - wrong folder. Type
  `cd /c/projects/kkbot/kbool` (Cygwin: `cd /cygdrive/c/projects/kkbot/kbool`).
* **Nothing reacts on the first screen** - click inside the window so it has the
  keyboard focus.
* **The window closed by itself** - the terminal itself was closed by a key you
  pressed. Run again with `--only` for the rest and tell which key it was.
* **Pasted text or a menu appeared** - ignore it, wait for the countdown.
* **The screen looks garbled, the arrow keys type letters** - press Ctrl+C
  once. Then see "After Ctrl+C" above.
* **The run is stuck on one screen for more than 20 seconds** - press Ctrl+C. The
  log is written after every item; send it.
* **No log file** - the program stopped before the first screen (see the message
  it printed). Send that message instead.

## Options

| Option | Meaning |
|---|---|
| `--only GROUPS` | run only these groups (comma list) |
| `--timeout SECONDS` | wait per request, default 10 (decimals allowed) |
| `--out DIR` | write the log into `DIR` instead of the current folder |
| `--with-dangerous` | also ask for Alt+F4 (closes most windows) |
| `--list-items` | print the items (group, id, kind, expected) and exit |
| `--help` | usage |

For developers: `bash tools/termcheck/tests/selftest.sh` checks the program
without a person (a pseudo-terminal part runs where `script(1)` exists: MSYS2,
Cygwin, Linux).

## Automatic run (Windows)

`tools/termcheck/autodrive.ps1` runs the check in five Windows terminals one after
another and presses the keys and the mouse for you. It uses real Windows input
(the same path as a physical keyboard), so the terminals translate the keys
exactly as they would for a person. The VS Code terminal is not automated: run it
by hand as in section 3 above.

Terminals, in this order: Windows Terminal (Git Bash), classic console (conhost,
Git Bash), Git Bash window (mintty), MSYS2 window, Cygwin terminal.

**It takes over the keyboard and the mouse for about 10-15 minutes** (about 2-3
minutes per terminal). During that time:

* do not touch the keyboard or the mouse (a key held by hand, even Shift or Ctrl,
  stops the run);
* do not open other windows. The driver checks before every key and every mouse
  event that its terminal window is in front. It brings the window back to the
  front only before the first item of each terminal; after that, if another
  window comes to the front (a pop-up that takes the focus), the driver stops;
* do not close the driver's PowerShell window: to stop, move the mouse.

### Start it

1. Save your work. Close nothing else; the driver does not touch other windows.
2. Make sure the US English keyboard layout is installed (Settings > Time &
   language > Language & region). The driver switches to it for the run. On this
   PC the keyboard layout is shared by all windows, so during the run every window
   is in English; the layout you had is put back at the end. If the end of the run
   says `keyboard layout not restored - press Win+Space`, press Win+Space to get
   your layout back.
3. Open PowerShell 7 (Start menu: type `pwsh`, press Enter).
4. Type and press Enter:

       cd C:\projects\kkbot\kbool
       pwsh -File tools\termcheck\autodrive.ps1 -Live

5. Take your hands off the keyboard and the mouse. Windows open and close by
   themselves, one terminal at a time.

To try only one terminal or a few groups first:

    pwsh -File tools\termcheck\autodrive.ps1 -Live -Terminals mintty-git -Groups arrows,keypad

Without `-Live` nothing is opened and nothing is pressed: the driver prints what it
would send (a dry run).

### How to stop it

* **Move the mouse.** This is the way to stop it. Or
* **hold Right Shift and Right Ctrl together** for a moment.

The driver then stops at once: it lets go of every key and mouse button, puts
NumLock, CapsLock, the keyboard layout and the clipboard back, closes its own
terminal window and writes what it has. (Ctrl+C stops it only when its PowerShell
window has the keyboard focus, which it does not have during the run: move the
mouse instead. Do not close the PowerShell window: the putting-back would not
run.)

It also stops by itself when a key is held by hand, when its terminal window is no
longer in front after the first item, when a mouse point would land outside the
text area of that window, and after 25 minutes in total (`-MaxMinutes`).

If the driver was killed before it could put things back (the window was closed,
the PC hung), run, in a new PowerShell 7 window:

    cd C:\projects\kkbot\kbool
    pwsh -File tools\termcheck\autodrive.ps1 -Restore tools\termcheck\runs\<date-time>

It puts back NumLock, CapsLock, the keyboard layout and the clipboard text from
`state.json` in that folder (it presses no key other than NumLock / CapsLock).
`state.json` holds a copy of your clipboard text; it is deleted as soon as
everything is put back.

### What it does to your PC, and puts back

* NumLock is switched on and off for the keypad items; CapsLock is turned off for
  the run. Both are put back at the end.
* The clipboard holds the text `termcheck-clip` during the run (Shift+Ins pastes
  it). Your clipboard **text** is put back at the end; anything else on the
  clipboard (pictures, files copied in Explorer, formatted text, any non-text
  format) is lost.
* It never presses the Windows key, the Menu key, Alt+Tab, Alt+F4, Alt+Esc,
  Alt+Space, Ctrl+Esc, Ctrl+Shift+Esc or Ctrl+Alt+Del, and never the right-side
  Shift, Ctrl or Alt keys.
* In the mintty windows (Git Bash, MSYS2, Cygwin) Alt+F2, Alt+F3 and Alt+F8 are
  skipped (they open a new window, a search bar, a reset dialog); the log shows
  them as NONE with `note=skipped-by-driver`.
* In the classic console (conhost) Shift+Click is skipped
  (`note=skipped-by-driver:conhost-selection`): Shift+click starts conhost's
  selection mode, which freezes the console's output, so termcheck cannot draw
  the next screen and the run would hang. Try Shift+Click there by hand.
* Key combinations that another program has taken as a global hotkey (for example
  F12 or Alt+PgUp taken by a screenshot or media tool) are found at the start and
  skipped, so the driver never triggers that program; the log shows
  `note=skipped-by-driver:taken-hotkey` and `summary.txt` lists them. Programs
  that watch the keyboard with a low-level hook cannot be detected this way; if
  one reacts to a key, close it before the run.
* After F11, Alt+F11, Alt+F10 and Alt+F12 the same key is pressed again when the
  window changed (full screen, size).

### Where the results are

`C:\projects\kkbot\kbool\tools\termcheck\runs\<date-time>\`:

* `summary.txt` - one line per terminal: OK / DIFF / NONE / INFO counts, whether
  the terminal settings were put back (`stty-restored`), how termcheck ended;
* `driver.log` - every key and mouse event sent, every check, any stop;
* one folder per terminal (`wt`, `conhost`, `mintty-git`, `msys2`, `cygwin`) with
  the termcheck log `fv_termcheck_<date-time>_<terminal>.log`, the sync file
  `sync.txt` and `trace.txt` (one line per input poll, for diagnosing a hang).

The Git terminals (`wt`, `conhost`, `mintty-git`) run with `MSYSTEM=UCRT64`,
Git Bash's own default here; `msys2` with `MSYSTEM=MSYS`; `cygwin` without it.
A terminal that stops answering (no next item within the item time plus 10 s) is
marked `STUCK` in `summary.txt` and the run goes on with the next terminal.

Send the whole `<date-time>` folder.

### For developers

* Sync mode: with `TERMCHECK_SYNC=FILE` termcheck appends one line per state:
  `ready <group> <id> [target X Y [X2 Y2]] [screen W H]` (after the prompt is
  drawn and pending input dropped; keys sent earlier are dropped as stale),
  `done <id> <result> [cell X Y [cell2 X Y]] [screen W H] [skipped]`,
  `retry <id> DIFF cell X Y` (a mouse item that landed on the wrong cell is asked
  once more, only the second attempt is logged), `finish-wait`,
  `end <complete|incomplete|error> <status>`. `TERMCHECK_NONCE` sets the window
  title `termcheck-<nonce>`; `TERMCHECK_SKIP=ID[:REASON],...` skips items (note `skipped-by-driver[:REASON]`).
* `TERMCHECK_TRACE=FILE` appends `<epoch.us> <phase> <event>[:<key>] r=<FV_VIDEO_RESIZED> <group/item>`
  per loop turn (phases drain, settle, wait, finish, and drain-time-limit /
  drain-resize / settle-resize). `TERMCHECK_LABEL=WORD` names the log after WORD.
  Draining pending input stops after 0.3 s, and resizes seen while draining or
  settling are read once (one `stty size`), not once per event.
* `-Terminals` and `-Groups` take an array or one comma string
  (`-Terminals wt,conhost` through `pwsh -File`).
* Offline driver tests (no window, no input):
  `pwsh -NoProfile -File tools/termcheck/tests/autodrive.Tests.ps1`.

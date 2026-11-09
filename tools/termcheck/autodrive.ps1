<#
.SYNOPSIS
    autodrive.ps1 -- runs tools/termcheck in Windows terminals and presses the
    keys and the mouse for it (Win32 SendInput). README: "Automatic run (Windows)".

.DESCRIPTION
    Default is a DRY RUN: no window is opened and no input is sent; the exact
    injection plan is printed. -Live opens each terminal, finds its window by
    the title termcheck-<nonce>, follows termcheck's sync file item by item
    (TERMCHECK_SYNC) and injects real keyboard and mouse input into that window
    only. Every SendInput batch goes through one wrapper (TcAuto.Inj.Send) that
    allows only the VK codes of the key table, refuses forbidden combinations
    and control characters and, in live mode, checks before every batch that the
    target window is in front (recovered once, only before the first item), that
    the mouse was not moved by hand, that no key is held by hand, that the abort
    keys (Right Shift + Right Ctrl) are not held and that every mouse point is
    inside the target window's client area. Any failed check aborts the whole run.

    pwsh -File tools\termcheck\autodrive.ps1                      # dry run, all terminals
    pwsh -File tools\termcheck\autodrive.ps1 -ReplaySync FILE     # dry run on a recorded sync file
    pwsh -File tools\termcheck\autodrive.ps1 -Live                # the real run (takes over keyboard and mouse)
    pwsh -File tools\termcheck\autodrive.ps1 -Restore RUNDIR      # put back locks, layout, clipboard from RUNDIR\state.json
#>
[CmdletBinding()]
param(
    [ValidateSet('wt', 'conhost', 'mintty-git', 'msys2', 'cygwin')]
    [string[]]$Terminals = @('wt', 'conhost', 'mintty-git', 'msys2', 'cygwin'),
    [string]$Groups = '',
    [ValidateRange(2, 60)][int]$Timeout = 6,
    [ValidateRange(1, 240)][int]$MaxMinutes = 25,
    [string]$OutDir = '',
    [string]$ReplaySync = '',
    [string]$Restore = '',
    [switch]$Live,
    [switch]$DryRun,
    [switch]$LibraryOnly
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
[cultureinfo]::CurrentCulture = [cultureinfo]::InvariantCulture     # 9.5, not 9,5, in the logs

$script:TcRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:GitBash = 'C:\bin\Git\bin\bash.exe'

# ---- Win32 layer -----------------------------------------------------------------
if (-not ('TcAuto.Inj' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace TcAuto {

[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
[StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
[StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
    public int cbSize; public uint flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }

public static class W {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern short GetKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int n, IntPtr[] list);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
    [DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] public static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
    [DllImport("user32.dll")] public static extern bool GetKeyboardState(byte[] state);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);

    // per-monitor v2 DPI awareness for this process; true only when it is in effect afterwards
    public static bool EnsurePerMonitorV2() {
        SetProcessDpiAwarenessContext(new IntPtr(-4));       // fails with 5 when already set: the check below decides
        return AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(), new IntPtr(-4));
    }

    // a lock key's toggle state, not stale: GetKeyState(0) syncs this thread's key state, then GetKeyboardState
    public static bool LockOn(int vk) {
        GetKeyState(0);
        var b = new byte[256];
        if (!GetKeyboardState(b)) return (GetKeyState(vk) & 1) != 0;
        return (b[vk] & 1) != 0;
    }

    public static string Text(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
    public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
    public static uint Thread(IntPtr h) { uint p; return GetWindowThreadProcessId(h, out p); }

    // visible top-level windows with this exact title; cls / pid filter when given
    public static List<IntPtr> Find(string title, string cls, uint pid) {
        var found = new List<IntPtr>();
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            if (Text(h) != title) return true;
            if (!string.IsNullOrEmpty(cls) && Cls(h) != cls) return true;
            if (pid != 0 && Pid(h) != pid) return true;
            found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static RECT Client(IntPtr h) {     // the client rectangle in screen pixels
        RECT r; GetClientRect(h, out r);
        var p = new POINT(); ClientToScreen(h, ref p);
        return new RECT { Left = p.X, Top = p.Y, Right = p.X + r.Right, Bottom = p.Y + r.Bottom };
    }

    // menu mode (F10 / Alt / Shift+F10 can put a window into it): GUI_INMENUMODE|SYSTEMMENUMODE|POPUPMENUMODE
    public static bool InMenuMode(IntPtr h) {
        var gi = new GUITHREADINFO(); gi.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (!GetGUIThreadInfo(Thread(h), ref gi)) return false;
        return (gi.flags & 0x1C) != 0;
    }
}

// one event of a batch
public class Ev {
    public string Kind;      // key | uni | move | down | up | wheel
    public ushort Vk, Scan;
    public bool Ext, Up;
    public int X, Y;         // move: screen pixel
    public int Button;       // down/up: 1 left, 2 right, 4 middle
    public int Wheel;        // +120 / -120
    public string Name = "";
    public bool IsMouse { get { return Kind == "move" || Kind == "down" || Kind == "up" || Kind == "wheel"; } }
    public bool IsRelease { get { return (Kind == "key" && Up) || (Kind == "uni" && Up) || Kind == "up"; } }
    public override string ToString() {
        switch (Kind) {
            case "key": return (Up ? "-" : "+") + Name + "(vk=0x" + Vk.ToString("X2") + ",sc=0x" + Scan.ToString("X2") + (Ext ? ",E0" : "") + ")";
            case "uni": return (Up ? "-" : "+") + "U+" + Scan.ToString("X4") + "(KEYEVENTF_UNICODE)";
            case "move": return "move(" + X + "," + Y + ")";
            case "down": return "+" + Btn(Button);
            case "up": return "-" + Btn(Button);
            case "wheel": return "wheel(" + (Wheel > 0 ? "+" : "") + Wheel + ")";
        }
        return "?";
    }
    static string Btn(int b) { return b == 1 ? "LButton" : b == 2 ? "RButton" : b == 4 ? "MButton" : "Button" + b; }
}

public class AbortException : Exception { public AbortException(string m) : base(m) { } }

// the single low-level SendInput wrapper
public static class Inj {
    public static bool Live = false;          // false: nothing is sent, batches go to Plan
    public static bool Aborted = false;       // after an abort only releases pass
    public static IntPtr Target = IntPtr.Zero;
    public static bool AllowFrontRecovery = false;   // true only before the first item of a terminal
    public static bool AllowLockToggle = false;      // -Restore: lock toggles without a live run
    public static readonly List<string> Plan = new List<string>();
    public static readonly List<string> Log = new List<string>();
    public static readonly HashSet<ushort> Held = new HashSet<ushort>();
    public static readonly HashSet<ushort> Allowed = new HashSet<ushort>();
    public static readonly object Gate = new object();   // Held/HeldButtons vs the emergency thread
    public static int HeldButtons = 0;
    public static bool HaveLast = false;
    public static int LastX, LastY;
    public static int Tolerance = 2;
    public static DateTime LastSend = DateTime.MinValue;
    public static int ModifierLagMs = 150;    // our own key-up may lag in GetAsyncKeyState
    // what the finally / emergency handler restores
    public static bool HaveInitial = false;
    public static bool InitialNumLock, InitialCaps;
    public static IntPtr OriginalHkl = IntPtr.Zero;

    // the seam: what Guard/Idle see of the desktop (tests replace these; no input involved)
    public static Func<IntPtr> Foreground = () => W.GetForegroundWindow();
    public static Func<POINT> Cursor = () => { POINT p; W.GetCursorPos(out p); return p; };
    public static Func<int, bool> KeyDown = vk => (W.GetAsyncKeyState(vk) & 0x8000) != 0;
    public static Func<int, int, IntPtr> RootAt = (x, y) => W.GetAncestor(W.WindowFromPoint(new POINT { X = x, Y = y }), 2 /* GA_ROOT */);
    public static Func<IntPtr, bool> IsWin = h => W.IsWindow(h);
    public static Func<IntPtr, RECT> ClientOf = h => W.Client(h);
    public static Func<IntPtr, bool> BringToFront = h => { W.SetForegroundWindow(h); Thread.Sleep(200); return W.GetForegroundWindow() == h; };
    public static void ResetProviders() {
        Foreground = () => W.GetForegroundWindow();
        Cursor = () => { POINT p; W.GetCursorPos(out p); return p; };
        KeyDown = vk => (W.GetAsyncKeyState(vk) & 0x8000) != 0;
        RootAt = (x, y) => W.GetAncestor(W.WindowFromPoint(new POINT { X = x, Y = y }), 2);
        IsWin = h => W.IsWindow(h);
        ClientOf = h => W.Client(h);
        BringToFront = h => { W.SetForegroundWindow(h); Thread.Sleep(200); return W.GetForegroundWindow() == h; };
    }

    const ushort VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1,
                 VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5,
                 VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_APPS = 0x5D, VK_TAB = 0x09, VK_ESCAPE = 0x1B,
                 VK_SPACE = 0x20, VK_F4 = 0x73, VK_DELETE = 0x2E, VK_DECIMAL = 0x6E;
    static readonly ushort[] Mods8 = { VK_LWIN, VK_RWIN, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LSHIFT, VK_RSHIFT };
    static readonly ushort[] ReleaseMods = { VK_LCONTROL, VK_LMENU, VK_LSHIFT, VK_RSHIFT, VK_RCONTROL, VK_RMENU };

    public static void Note(string s) { lock (Log) Log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " " + s); }

    static bool IsMod(ushort vk) { return vk == VK_LSHIFT || vk == VK_LCONTROL || vk == VK_LMENU; }

    public static void SetAllowed(ushort[] vks) { lock (Gate) { Allowed.Clear(); foreach (var v in vks) Allowed.Add(v); } }

    // the rules every batch must pass (dry and live); null = allowed
    public static string Check(Ev[] batch) {
        HashSet<ushort> held;
        lock (Gate) held = new HashSet<ushort>(Held);
        bool hasMove = false, hasOther = false;
        foreach (var e in batch) { if (e.Kind == "move") hasMove = true; else hasOther = true; }
        if (hasMove && hasOther) return "refused: a mouse move must be a batch of its own";
        foreach (var e in batch) {
            if (e.Kind == "uni") {
                if (e.Scan < 0x20 || e.Scan == 0x7F) return "refused: a control character as KEYEVENTF_UNICODE (U+" + e.Scan.ToString("X4") + ")";
                continue;
            }
            if (e.Kind != "key") continue;
            ushort vk = e.Vk;
            if (e.Up) {
                if (!Allowed.Contains(vk) && Array.IndexOf(ReleaseMods, vk) < 0) return "refused: release of a key outside the allow-list (vk=0x" + vk.ToString("X2") + ")";
                held.Remove(vk); continue;
            }
            if (vk == VK_LWIN || vk == VK_RWIN) return "refused: the Win key";
            if (vk == VK_APPS) return "refused: the Menu (Apps) key";
            if (vk == VK_RSHIFT || vk == VK_RCONTROL || vk == VK_RMENU || vk == VK_SHIFT || vk == VK_CONTROL || vk == VK_MENU)
                return "refused: only left-side modifiers are injected (vk=0x" + vk.ToString("X2") + ")";
            if (!Allowed.Contains(vk)) return "refused: vk=0x" + vk.ToString("X2") + " is not in the allow-list";
            bool alt = held.Contains(VK_LMENU), ctrl = held.Contains(VK_LCONTROL), shift = held.Contains(VK_LSHIFT);
            if (IsMod(vk)) {
                foreach (var h in held) if (!IsMod(h)) return "refused: a modifier pressed while a key is held";
                held.Add(vk);
                continue;
            }
            if (alt && vk == VK_TAB) return "refused: Alt+Tab";
            if (alt && vk == VK_ESCAPE) return "refused: Alt+Esc";
            if (alt && vk == VK_SPACE) return "refused: Alt+Space";
            if (alt && vk == VK_F4) return "refused: Alt+F4";
            if (ctrl && shift && vk == VK_ESCAPE) return "refused: Ctrl+Shift+Esc";
            if (ctrl && vk == VK_ESCAPE) return "refused: Ctrl+Esc";
            if (ctrl && alt && (vk == VK_DELETE || vk == VK_DECIMAL)) return "refused: Ctrl+Alt+Del";
            held.Add(vk);
        }
        return null;
    }

    public static bool AbortKeysDown() { return KeyDown(VK_RSHIFT) && KeyDown(VK_RCONTROL); }

    public static void ResetCursorRef() { var p = Cursor(); LastX = p.X; LastY = p.Y; HaveLast = true; }

    static bool Inside(RECT r, int x, int y) { return x >= r.Left && x < r.Right && y >= r.Top && y < r.Bottom; }
    static bool OverClient(int x, int y) { return RootAt(x, y) == Target && Inside(ClientOf(Target), x, y); }

    // the owner-takeover and window checks; null = fine
    public static string Idle() {
        if (Target == IntPtr.Zero || !IsWin(Target)) return "the target window is gone";
        if (AbortKeysDown()) return "abort keys held (Right Shift + Right Ctrl)";
        if ((DateTime.UtcNow - LastSend).TotalMilliseconds > ModifierLagMs) {
            lock (Gate) {
                foreach (var vk in Mods8)
                    if (KeyDown(vk) && !Held.Contains(vk)) return "a key is held by hand (vk=0x" + vk.ToString("X2") + ")";
            }
        }
        var p = Cursor();
        if (HaveLast && (Math.Abs(p.X - LastX) > Tolerance || Math.Abs(p.Y - LastY) > Tolerance))
            return "the mouse was moved by hand (cursor " + p.X + "," + p.Y + ", expected " + LastX + "," + LastY + ")";
        return null;
    }

    // before every batch: Idle, the foreground (recovered once only before the first item),
    // move points over the target's client area; a click/wheel batch needs the cursor there
    public static string Guard(Ev[] batch) {
        string r = Idle();
        if (r != null) return r;
        IntPtr fg = Foreground();
        if (fg != Target) {
            if (!AllowFrontRecovery) return "the target window lost the foreground (foreground=0x" + fg.ToString("X") + ")";
            Note("foreground check: foreground=0x" + fg.ToString("X") + " is not the target; bringing the target to front once (before the first item)");
            AllowFrontRecovery = false;
            if (!BringToFront(Target)) return "the target window is not in front (foreground=0x" + Foreground().ToString("X") + ")";
        }
        bool move = false, button = false;
        foreach (var e in batch) { if (e.Kind == "move") move = true; else if (e.IsMouse) button = true; }
        if (move) {
            foreach (var e in batch) if (e.Kind == "move" && !OverClient(e.X, e.Y)) return "a mouse point is not over the target's client area (" + e.X + "," + e.Y + ")";
        }
        if (button) {
            var p = Cursor();
            if (!OverClient(p.X, p.Y)) return "the cursor is not over the target's client area (" + p.X + "," + p.Y + ")";
        }
        Note("foreground check: ok (target 0x" + Target.ToString("X") + ")" + (move ? ", move points inside the client area" : "") + (button ? ", cursor inside the client area" : ""));
        return null;
    }

    public static int Norm(int px, int origin, int size) {
        return (int)Math.Round((px - origin) * 65535.0 / (size - 1));
    }

    static INPUT ToInput(Ev e) {
        var i = new INPUT();
        if (e.Kind == "key" || e.Kind == "uni") {
            i.type = 1;
            i.u.ki.wVk = e.Kind == "uni" ? (ushort)0 : e.Vk;
            i.u.ki.wScan = e.Scan;
            uint f = 0;
            if (e.Kind == "uni") f |= 0x0004;         // KEYEVENTF_UNICODE
            else if (e.Ext) f |= 0x0001;              // KEYEVENTF_EXTENDEDKEY
            if (e.Up) f |= 0x0002;                    // KEYEVENTF_KEYUP
            i.u.ki.dwFlags = f;
            return i;
        }
        i.type = 0;
        const uint ABS = 0x8000, VDESK = 0x4000;
        switch (e.Kind) {
            case "move":
                int vx = W.GetSystemMetrics(76), vy = W.GetSystemMetrics(77), vw = W.GetSystemMetrics(78), vh = W.GetSystemMetrics(79);
                i.u.mi.dx = Norm(e.X, vx, vw); i.u.mi.dy = Norm(e.Y, vy, vh);
                i.u.mi.dwFlags = 0x0001 | ABS | VDESK;
                break;
            case "down": i.u.mi.dwFlags = e.Button == 1 ? 0x0002u : e.Button == 2 ? 0x0008u : 0x0020u; break;
            case "up": i.u.mi.dwFlags = e.Button == 1 ? 0x0004u : e.Button == 2 ? 0x0010u : 0x0040u; break;
            case "wheel": i.u.mi.dwFlags = 0x0800; i.u.mi.mouseData = unchecked((uint)e.Wheel); break;
        }
        return i;
    }

    static void Track(Ev[] batch) {
        lock (Gate) {
            foreach (var e in batch) {
                if (e.Kind == "key") { if (e.Up) Held.Remove(e.Vk); else Held.Add(e.Vk); }
                else if (e.Kind == "down") HeldButtons |= e.Button;
                else if (e.Kind == "up") HeldButtons &= ~e.Button;
                else if (e.Kind == "move") { LastX = e.X; LastY = e.Y; HaveLast = true; }
            }
        }
    }

    public static string Describe(Ev[] batch) {
        var parts = new List<string>();
        foreach (var e in batch) parts.Add(e.ToString());
        return "SendInput[" + batch.Length + "] " + string.Join(" ", parts);
    }

    static uint RealSend(Ev[] batch) {
        var arr = new INPUT[batch.Length];
        for (int k = 0; k < batch.Length; k++) arr[k] = ToInput(batch[k]);
        return W.SendInput((uint)arr.Length, arr, Marshal.SizeOf(typeof(INPUT)));
    }

    // check, guard (live), send as ONE SendInput array, track
    public static void Send(Ev[] batch) {
        lock (Gate) {
            if (Aborted) {
                foreach (var e in batch) if (!e.IsRelease) throw new AbortException("refused after abort: only key-ups and mouse-ups pass");
            }
            string why = Check(batch);
            if (why != null) { Note(why + ": " + Describe(batch)); throw new InvalidOperationException(why); }
            if (Live && !Aborted) {
                string g = Guard(batch);
                if (g != null) { Note("ABORT: " + g); Aborted = true; ReleaseAll(); throw new AbortException(g); }
            }
            string d = Describe(batch);
            if (Live) {
                uint n = RealSend(batch);
                Track(batch);
                LastSend = DateTime.UtcNow;
                Note("sent " + n + "/" + batch.Length + ": " + d);
                if (n != batch.Length) { Aborted = true; ReleaseAll(); throw new AbortException("SendInput sent " + n + " of " + batch.Length + " (blocked by UIPI or the secure desktop)"); }
            } else {
                Track(batch);
                Plan.Add(d);
            }
        }
    }

    // releases only (works after an abort): keys the driver holds, the six modifiers
    // when down, held mouse buttons
    public static void ReleaseAll() {
        lock (Gate) {
            var evs = new List<Ev>();
            var scans = new Dictionary<ushort, ushort> { { VK_LCONTROL, 0x1D }, { VK_LMENU, 0x38 }, { VK_LSHIFT, 0x2A }, { VK_RSHIFT, 0x36 }, { VK_RCONTROL, 0x1D }, { VK_RMENU, 0x38 } };
            foreach (var vk in new List<ushort>(Held))
                if (Array.IndexOf(ReleaseMods, vk) < 0) evs.Add(new Ev { Kind = "key", Vk = vk, Up = true, Name = "held" });
            foreach (var vk in ReleaseMods) {
                bool down = Held.Contains(vk) || (Live && KeyDown(vk));
                if (down) evs.Add(new Ev { Kind = "key", Vk = vk, Scan = scans[vk], Ext = vk == VK_RCONTROL || vk == VK_RMENU, Up = true, Name = "release" });
            }
            foreach (var b in new[] { 1, 2, 4 }) if ((HeldButtons & b) != 0) evs.Add(new Ev { Kind = "up", Button = b });
            if (evs.Count == 0) return;
            var batch = evs.ToArray();
            string d = Describe(batch);
            if (Live) { RealSend(batch); Note("release: " + d); }
            else Plan.Add("release: " + d);
            Track(batch);
        }
    }

    // lock keys back to their initial state; the lock-key toggles are the one exception
    // to "only releases after an abort": they type no character
    public static void RestoreLocks() {
        if (!HaveInitial) return;
        ToggleTo(0x90, 0x45, true, InitialNumLock, "NumLock");
        ToggleTo(0x14, 0x3A, false, InitialCaps, "CapsLock");
    }

    // the layout is global on this PC: ask the window in front (the target if it still exists)
    public static IntPtr RequestLayout(IntPtr hkl) {
        IntPtr h = (Target != IntPtr.Zero && W.IsWindow(Target)) ? Target : W.GetForegroundWindow();
        if (h != IntPtr.Zero) W.PostMessage(h, 0x0050 /* WM_INPUTLANGCHANGEREQUEST */, IntPtr.Zero, hkl);
        return h;
    }

    public static void ToggleTo(ushort vk, ushort scan, bool ext, bool want, string name) {
        bool on = W.LockOn(vk);
        if (!Live && !AllowLockToggle) return;
        if (on == want) { Note(name + ": " + (want ? "on" : "off") + " requested, observed " + (on ? "on" : "off")); return; }
        var arr = new INPUT[2];
        arr[0] = ToInput(new Ev { Kind = "key", Vk = vk, Scan = scan, Ext = ext });
        arr[1] = ToInput(new Ev { Kind = "key", Vk = vk, Scan = scan, Ext = ext, Up = true });
        W.SendInput(2, arr, Marshal.SizeOf(typeof(INPUT)));
        Thread.Sleep(100);
        Note(name + ": " + (want ? "on" : "off") + " requested, observed " + (W.LockOn(vk) ? "on" : "off") + " after the toggle");
    }

    static bool handlersInstalled = false;
    // Ctrl+C on the driver's console and process exit: release everything, restore
    public static void InstallHandlers() {
        if (handlersInstalled) return;
        handlersInstalled = true;
        AppDomain.CurrentDomain.ProcessExit += (s, a) => Emergency("process exit");
        Console.CancelKeyPress += (s, a) => Emergency("Ctrl+C on the driver console");
    }

    public static void Emergency(string why) {
        try {
            if (!Live) return;
            Note("EMERGENCY (" + why + "): releasing keys and buttons, restoring lock keys and layout");
            Aborted = true;
            ReleaseAll();
            RestoreLocks();
            if (OriginalHkl != IntPtr.Zero) RequestLayout(OriginalHkl);
        } catch { }
    }
}
}
'@
}

# ---- keys: virtual-key, scan code, extended (E0) flag ------------------------------
$script:KeyDefs = @{
    Up = @(0x26, 0x48, 1); Down = @(0x28, 0x50, 1); Left = @(0x25, 0x4B, 1); Right = @(0x27, 0x4D, 1)
    Home = @(0x24, 0x47, 1); End = @(0x23, 0x4F, 1); PgUp = @(0x21, 0x49, 1); PgDn = @(0x22, 0x51, 1)
    Ins = @(0x2D, 0x52, 1); Del = @(0x2E, 0x53, 1)
    F1 = @(0x70, 0x3B, 0); F2 = @(0x71, 0x3C, 0); F3 = @(0x72, 0x3D, 0); F4 = @(0x73, 0x3E, 0)
    F5 = @(0x74, 0x3F, 0); F6 = @(0x75, 0x40, 0); F7 = @(0x76, 0x41, 0); F8 = @(0x77, 0x42, 0)
    F9 = @(0x78, 0x43, 0); F10 = @(0x79, 0x44, 0); F11 = @(0x7A, 0x57, 0); F12 = @(0x7B, 0x58, 0)
    Tab = @(0x09, 0x0F, 0); Enter = @(0x0D, 0x1C, 0); Esc = @(0x1B, 0x01, 0); Backspace = @(0x08, 0x0E, 0)
    Space = @(0x20, 0x39, 0); X = @(0x58, 0x2D, 0); A = @(0x41, 0x1E, 0); Z = @(0x5A, 0x2C, 0)
    Backslash = @(0xDC, 0x2B, 0)                         # VK_OEM_5 on the US layout
    KpClear = @(0x0C, 0x4C, 0); Kp5 = @(0x65, 0x4C, 0)   # keypad 5: NumLock off / on
    KpEnter = @(0x0D, 0x1C, 1)                           # keypad Enter = Enter + E0
    LShift = @(0xA0, 0x2A, 0); LCtrl = @(0xA2, 0x1D, 0); LAlt = @(0xA4, 0x38, 0)
    NumLock = @(0x90, 0x45, 1); CapsLock = @(0x14, 0x3A, 0)
    # never in the table; here only so the offline test can hand them to the wrapper
    LWin = @(0x5B, 0x5B, 1); RWin = @(0x5C, 0x5C, 1); Apps = @(0x5D, 0x5D, 1)
    RShift = @(0xA1, 0x36, 0); RCtrl = @(0xA3, 0x1D, 1)
}
$script:ModMap = @{ Shift = 'LShift'; Ctrl = 'LCtrl'; Alt = 'LAlt' }

function New-KeyEv([string]$name, [bool]$up) {
    $d = $script:KeyDefs[$name]
    if (-not $d) { throw "no key definition for '$name'" }
    $e = [TcAuto.Ev]::new()
    $e.Kind = 'key'; $e.Vk = [uint16]$d[0]; $e.Scan = [uint16]$d[1]; $e.Ext = [bool]$d[2]; $e.Up = $up; $e.Name = $name
    $e
}

# New-KeyBatch MODS KEY: modifiers down, key down, key up, modifiers up (one SendInput array)
function New-KeyBatch([string[]]$mods, [string]$key) {
    $b = [System.Collections.Generic.List[TcAuto.Ev]]::new()
    foreach ($m in $mods) { $b.Add((New-KeyEv $m $false)) }
    $b.Add((New-KeyEv $key $false))
    $b.Add((New-KeyEv $key $true))
    for ($k = $mods.Count - 1; $k -ge 0; $k--) { $b.Add((New-KeyEv $mods[$k] $true)) }
    , $b.ToArray()
}

function New-UniBatch([int]$code) {
    $d = [TcAuto.Ev]::new(); $d.Kind = 'uni'; $d.Scan = [uint16]$code
    $u = [TcAuto.Ev]::new(); $u.Kind = 'uni'; $u.Scan = [uint16]$code; $u.Up = $true
    , @($d, $u)
}

# ---- the key table: termcheck item id -> how to produce it ------------------------
# Kind key: Mods (left modifiers held around the key), Key (KeyDefs name), NumLock
# (on/off: forced before the item), Layout (log the layout before/after, restore).
# Kind uni: KEYEVENTF_UNICODE character. Kind mouse: Action/Button/Mods/Wheel.
# Kind resize: SetWindowPos. Alt+F4 never has an entry (termcheck runs without
# --with-dangerous; the wrapper refuses it too).
function Get-KeyTable {
    $t = [ordered]@{}
    $mods = @('', 'Shift', 'Ctrl', 'Alt')
    $add = {
        param($id, $group, $key, $modnames, $extra)
        $e = @{ Kind = 'key'; Group = $group; Key = $key; Mods = @($modnames | Where-Object { $_ } | ForEach-Object { $script:ModMap[$_] }); NumLock = $null; Layout = $false; Note = '' }
        if ($extra) { foreach ($k in $extra.Keys) { $e[$k] = $extra[$k] } }
        $t[$id] = $e
    }
    foreach ($b in 'Up', 'Down', 'Left', 'Right') { foreach ($m in $mods) { & $add (($m ? "$m+" : '') + $b) 'arrows' $b @($m) $null } }
    foreach ($b in 'Home', 'End', 'PgUp', 'PgDn', 'Ins', 'Del') { foreach ($m in $mods) { & $add (($m ? "$m+" : '') + $b) 'nav' $b @($m) $null } }
    foreach ($n in 1..12) {
        foreach ($m in $mods) {
            if ($m -eq 'Alt' -and $n -eq 4) { continue }      # Alt+F4: never
            & $add (($m ? "$m+" : '') + "F$n") 'fkeys' "F$n" @($m) $null
        }
    }
    & $add 'Tab' 'special' 'Tab' @() $null
    & $add 'Shift+Tab' 'special' 'Tab' @('Shift') $null
    & $add 'Enter' 'special' 'Enter' @() $null
    & $add 'Esc' 'special' 'Esc' @() $null
    & $add 'Backspace' 'special' 'Backspace' @() $null
    & $add 'Ctrl+Backspace' 'special' 'Backspace' @('Ctrl') $null
    & $add 'Alt+Backspace' 'special' 'Backspace' @('Alt') $null
    & $add 'Ctrl+Space' 'special' 'Space' @('Ctrl') $null
    & $add 'Alt+X' 'chars' 'X' @('Alt') $null
    & $add 'Alt+Shift+X' 'chars' 'X' @('Alt', 'Shift') @{ Layout = $true; Note = 'Alt+Shift may switch the layout; the layout is logged before/after and restored' }
    & $add 'Ctrl+A' 'chars' 'A' @('Ctrl') $null
    & $add 'Ctrl+Z' 'chars' 'Z' @('Ctrl') $null
    & $add 'Ctrl+\' 'chars' 'Backslash' @('Ctrl') $null
    $t['zhe'] = @{ Kind = 'uni'; Group = 'chars'; Code = 0x0436; Note = 'KEYEVENTF_UNICODE: tests the character path, not the Russian layout' }
    & $add 'Space' 'chars' 'Space' @() $null
    & $add 'Keypad5-NumLockOff' 'keypad' 'KpClear' @() @{ NumLock = 'off' }
    & $add 'Keypad5-NumLockOn' 'keypad' 'Kp5' @() @{ NumLock = 'on' }
    & $add 'KeypadEnter' 'keypad' 'KpEnter' @() @{ NumLock = 'on' }
    $mouse = {
        param($id, $action, $button, $modname, $wheel)
        $t[$id] = @{ Kind = 'mouse'; Group = 'mouse'; Action = $action; Button = $button; Mods = @($modname | Where-Object { $_ } | ForEach-Object { $script:ModMap[$_] }); Wheel = $wheel }
    }
    & $mouse 'Click-Left' 'click' 1 '' 0
    & $mouse 'Click-Right' 'click' 2 '' 0
    & $mouse 'Click-Middle' 'click' 4 '' 0
    & $mouse 'Wheel-Up' 'wheel' 0 '' 120
    & $mouse 'Wheel-Down' 'wheel' 0 '' -120
    & $mouse 'Drag' 'drag' 1 '' 0
    & $mouse 'Double-Click' 'dbl' 1 '' 0
    & $mouse 'Triple-Click' 'tri' 1 '' 0
    & $mouse 'Ctrl+Click' 'click' 1 'Ctrl' 0
    & $mouse 'Shift+Click' 'click' 1 'Shift' 0
    & $mouse 'Click-Far-Right' 'click' 1 '' 0
    $t['Resize'] = @{ Kind = 'resize'; Group = 'resize' }
    $t
}

# items a terminal must not get (S5); the driver passes them as TERMCHECK_SKIP
$script:SkipList = @{
    'mintty-git' = @('Alt+F2', 'Alt+F3', 'Alt+F8')
    'msys2'      = @('Alt+F2', 'Alt+F3', 'Alt+F8')
    'cygwin'     = @('Alt+F2', 'Alt+F3', 'Alt+F8')
    'wt'         = @()
    'conhost'    = @()
}
# keys that may change the window (full screen, default size): sent again when the client
# rectangle changed; Always = toggles with no size change (mintty Alt+F12 flip screen)
$script:UndoKeys = @('F11', 'Alt+F11', 'Alt+F10', 'Alt+F12')
$script:UndoAlways = @{ 'mintty-git' = @('Alt+F12'); 'msys2' = @('Alt+F12'); 'cygwin' = @('Alt+F12'); 'wt' = @(); 'conhost' = @() }

# Test-KeyTable LISTLINES: compare the table with termcheck --list-items; returns problem strings
function Test-KeyTable($table, [string[]]$listLines) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $ids = @{}
    foreach ($l in $listLines) {
        if (-not $l) { continue }
        $f = $l -split "`t"
        if ($f.Count -lt 4) { $problems.Add("bad --list-items line: $l"); continue }
        $ids[$f[1]] = $f[0]
        if (-not $table.Contains($f[1])) { $problems.Add("no table entry for item '$($f[1])' ($($f[0]))"); continue }
        $e = $table[$f[1]]
        if ($e.Group -ne $f[0]) { $problems.Add("item '$($f[1])': group $($f[0]) in termcheck, $($e.Group) in the table") }
        $kind = $f[2] -replace ':.*$', ''
        $want = @{ key = @('key', 'uni'); mouse = @('mouse'); resize = @('resize') }[$kind]
        if ($want -and $want -notcontains $e.Kind) { $problems.Add("item '$($f[1])': kind $($f[2]) in termcheck, $($e.Kind) in the table") }
    }
    foreach ($k in $table.Keys) { if (-not $ids.ContainsKey($k)) { $problems.Add("table entry '$k' is not a termcheck item") } }
    if ($table.Contains('Alt+F4')) { $problems.Add('the table has Alt+F4') }
    , $problems.ToArray()
}

function Get-ListItems {
    $tc = Join-Path $script:TcRepo 'tools/termcheck/termcheck.sh'
    $out = & $script:GitBash $tc --list-items
    if ($LASTEXITCODE -ne 0) { throw "termcheck --list-items failed (rc $LASTEXITCODE)" }
    , @($out)
}

# ---- the sync file ---------------------------------------------------------------------
# ConvertFrom-SyncLine LINE -> @{ Type; Group; Id; Result; Target=@(x,y[,x2,y2]); Screen=@(w,h); Cell; Cell2; Skipped; Status; Rc }
function ConvertFrom-SyncLine([string]$line) {
    $w = @($line -split ' ' | Where-Object { $_ -ne '' })
    if ($w.Count -eq 0) { return $null }
    $r = @{ Type = $w[0]; Raw = $line; Group = $null; Id = $null; Result = $null; Target = $null; Screen = $null; Cell = $null; Cell2 = $null; Skipped = $false; Reason = $null; Status = $null; Rc = $null }
    $i = 1
    switch ($w[0]) {
        'ready' { $r.Group = $w[1]; $r.Id = $w[2]; $i = 3 }
        { $_ -in 'done', 'retry' } { $r.Id = $w[1]; $r.Result = $w[2]; $i = 3 }
        'end' { $r.Status = $w[1]; if ($w.Count -gt 2) { $r.Rc = [int]$w[2] }; return $r }
        'finish-wait' { return $r }
        default { $r.Type = 'unknown'; return $r }
    }
    while ($i -lt $w.Count) {
        switch ($w[$i]) {
            'target' {
                $n = @(); $i++
                while ($i -lt $w.Count -and $w[$i] -match '^-?\d+$') { $n += [int]$w[$i]; $i++ }
                $r.Target = $n; continue
            }
            'screen' { $r.Screen = @([int]$w[$i + 1], [int]$w[$i + 2]); $i += 3; continue }
            'cell' { $r.Cell = @([int]$w[$i + 1], [int]$w[$i + 2]); $i += 3; continue }
            'cell2' { $r.Cell2 = @([int]$w[$i + 1], [int]$w[$i + 2]); $i += 3; continue }
            'skipped' {
                $r.Skipped = $true; $i++
                if ($i -lt $w.Count) { $r.Reason = $w[$i]; $i++ }
                continue
            }
            default { $i++ }
        }
    }
    $r
}

# a reader that hands out only complete (LF-terminated) lines; the file is opened with
# FileShare.ReadWrite because termcheck appends to it while the driver reads
class SyncReader {
    [string]$Path
    [long]$Pos = 0
    [string]$Partial = ''
    SyncReader([string]$p) { $this.Path = $p }
    [string[]] ReadLines() {
        if (-not [System.IO.File]::Exists($this.Path)) { return @() }
        [string]$text = ''
        $fs =[System.IO.FileStream]::new($this.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        try {
            if ($fs.Length -le $this.Pos) { return @() }
            $fs.Seek($this.Pos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $buf = [byte[]]::new($fs.Length - $this.Pos)
            $n = $fs.Read($buf, 0, $buf.Length)
            $this.Pos += $n
            $text = $this.Partial + [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
        } finally { $fs.Dispose() }
        $parts = $text -split "`n"
        $this.Partial = $parts[-1]                  # no LF yet: kept for the next read
        if ($parts.Count -le 1) { return @() }
        return @($parts[0..($parts.Count - 2)] | ForEach-Object { $_.TrimEnd("`r") })
    }
}

# ---- cell <-> pixel and calibration ------------------------------------------------------
# a grid per axis: pixel = Origin + Cell * (c + 0.5)
function New-Grid([double]$origin, [double]$cell) { @{ Origin = $origin; Cell = $cell } }

function Get-Pixel($grid, [int]$c) { [int][math]::Round($grid.Origin + $grid.Cell * ($c + 0.5)) }

# first guess from the client rectangle, the screen size W x H and the terminal's padding
$script:Padding = @{   # left, top, right, bottom at 96 DPI (inside the client rectangle)
    'wt'         = @(8, 48, 24, 8)     # 8 px padding; tab row on top; scroll bar on the right
    'conhost'    = @(0, 0, 0, 0)       # scroll bars are outside the client area
    'mintty-git' = @(1, 1, 1, 1)       # Padding=1 (mintty(1)); scroll bar outside the client area
    'msys2'      = @(1, 1, 1, 1)
    'cygwin'     = @(1, 1, 1, 1)
}
function Get-InitialGrids($client, [int]$cols, [int]$rows, [string]$terminal, [double]$scale) {
    $p = $script:Padding[$terminal]
    if (-not $p) { $p = @(0, 0, 0, 0) }
    $cw = (($client.Right - $client.Left) - ($p[0] + $p[2]) * $scale) / $cols
    $ch = (($client.Bottom - $client.Top) - ($p[1] + $p[3]) * $scale) / $rows
    @{ X = (New-Grid ($client.Left + $p[0] * $scale) $cw); Y = (New-Grid ($client.Top + $p[1] * $scale) $ch) }
}

# Update-Grid GRID SAMPLES: SAMPLES = list of @(pixel aimed at, cell received).
# Least squares pixel = o + s*(c+0.5) when there are two distinct cells, else only
# the origin moves; a fit with an absurd cell size is ignored.
function Update-Grid($grid, $samples) {
    $n = @($samples).Count
    if ($n -eq 0) { return $grid }
    $distinct = @($samples | ForEach-Object { $_[1] } | Sort-Object -Unique).Count
    if ($distinct -ge 2) {
        $sx = 0.0; $sy = 0.0; $sxx = 0.0; $sxy = 0.0
        foreach ($s in $samples) { $x = $s[1] + 0.5; $y = [double]$s[0]; $sx += $x; $sy += $y; $sxx += $x * $x; $sxy += $x * $y }
        $den = $n * $sxx - $sx * $sx
        if ([math]::Abs($den) -gt 1e-9) {
            $slope = ($n * $sxy - $sx * $sy) / $den
            if ($slope -ge 3 -and $slope -le 80) {
                # the received cells are floors, not centres: each sample says
                # o + s*c <= p < o + s*(c+1). Search s around the fit for the widest
                # feasible origin interval and take its middle (the most central grid).
                $best = $null; $bestW = 0.0
                $lo0 = [math]::Max(3.0, [math]::Min($slope, $grid.Cell) * 0.85); $hi0 = [math]::Min(80.0, [math]::Max($slope, $grid.Cell) * 1.15)
                for ($cw = $lo0; $cw -le $hi0; $cw += 0.005) {
                    $lo = -1e9; $hi = 1e9
                    foreach ($s in $samples) {
                        $a = $s[0] - $cw * ($s[1] + 1); $b = $s[0] - $cw * $s[1]
                        if ($a -gt $lo) { $lo = $a }
                        if ($b -lt $hi) { $hi = $b }
                    }
                    if ($hi - $lo -gt $bestW) { $bestW = $hi - $lo; $best = New-Grid (($lo + $hi) / 2) $cw }
                }
                if ($best) { return $best }
                return New-Grid (($sy - $slope * $sx) / $n) $slope     # no grid fits every sample: least squares
            }
        }
    }
    $o = 0.0
    foreach ($s in $samples) { $o += $s[0] - $grid.Cell * ($s[1] + 0.5) }
    New-Grid ($o / $n) $grid.Cell
}

# Limit-Grid NEW OLD MIN MAX: a fitted grid whose origin leaves the client rectangle is refused
function Limit-Grid($new, $old, [double]$min, [double]$max) {
    if ($new.Origin -lt $min -or $new.Origin -ge $max) {
        Write-DLog ("calibration refused: origin {0:N1} is outside the client area {1}..{2}; the old grid stays" -f $new.Origin, $min, $max)
        return $old
    }
    $new
}

# ---- the driver log --------------------------------------------------------------------
$script:DriverLog = $null
function Write-DLog([string]$msg) {
    if (-not [TcAuto.Inj]::Live -and -not $script:DriverLog) { [TcAuto.Inj]::Plan.Add("  # $msg"); return }   # dry run: part of the plan
    $line = (Get-Date).ToString('HH:mm:ss.fff') + ' ' + $msg
    if ($script:DriverLog) { [System.IO.File]::AppendAllText($script:DriverLog, $line + "`n") }
    Write-Host $line
}
# the wrapper's own notes (every injected event, every foreground check) into the log
function Sync-InjLog {
    foreach ($l in [TcAuto.Inj]::Log) {
        if ($script:DriverLog) { [System.IO.File]::AppendAllText($script:DriverLog, $l + "`n") }
    }
    [TcAuto.Inj]::Log.Clear()
}

# ---- item -> steps ---------------------------------------------------------------------
# a step: @{ Batch = Ev[]; WaitMs = pause after it; Note = text }
function New-Step($batch, [int]$waitMs = 0, [string]$note = '') { @{ Batch = $batch; WaitMs = $waitMs; Note = $note } }

function New-MouseEv([string]$kind, [int]$a = 0, [int]$b = 0) {
    $e = [TcAuto.Ev]::new(); $e.Kind = $kind
    switch ($kind) {
        'move' { $e.X = $a; $e.Y = $b }
        'down' { $e.Button = $a }
        'up' { $e.Button = $a }
        'wheel' { $e.Wheel = $a }
    }
    $e
}

# Get-ItemSteps ENTRY READY GRIDS -> steps for one item (keys need no grids)
function Get-ItemSteps($entry, $ready, $grids) {
    $steps = [System.Collections.Generic.List[object]]::new()
    switch ($entry.Kind) {
        'key' { $steps.Add((New-Step (New-KeyBatch $entry.Mods $entry.Key))) }
        'uni' { $steps.Add((New-Step (New-UniBatch $entry.Code) 0 $entry.Note)) }
        'mouse' {
            $t = $ready.Target
            if (-not $t -or $t.Count -lt 2) { throw "mouse item $($ready.Id) without a target in the ready line" }
            $px = Get-Pixel $grids.X $t[0]; $py = Get-Pixel $grids.Y $t[1]
            $modsDown = @($entry.Mods | ForEach-Object { New-KeyEv $_ $false })
            $modsUp = @($entry.Mods | ForEach-Object { New-KeyEv $_ $true })
            # every move is a batch of its own: the wrapper checks its point is over the target's
            # client area, the next batch checks the cursor really is there (and still is)
            $steps.Add((New-Step @((New-MouseEv move $px $py)) 20 'move'))
            switch ($entry.Action) {
                'click' {
                    $steps.Add((New-Step (@($modsDown) + @((New-MouseEv down $entry.Button), (New-MouseEv up $entry.Button)) + @($modsUp))))
                }
                'wheel' { $steps.Add((New-Step @((New-MouseEv wheel $entry.Wheel)))) }
                'drag' {
                    $qx = Get-Pixel $grids.X $t[2]; $qy = Get-Pixel $grids.Y $t[3]
                    $steps.Add((New-Step @((New-MouseEv down 1)) 20))
                    for ($k = 1; $k -le 6; $k++) {
                        $ix = [int][math]::Round($px + ($qx - $px) * $k / 7); $iy = [int][math]::Round($py + ($qy - $py) * $k / 7)
                        $steps.Add((New-Step @((New-MouseEv move $ix $iy)) 20))
                    }
                    $steps.Add((New-Step @((New-MouseEv move $qx $qy)) 20))
                    $steps.Add((New-Step @((New-MouseEv up 1))))
                }
                { $_ -in 'dbl', 'tri' } {
                    $n = $entry.Action -eq 'dbl' ? 2 : 3
                    $steps.Add((New-Step @((New-MouseEv down 1), (New-MouseEv up 1)) 80 'click 1 (FV double/triple window 0.44 s, timed with a Stopwatch)'))
                    for ($k = 2; $k -le $n; $k++) { $steps.Add((New-Step @((New-MouseEv down 1), (New-MouseEv up 1)) ($k -lt $n ? 80 : 0) "click $k")) }
                }
            }
        }
        'resize' { }     # SetWindowPos, see Invoke-Resize
    }
    , $steps.ToArray()
}

# Invoke-Steps STEPS: through the wrapper; pauses only in live mode; the clicks of a
# double/triple click must start within 0.40 s (FV counts 0.44 s)
function Invoke-Steps($steps, [string]$id) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $k = 0
    foreach ($s in $steps) {
        $k++
        if ($s.Note -and $s.Note -like 'click *' -and $k -gt 1 -and $sw.ElapsedMilliseconds -gt 400) {
            Write-DLog "WARN $id click $k starts after $($sw.ElapsedMilliseconds) ms (> 0.40 s)"
        }
        if (-not [TcAuto.Inj]::Live) {
            [TcAuto.Inj]::Plan.Add("  [$id]" + ($s.Note ? " ($($s.Note))" : ''))
        }
        [TcAuto.Inj]::Send($s.Batch)
        Sync-InjLog
        if ([TcAuto.Inj]::Live -and $s.WaitMs -gt 0) {
            $until = $sw.ElapsedMilliseconds + $s.WaitMs
            while ($sw.ElapsedMilliseconds -lt $until) { Start-Sleep -Milliseconds 2 }
        }
    }
}

# ---- live state: lock keys, layout, clipboard ----------------------------------------------
function Get-LockState { @{ NumLock = [TcAuto.W]::LockOn(0x90); Caps = [TcAuto.W]::LockOn(0x14) } }

function Get-ForegroundHkl { [TcAuto.W]::GetKeyboardLayout([TcAuto.W]::Thread([TcAuto.W]::GetForegroundWindow())) }

# Restore-Layout HKL: the layout is global on this PC (SPI_GETTHREADLOCALINPUTSETTINGS = 0), so
# WM_INPUTLANGCHANGEREQUEST goes to the target if it still exists, else to the window in front;
# confirmed on the foreground thread. $true when confirmed.
function Restore-Layout([IntPtr]$hkl) {
    if ($hkl -eq [IntPtr]::Zero) { return $true }
    $want = Format-Hkl $hkl
    for ($try = 0; $try -lt 2; $try++) {
        $h = [TcAuto.Inj]::RequestLayout($hkl)
        Write-DLog ("layout restore {0} requested from window 0x{1:X}" -f $want, $h.ToInt64())
        for ($k = 0; $k -lt 20; $k++) {
            Start-Sleep -Milliseconds 100
            if ((Format-Hkl (Get-ForegroundHkl)) -eq $want) { return $true }
        }
        [TcAuto.Inj]::Target = [IntPtr]::Zero      # second try: the window in front
    }
    $false
}

function Format-Hkl([IntPtr]$h) { '{0:X8}' -f ($h.ToInt64() -band 0xFFFFFFFF) }

function Get-UsHkl {
    $n = [TcAuto.W]::GetKeyboardLayoutList(0, $null)
    $list = [IntPtr[]]::new($n)
    [void][TcAuto.W]::GetKeyboardLayoutList($n, $list)
    foreach ($h in $list) { if (($h.ToInt64() -band 0xFFFFFFFF) -eq 0x04090409) { return $h } }
    [IntPtr]::Zero
}

function Get-TargetHkl([IntPtr]$hwnd) { [TcAuto.W]::GetKeyboardLayout([TcAuto.W]::Thread($hwnd)) }

# Set-TargetLayout HWND HKL: ask the window to switch (WM_INPUTLANGCHANGEREQUEST), re-check
function Set-TargetLayout([IntPtr]$hwnd, [IntPtr]$hkl) {
    [void][TcAuto.W]::PostMessage($hwnd, 0x0050, [IntPtr]::Zero, $hkl)
    for ($k = 0; $k -lt 20; $k++) {
        Start-Sleep -Milliseconds 100
        if ((Format-Hkl (Get-TargetHkl $hwnd)) -eq (Format-Hkl $hkl)) { return $true }
    }
    $false
}

# Set-NumLock ON: toggle through the wrapper (VK_NUMLOCK + EXTENDEDKEY, scan 0x45)
function Set-NumLock([bool]$on) {
    if (-not [TcAuto.Inj]::Live) { [TcAuto.Inj]::Plan.Add("  (ensure NumLock " + ($on ? 'on' : 'off') + ": toggled with VK_NUMLOCK E0 when it differs)"); return }
    $cur = [TcAuto.W]::LockOn(0x90)
    if ($cur -eq $on) { Write-DLog ("NumLock " + ($on ? 'on' : 'off') + " requested, observed " + ($cur ? 'on' : 'off')); return }
    [TcAuto.Inj]::Send((New-KeyBatch @() 'NumLock'))
    Sync-InjLog
    Start-Sleep -Milliseconds 100
    $now = [TcAuto.W]::LockOn(0x90)
    Write-DLog ("NumLock " + ($on ? 'on' : 'off') + " requested, observed " + ($now ? 'on' : 'off') + " after the toggle")
    if ($now -ne $on) { throw [TcAuto.AbortException]::new("NumLock did not follow the toggle") }
}

# ---- hotkeys taken by other programs ------------------------------------------------------------
# Get-TakenHotkeys TABLE [REGISTRAR]: the key items whose combo another program holds as a global
# hotkey (RegisterHotKey fails); each combo is held for an instant and released. Low-level
# keyboard hooks cannot be seen this way. REGISTRAR: scriptblock (mods, vk) -> $true when free (tests).
function Get-TakenHotkeys($table, [scriptblock]$registrar) {
    if (-not $registrar) {
        $registrar = {
            param($mods, $vk)
            $ok = [TcAuto.W]::RegisterHotKey([IntPtr]::Zero, 0xB7A0, ($mods -bor 0x4000), $vk)   # MOD_NOREPEAT
            if ($ok) { [void][TcAuto.W]::UnregisterHotKey([IntPtr]::Zero, 0xB7A0) }
            $ok
        }
    }
    $bits = @{ LAlt = 1; LCtrl = 2; LShift = 4 }
    $taken = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $table.Keys) {
        $e = $table[$id]
        if ($e.Kind -ne 'key') { continue }
        $m = 0
        foreach ($x in $e.Mods) { $m = $m -bor $bits[$x] }
        if (-not (& $registrar $m $script:KeyDefs[$e.Key][0])) { $taken.Add($id) }
    }
    , $taken.ToArray()
}

# ---- cleanup and the saved state ----------------------------------------------------------------
# Invoke-Cleanup STEPS: ordered @(name, scriptblock) pairs; every step runs, a failing one is
# logged and the next one still runs; returns the names of the failed steps
function Invoke-Cleanup($steps) {
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $steps) {
        try { & $s[1] } catch { $failed.Add($s[0]); try { Write-DLog "WARN cleanup step '$($s[0])' failed: $_" } catch { } }
    }
    , $failed.ToArray()
}

# the state to put back, written before anything is changed (for -Restore after a crash);
# it holds the clipboard text, so it is deleted once everything is restored
function Save-RunState([string]$root, $locks, [IntPtr]$hkl, $clip, [bool]$clipSaved) {
    $o = [ordered]@{ NumLock = $locks.NumLock; CapsLock = $locks.Caps; Layout = (Format-Hkl $hkl); ClipboardSaved = $clipSaved; Clipboard = $clip }
    Write-LfFile (Join-Path $root 'state.json') ($o | ConvertTo-Json)
}

# -Restore RUNDIR: lock keys (the only input), layout, clipboard from state.json
function Invoke-Restore([string]$dir) {
    $f = Join-Path $dir 'state.json'
    if (-not (Test-Path $f)) { throw "no state.json in '$dir' (nothing to restore, or it was restored already)" }
    $s = Get-Content -Raw $f | ConvertFrom-Json
    [TcAuto.Inj]::InitialNumLock = $s.NumLock; [TcAuto.Inj]::InitialCaps = $s.CapsLock; [TcAuto.Inj]::HaveInitial = $true
    [TcAuto.Inj]::AllowLockToggle = $true
    try { [TcAuto.Inj]::RestoreLocks() } finally { [TcAuto.Inj]::AllowLockToggle = $false }
    [TcAuto.Inj]::Log | ForEach-Object { Write-Output $_ }; [TcAuto.Inj]::Log.Clear()
    $hkl = [IntPtr]::new([Convert]::ToInt64($s.Layout, 16))
    $ok = Restore-Layout $hkl
    if ($s.ClipboardSaved) { Set-Clipboard -Value ($s.Clipboard ?? '') }
    if ($ok) { Remove-Item -LiteralPath $f; Write-Output "restored: NumLock $($s.NumLock), CapsLock $($s.CapsLock), layout $($s.Layout), clipboard" }
    else { Write-Output "keyboard layout not restored - press Win+Space (state.json kept)" }
}

# ---- windows ---------------------------------------------------------------------------------
function Find-TargetWindow([string]$title, [string]$cls, [int]$timeoutSec) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        $found = [TcAuto.W]::Find($title, $cls, 0)
        if ($found.Count -eq 1) { return $found[0] }
        if ($found.Count -gt 1) { throw "more than one window has the title '$title'" }
        Start-Sleep -Milliseconds 200
    }
    [IntPtr]::Zero
}

function Get-WindowProps([IntPtr]$hwnd) {
    @{ IsWindow = [TcAuto.W]::IsWindow($hwnd); Class = [TcAuto.W]::Cls($hwnd); Pid = [TcAuto.W]::Pid($hwnd); Title = [TcAuto.W]::Text($hwnd) }
}

# the window still is the one launched: same handle, class, PID and nonce title
function Test-SameWindow($win, $props) {
    if (-not $props) { $props = Get-WindowProps $win.Hwnd }
    if (-not $props.IsWindow) { return $false }
    if ($props.Class -ne $win.Class) { return $false }
    if ($props.Pid -ne $win.Pid) { return $false }
    $props.Title -like "*termcheck-$($win.Nonce)*"
}

function Get-Scale([IntPtr]$hwnd) { $d = [TcAuto.W]::GetDpiForWindow($hwnd); if ($d -le 0) { 1.0 } else { $d / 96.0 } }

function Get-ClientRect([IntPtr]$hwnd) { [TcAuto.W]::Client($hwnd) }

function Format-Rect($r) { "{0},{1}-{2},{3}" -f $r.Left, $r.Top, $r.Right, $r.Bottom }

# leave menu mode (F10, Alt, Shift+F10 can open it) with Esc, at most twice
function Exit-MenuMode([IntPtr]$hwnd, [string]$id) {
    for ($k = 0; $k -lt 2; $k++) {
        if (-not [TcAuto.W]::InMenuMode($hwnd)) { return }
        Write-DLog "the window is in menu mode after ${id}; sending Esc"
        [TcAuto.Inj]::Send((New-KeyBatch @() 'Esc'))
        Sync-InjLog
        Start-Sleep -Milliseconds 150
    }
    if ([TcAuto.W]::InMenuMode($hwnd)) { throw [TcAuto.AbortException]::new("the window stays in menu mode after $id") }
}

$script:KeyDefs['C'] = @(0x43, 0x2E, 0)

# the wrapper's allow-list: exactly the VK codes the table uses, plus Ctrl+C (finish), Esc (menu
# mode), NumLock and CapsLock (lock keys) and the left modifiers
function Get-AllowedVks($table) {
    $names = [System.Collections.Generic.HashSet[string]]::new([string[]]@('C', 'Esc', 'NumLock', 'CapsLock', 'LCtrl', 'LAlt', 'LShift'))
    foreach ($id in $table.Keys) {
        $e = $table[$id]
        if ($e.Kind -eq 'key') { [void]$names.Add($e.Key); foreach ($m in $e.Mods) { [void]$names.Add($m) } }
    }
    , [uint16[]]@($names | ForEach-Object { $script:KeyDefs[$_][0] } | Sort-Object -Unique)
}
[TcAuto.Inj]::SetAllowed((Get-AllowedVks (Get-KeyTable)))

# ---- one sync line -> driver actions (shared by the live run and the dry run) -------------
# CTX: Terminal, Table, Hwnd (0 in a dry run), FakeClient, Grids, Client, SX, SY (samples),
# Pending (the mouse pixels of the current item), Before (client rect before an undo key),
# HklBefore, Counts, Failures, State (run|finish|end), EndStatus, CtrlC, ReadyAt, Waiting
function New-Ctx([string]$terminal, $table, [IntPtr]$hwnd, $fakeClient) {
    @{ Terminal = $terminal; Table = $table; Hwnd = $hwnd; FakeClient = $fakeClient; Grids = $null; Client = $null
        SX = [System.Collections.Generic.List[object]]::new(); SY = [System.Collections.Generic.List[object]]::new()
        Pending = $null; Before = $null; HklBefore = $null; Counts = @{}; Failures = [System.Collections.Generic.List[string]]::new()
        State = 'run'; EndStatus = $null; EndRc = $null; CtrlC = 0; CtrlCAt = $null; ReadyAt = $null; Waiting = $null; Hkl = $null; UsHkl = $null
        SawReady = $false }
}

function Get-CtxClient($ctx) { if ($ctx.Hwnd -ne [IntPtr]::Zero) { Get-ClientRect $ctx.Hwnd } else { $ctx.FakeClient } }

function Send-CtrlC($ctx) {
    $ctx.CtrlC++
    $ctx.CtrlCAt = [DateTime]::UtcNow
    if (-not [TcAuto.Inj]::Live) { [TcAuto.Inj]::Plan.Add("  [finish] Ctrl+C #$($ctx.CtrlC)") }
    [TcAuto.Inj]::Send((New-KeyBatch @('LCtrl') 'C'))
    Sync-InjLog
}

function Step-SyncLine($ctx, $rec) {
    $live = [TcAuto.Inj]::Live
    switch ($rec.Type) {
        'ready' {
            $ctx.Waiting = $rec.Id; $ctx.ReadyAt = [DateTime]::UtcNow; $ctx.SawReady = $true
            if (-not $ctx.Table.Contains($rec.Id)) { Write-DLog "WARN no table entry for '$($rec.Id)': nothing sent, termcheck times out"; return }
            $e = $ctx.Table[$rec.Id]
            if ($e.Kind -eq 'key' -and $e.NumLock) { Set-NumLock ($e.NumLock -eq 'on') }
            if ($e.Kind -eq 'key' -and $e.Layout -and $live) {
                $ctx.HklBefore = Get-TargetHkl $ctx.Hwnd
                Write-DLog "layout before $($rec.Id): $(Format-Hkl $ctx.HklBefore)"
            }
            if ($script:UndoKeys -contains $rec.Id) { $ctx.Before = Get-CtxClient $ctx }
            if ($e.Kind -eq 'uni') { Write-DLog "$($rec.Id): $($e.Note)" }
            if ($e.Kind -eq 'mouse') {
                # the client rectangle is queried before every mouse item; a changed one restarts the calibration
                $client = Get-CtxClient $ctx
                if (-not $ctx.Grids -or (Format-Rect $client) -ne (Format-Rect $ctx.Client)) {
                    $scale = $live ? (Get-Scale $ctx.Hwnd) : 1.0
                    $ctx.Grids = Get-InitialGrids $client $rec.Screen[0] $rec.Screen[1] $ctx.Terminal $scale
                    $ctx.Client = $client; $ctx.SX.Clear(); $ctx.SY.Clear()
                    Write-DLog ("grid from client {0} screen {1}x{2}: x0={3:N1} cw={4:N2} y0={5:N1} ch={6:N2}" -f (Format-Rect $client), $rec.Screen[0], $rec.Screen[1], $ctx.Grids.X.Origin, $ctx.Grids.X.Cell, $ctx.Grids.Y.Origin, $ctx.Grids.Y.Cell)
                }
                $t = $rec.Target
                $ctx.Pending = @{ Id = $rec.Id; Px = (Get-Pixel $ctx.Grids.X $t[0]); Py = (Get-Pixel $ctx.Grids.Y $t[1]); Qx = $null; Qy = $null }
                if ($t.Count -ge 4) { $ctx.Pending.Qx = Get-Pixel $ctx.Grids.X $t[2]; $ctx.Pending.Qy = Get-Pixel $ctx.Grids.Y $t[3] }
            }
            if ($e.Kind -eq 'resize') { Invoke-Resize $ctx $rec }
            else { Invoke-Steps (Get-ItemSteps $e $rec $ctx.Grids) $rec.Id }
            # the foreground may be recovered only before the first item; from now on a loss aborts
            [TcAuto.Inj]::AllowFrontRecovery = $false
        }
        { $_ -in 'done', 'retry' } {
            $ctx.Waiting = $null
            if ($ctx.Pending -and $ctx.Pending.Id -eq $rec.Id -and $rec.Cell) {
                $ctx.SX.Add(@($ctx.Pending.Px, $rec.Cell[0])); $ctx.SY.Add(@($ctx.Pending.Py, $rec.Cell[1]))
                if ($rec.Cell2 -and $null -ne $ctx.Pending.Qx) { $ctx.SX.Add(@($ctx.Pending.Qx, $rec.Cell2[0])); $ctx.SY.Add(@($ctx.Pending.Qy, $rec.Cell2[1])) }
                $c = $ctx.Client
                $ctx.Grids = @{ X = (Limit-Grid (Update-Grid $ctx.Grids.X $ctx.SX) $ctx.Grids.X $c.Left $c.Right); Y = (Limit-Grid (Update-Grid $ctx.Grids.Y $ctx.SY) $ctx.Grids.Y $c.Top $c.Bottom) }
                Write-DLog ("calibration after {0} {1} cell {2},{3}: x0={4:N1} cw={5:N2} y0={6:N1} ch={7:N2}" -f $rec.Type, $rec.Id, $rec.Cell[0], $rec.Cell[1], $ctx.Grids.X.Origin, $ctx.Grids.X.Cell, $ctx.Grids.Y.Origin, $ctx.Grids.Y.Cell)
            }
            if ($rec.Type -eq 'retry') { Write-DLog "termcheck asks $($rec.Id) once more (the cell was off)"; return }
            $ctx.Pending = $null
            $r = $rec.Skipped ? 'SKIPPED' : $rec.Result
            $ctx.Counts[$r] = 1 + ($ctx.Counts[$r] ?? 0)
            if ($rec.Skipped) { Write-DLog "$($rec.Id): SKIPPED ($($rec.Reason ?? 'terminal skip-list'))"; return }
            $e = $ctx.Table[$rec.Id]
            if ($e -and $e.Kind -eq 'key' -and $e.Layout -and $live) {
                $after = Get-TargetHkl $ctx.Hwnd
                Write-DLog "layout after $($rec.Id): $(Format-Hkl $after)"
                if ((Format-Hkl $after) -ne (Format-Hkl $ctx.HklBefore)) {
                    Write-DLog "the layout changed; asking the window to switch back"
                    if (-not (Set-TargetLayout $ctx.Hwnd $ctx.HklBefore)) { $ctx.Failures.Add("$($rec.Id): the layout did not return to $(Format-Hkl $ctx.HklBefore)") }
                }
            }
            if ($script:UndoKeys -contains $rec.Id -and $e) {
                $now = Get-CtxClient $ctx
                $always = @($script:UndoAlways[$ctx.Terminal]) -contains $rec.Id
                if ($always -or (Format-Rect $now) -ne (Format-Rect $ctx.Before)) {
                    Write-DLog "$($rec.Id): client $(Format-Rect $ctx.Before) -> $(Format-Rect $now)$($always ? ' (toggle key)' : ''); sending the key again to undo"
                    if (-not $live) { [TcAuto.Inj]::Plan.Add("  [$($rec.Id)] undo: the same key again") }
                    [TcAuto.Inj]::Send((New-KeyBatch $e.Mods $e.Key)); Sync-InjLog
                    if ($live) { Start-Sleep -Milliseconds 800; Write-DLog "$($rec.Id): client now $(Format-Rect (Get-CtxClient $ctx))" }
                }
            }
            if ($live -and $e) { Exit-MenuMode $ctx.Hwnd $rec.Id }     # after every item, mouse ones too
        }
        'finish-wait' { $ctx.State = 'finish'; Send-CtrlC $ctx }
        'end' { $ctx.State = 'end'; $ctx.EndStatus = $rec.Status; $ctx.EndRc = $rec.Rc }
        default { Write-DLog "WARN unknown sync line: $($rec.Raw)" }
    }
}

# the resize item: grow the window by 3 columns and 2 rows (SetWindowPos), wait for done
function Invoke-Resize($ctx, $rec) {
    if (-not [TcAuto.Inj]::Live) { [TcAuto.Inj]::Plan.Add("  [Resize] SetWindowPos: +3 columns, +2 rows (no input)"); return }
    $r = [TcAuto.RECT]::new()
    [void][TcAuto.W]::GetWindowRect($ctx.Hwnd, [ref]$r)
    $client = Get-ClientRect $ctx.Hwnd
    $cw = ($client.Right - $client.Left) / [math]::Max(1, $rec.Screen[0]); $ch = ($client.Bottom - $client.Top) / [math]::Max(1, $rec.Screen[1])
    $w = ($r.Right - $r.Left) + [int][math]::Ceiling(3 * $cw); $h = ($r.Bottom - $r.Top) + [int][math]::Ceiling(2 * $ch)
    $ok = [TcAuto.W]::SetWindowPos($ctx.Hwnd, [IntPtr]::Zero, 0, 0, $w, $h, 0x0016)   # NOMOVE|NOZORDER|NOACTIVATE
    Write-DLog "resize: SetWindowPos to ${w}x${h} px: $ok"
}

# ---- the terminals ---------------------------------------------------------------------------
$script:TermSpecs = @{
    'wt'         = @{ Class = 'CASCADIA_HOSTING_WINDOW_CLASS'; Root = 'C:\bin\Git'; Shell = 'C:\bin\Git\usr\bin\bash.exe'; Drive = '/'; Msystem = $null }
    'conhost'    = @{ Class = 'ConsoleWindowClass'; Root = 'C:\bin\Git'; Shell = 'C:\bin\Git\usr\bin\bash.exe'; Drive = '/'; Msystem = $null }
    'mintty-git' = @{ Class = 'mintty'; Root = 'C:\bin\Git'; Shell = 'C:\bin\Git\usr\bin\bash.exe'; Drive = '/'; Msystem = $null }
    'msys2'      = @{ Class = 'mintty'; Root = 'C:\bin\msys64'; Shell = 'C:\bin\msys64\usr\bin\bash.exe'; Drive = '/'; Msystem = 'MSYS' }
    'cygwin'     = @{ Class = 'mintty'; Root = 'C:\bin\cygwin64'; Shell = 'C:\bin\cygwin64\bin\bash.exe'; Drive = '/cygdrive/'; Msystem = $null }
}

$script:FirstReadySec = 30      # the first 'ready' must come within this (else the terminal is given up)

# NO-WINDOW for mintty / conhost: stop the process the driver launched, after checking it still is
# that process (name and start time). Never for wt: wt.exe returns at once and its windows live in
# the shared WindowsTerminal.exe, which holds the owner's other windows.
function Stop-LaunchedChild([string]$t, $proc) {
    if ($t -eq 'wt' -or -not $proc) { return }
    $want = @{ 'conhost' = 'conhost'; 'mintty-git' = 'mintty'; 'msys2' = 'mintty'; 'cygwin' = 'mintty' }[$t]
    $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if (-not $p) { Write-DLog "${t}: the launched process $($proc.Id) has ended"; return }
    if ($p.ProcessName -ne $want -or $p.StartTime -ne $proc.StartTime) { Write-DLog "${t}: pid $($proc.Id) is no longer the launched $want; not stopped"; return }
    Stop-Process -Id $p.Id -Force
    Write-DLog "${t}: stopped the launched $want (pid $($p.Id))"
}

# C:\a\b -> /c/a/b (Git, MSYS2) or /cygdrive/c/a/b (Cygwin)
function ConvertTo-PosixPath([string]$win, [string]$drive) {
    $full = [System.IO.Path]::GetFullPath($win)
    $drive + $full.Substring(0, 1).ToLowerInvariant() + ($full.Substring(2) -replace '\\', '/')
}

function ConvertTo-ShSingle([string]$s) { "'" + ($s -replace "'", "'\''") + "'" }

# Get-LaunchCommand TERMINAL RUNSH NONCE -> @{ Exe; Args } (one argument string, quoted by hand;
# wt.exe treats ';' as its own separator, there is none in it)
function Get-LaunchCommand([string]$t, [string]$runSh, [string]$nonce) {
    $spec = $script:TermSpecs[$t]
    $p = ConvertTo-PosixPath $runSh $spec.Drive
    $title = "termcheck-$nonce"
    switch ($t) {
        'wt' { @{ Exe = 'wt.exe'; Args = "-w new new-tab --title $title --suppressApplicationTitle -- `"$script:GitBash`" -l `"$p`"" } }
        'conhost' { @{ Exe = 'conhost.exe'; Args = "`"$script:GitBash`" -l `"$p`"" } }
        'mintty-git' { @{ Exe = 'C:\bin\Git\usr\bin\mintty.exe'; Args = "-h never -t $title -e /usr/bin/bash -l `"$p`"" } }
        'msys2' { @{ Exe = 'C:\bin\msys64\usr\bin\mintty.exe'; Args = "-h never -t $title -e /usr/bin/bash -l `"$p`"" } }
        'cygwin' { @{ Exe = 'C:\bin\cygwin64\bin\mintty.exe'; Args = "-h never -t $title -e /bin/bash -l `"$p`"" } }
    }
}

# the script run inside the terminal (LF only)
function New-RunScript([string]$t, [string]$runDir, [string]$nonce, [int]$timeout, [string]$groups, [string[]]$taken = @()) {
    # the terminal's own skip-list, then the combos another program holds as hotkeys (ID:taken-hotkey)
    $skip = (@($script:SkipList[$t]) + @($taken | Where-Object { $_ } | ForEach-Object { "${_}:taken-hotkey" })) -join ','
    $only = $groups ? " --only $groups" : ''
    $s = @'
#!/bin/bash
# written by tools/termcheck/autodrive.ps1 for @TERM@; runs inside the terminal window
export PATH=/usr/bin:/bin:$PATH
tc_repo=$(cygpath -u @REPO@)
tc_run=$(cygpath -u @RUN@)
printf '%s\n' "$$" > "$tc_run/bash.pid"
cd "$tc_repo" || { printf 'stty-restored=no\nrc=cd-failed\n' > "$tc_run/stty.txt"; exit 1; }
tc_stty0=$(stty -g 2>/dev/null)
TERMCHECK_SYNC=$tc_run/sync.txt TERMCHECK_NONCE=@NONCE@ TERMCHECK_SKIP=@SKIP@ \
    "$BASH" tools/termcheck/termcheck.sh --timeout @TIMEOUT@ --out "$tc_run"@ONLY@
tc_rc=$?
tc_stty1=$(stty -g 2>/dev/null)
if [ -n "$tc_stty0" ] && [ "$tc_stty0" = "$tc_stty1" ]; then tc_r=yes; else tc_r=no; fi
printf 'stty-restored=%s\nrc=%s\n' "$tc_r" "$tc_rc" > "$tc_run/stty.txt"
sleep 2
exit 0
'@
    $s = $s.Replace('@TERM@', $t).Replace('@REPO@', (ConvertTo-ShSingle $script:TcRepo)).Replace('@RUN@', (ConvertTo-ShSingle $runDir))
    $s = $s.Replace('@NONCE@', $nonce).Replace('@SKIP@', (ConvertTo-ShSingle $skip)).Replace('@TIMEOUT@', [string]$timeout).Replace('@ONLY@', $only)
    $s -replace "`r", ''
}

# kills only the bash tree of run.sh (its PID from bash.pid), inside the same runtime
function New-KillScript([string]$runDir) {
    $s = @'
#!/bin/bash
# written by tools/termcheck/autodrive.ps1: ends the run.sh bash and its children only
export PATH=/usr/bin:/bin:$PATH
tc_run=$(cygpath -u @RUN@)
[ -s "$tc_run/bash.pid" ] || exit 0
root=$(cat "$tc_run/bash.pid")
case $root in ''|*[!0-9]*) echo "kill.sh: bad pid file"; exit 1 ;; esac
kill -0 "$root" 2>/dev/null || exit 0
# the pid must still be the run.sh bash (pids are reused)
cmd=$(tr '\0' ' ' < "/proc/$root/cmdline" 2>/dev/null)
case $cmd in
    *run.sh*) ;;
    *) echo "kill.sh: pid $root is not run.sh ($cmd); nothing killed"; exit 0 ;;
esac
all=$(ps -e | awk 'NR > 1 { if ($1 ~ /^[A-Z]$/) print $2, $3; else print $1, $2 }')
tree=" $root "
changed=1
while [ $changed = 1 ]; do
    changed=0
    while read -r p pp; do
        case $tree in *" $pp "*) case $tree in *" $p "*) ;; *) tree="$tree$p "; changed=1 ;; esac ;; esac
    done <<< "$all"
done
echo "killing: $tree"
kill -TERM $tree 2>/dev/null
sleep 1
kill -KILL $tree 2>/dev/null
exit 0
'@
    ($s.Replace('@RUN@', (ConvertTo-ShSingle $runDir))) -replace "`r", ''
}

function Write-LfFile([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false)) }

# the child's environment: no inherited terminal identity (restored right after the launch)
$script:ScrubVars = @('WT_SESSION', 'WT_PROFILE_ID', 'TERM', 'MSYSTEM', 'TERM_PROGRAM', 'TERM_PROGRAM_VERSION')
function Invoke-WithScrubbedEnv([string]$msystem, [scriptblock]$body) {
    $saved = @{}
    $names = @($script:ScrubVars) + @(Get-ChildItem env: | Where-Object { $_.Name -like 'VSCODE_*' -or $_.Name -like 'TERM_PROGRAM*' } | ForEach-Object Name)
    foreach ($n in ($names | Sort-Object -Unique)) { $saved[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
    if ($msystem) { [Environment]::SetEnvironmentVariable('MSYSTEM', $msystem) }
    try { & $body } finally {
        [Environment]::SetEnvironmentVariable('MSYSTEM', $null)
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
}

function Read-SttyFile([string]$runDir) {
    $f = Join-Path $runDir 'stty.txt'
    if (-not (Test-Path $f)) { return 'no-file' }
    $m = Select-String -Path $f -Pattern '^stty-restored=(\w+)' | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value } else { 'unreadable' }
}

function Read-TermcheckTotals([string]$runDir) {
    $log = Get-ChildItem -Path $runDir -Filter 'fv_termcheck_*.log' -ErrorAction SilentlyContinue | Select-Object -First 1
    $r = @{ OK = '-'; DIFF = '-'; NONE = '-'; INFO = '-'; Log = $null }
    if (-not $log) { return $r }
    $r.Log = $log.FullName
    $line = Select-String -Path $log.FullName -Pattern '^summary  total' | Select-Object -Last 1
    if ($line) { foreach ($k in 'OK', 'DIFF', 'NONE', 'INFO') { if ($line.Line -match "$k=(\d+)") { $r[$k] = $Matches[1] } } }
    $r
}

# window gone, else the bash tree killed (kill.sh), else WM_CLOSE after re-checking the window
function Close-Terminal($t, $win, [string]$runDir) {
    if (-not $win -or $win.Hwnd -eq [IntPtr]::Zero) { return }
    $gone = { -not [TcAuto.W]::IsWindow($win.Hwnd) }
    for ($k = 0; $k -lt 25 -and -not (& $gone); $k++) { Start-Sleep -Milliseconds 200 }
    if (& $gone) { Write-DLog "$t window closed by itself"; return }
    $kill = Join-Path $runDir 'kill.sh'
    if (Test-Path $kill) {
        Write-DLog "$t window still open: ending the run.sh bash tree (kill.sh)"
        $out = & $script:TermSpecs[$t].Shell (ConvertTo-PosixPath $kill $script:TermSpecs[$t].Drive) 2>&1
        Write-DLog "kill.sh: $out"
        for ($k = 0; $k -lt 15 -and -not (& $gone); $k++) { Start-Sleep -Milliseconds 200 }
        if (& $gone) { Write-DLog "$t window closed"; return }
    }
    if (Test-SameWindow $win) {
        Write-DLog "$t window still open: WM_CLOSE to 0x$($win.Hwnd.ToString('X')) (class $($win.Class), pid $($win.Pid), nonce title checked)"
        [void][TcAuto.W]::PostMessage($win.Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        for ($k = 0; $k -lt 15 -and -not (& $gone); $k++) { Start-Sleep -Milliseconds 200 }
        if (& $gone) { Write-DLog "$t window closed"; return }
        Write-DLog "WARN $t window stays open (a confirm dialog?); left as it is, no key is sent to it"
    } else {
        Write-DLog "WARN ${t}: the handle no longer matches the launched window; not closed"
    }
}

# ---- a live terminal run ---------------------------------------------------------------------
$script:Current = $null      # @{ Terminal; Win; RunDir } of the terminal being driven (for the finally)

function Invoke-LiveTerminal([string]$t, [string]$root, $table, [int]$nItems, [DateTime]$globalEnd, [string[]]$taken = @()) {
    $runDir = Join-Path $root $t
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $nonce = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $runSh = Join-Path $runDir 'run.sh'
    Write-LfFile $runSh (New-RunScript $t $runDir $nonce $Timeout $Groups $taken)
    Write-LfFile (Join-Path $runDir 'kill.sh') (New-KillScript $runDir)
    $cmd = Get-LaunchCommand $t $runSh $nonce
    $spec = $script:TermSpecs[$t]
    $res = @{ Terminal = $t; Result = 'started'; Stty = '-'; End = '-'; Driver = '' }
    Write-DLog "=== ${t}: launch: $($cmd.Exe) $($cmd.Args)"
    $proc = Invoke-WithScrubbedEnv $spec.Msystem { Start-Process -FilePath $cmd.Exe -ArgumentList $cmd.Args -WorkingDirectory $script:TcRepo -PassThru }
    $title = "termcheck-$nonce"
    $hwnd = Find-TargetWindow $title $spec.Class 40
    if ($hwnd -eq [IntPtr]::Zero) {
        Write-DLog "${t}: no window titled '$title' (class $($spec.Class)) within 40 s"
        $res.Result = 'NO-WINDOW'
        $out = & $spec.Shell (ConvertTo-PosixPath (Join-Path $runDir 'kill.sh') $spec.Drive) 2>&1
        Write-DLog "kill.sh: $out"
        Stop-LaunchedChild $t $proc
        return $res
    }
    $win = @{ Hwnd = $hwnd; Class = [TcAuto.W]::Cls($hwnd); Pid = [TcAuto.W]::Pid($hwnd); Nonce = $nonce }
    $script:Current = @{ Terminal = $t; Win = $win; RunDir = $runDir }
    Write-DLog ("${t}: window 0x{0:X} class {1} pid {2} (launcher pid {3})" -f $hwnd.ToInt64(), $win.Class, $win.Pid, ($proc ? $proc.Id : '-'))
    [TcAuto.Inj]::Target = $hwnd
    [TcAuto.Inj]::AllowFrontRecovery = $true      # until the first item only

    # US layout for the run (S2); the layout is global here, the run's original comes back at the end
    $orig = Get-TargetHkl $hwnd
    Write-DLog "${t}: layout of the window $(Format-Hkl $orig)"
    if ((Format-Hkl $orig) -ne '04090409') {
        $us = Get-UsHkl
        if ($us -eq [IntPtr]::Zero) { throw [TcAuto.AbortException]::new('the US keyboard layout (00000409) is not installed') }
        if (-not (Set-TargetLayout $hwnd $us)) { throw [TcAuto.AbortException]::new("the window did not switch to the US layout (still $(Format-Hkl (Get-TargetHkl $hwnd)))") }
        Write-DLog "${t}: layout switched to 04090409"
    }
    if ([TcAuto.W]::LockOn(0x14)) {
        Write-DLog "${t}: CapsLock is on; turning it off for the run"
        [TcAuto.Inj]::Send((New-KeyBatch @() 'CapsLock')); Sync-InjLog
        Start-Sleep -Milliseconds 100
        $c = [TcAuto.W]::LockOn(0x14)
        Write-DLog "${t}: CapsLock off requested, observed $($c ? 'on' : 'off')"
        if ($c) { throw [TcAuto.AbortException]::new('CapsLock did not turn off') }
    }

    $ctx = New-Ctx $t $table $hwnd $null
    $reader = [SyncReader]::new((Join-Path $runDir 'sync.txt'))
    $itemLimit = [TimeSpan]::FromSeconds($Timeout + 5)
    $termStart = [DateTime]::UtcNow
    $termEnd = $termStart.AddSeconds($nItems * ($Timeout + 5) + 60)
    if ($termEnd -gt $globalEnd) { $termEnd = $globalEnd }
    while ($ctx.State -ne 'end') {
        $now = [DateTime]::UtcNow
        if ($now -gt $globalEnd) { throw [TcAuto.AbortException]::new("the run is over -MaxMinutes $MaxMinutes") }
        if ($now -gt $termEnd) { Write-DLog "${t}: whole-terminal timeout"; $res.Result = 'TIMEOUT'; break }
        if (-not $ctx.SawReady -and ($now - $termStart).TotalSeconds -gt $script:FirstReadySec) {
            Write-DLog "${t}: no 'ready' from termcheck within $($script:FirstReadySec) s"; $res.Result = 'NO-READY'; break
        }
        $lines = $reader.ReadLines()
        if ($lines.Count -eq 0) {
            $why = [TcAuto.Inj]::Idle()
            if ($why) { [TcAuto.Inj]::Note("ABORT: $why"); Sync-InjLog; throw [TcAuto.AbortException]::new($why) }
            if ($ctx.Waiting -and ($now - $ctx.ReadyAt) -gt $itemLimit) { Write-DLog "${t}: item $($ctx.Waiting) stuck (no done within $($itemLimit.TotalSeconds) s)"; $res.Result = 'STUCK'; break }
            if ($ctx.State -eq 'finish' -and ($now - $ctx.CtrlCAt).TotalSeconds -gt 3) {
                if ($ctx.CtrlC -ge 3) { Write-DLog "${t}: no 'end' after 3 Ctrl+C"; $res.Result = 'NO-END'; break }
                Write-DLog "${t}: no 'end' 3 s after Ctrl+C; sending it again"
                Send-CtrlC $ctx
            }
            Start-Sleep -Milliseconds 30
            continue
        }
        foreach ($l in $lines) {
            Write-DLog "sync: $l"
            $rec = ConvertFrom-SyncLine $l
            if ($rec) { Step-SyncLine $ctx $rec }
            if ($ctx.State -eq 'end') { break }
        }
    }
    if ($ctx.State -eq 'end') { $res.Result = 'ran'; $res.End = "$($ctx.EndStatus) $($ctx.EndRc)" }
    for ($k = 0; $k -lt 50 -and -not (Test-Path (Join-Path $runDir 'stty.txt')); $k++) { Start-Sleep -Milliseconds 200 }
    $res.Stty = Read-SttyFile $runDir
    $res.Driver = ($ctx.Failures -join '; ')
    Close-Terminal $t $win $runDir
    [TcAuto.Inj]::Target = [IntPtr]::Zero
    $script:Current = $null
    $res
}

# ---- the dry run ---------------------------------------------------------------------------------
# New-SimulatedSync LISTLINES TERMINAL W H: the sync lines a clean run would write
function New-SimulatedSync([string[]]$listLines, [string]$t, [int]$w = 80, [int]$h = 24) {
    $out = [System.Collections.Generic.List[string]]::new()
    $skip = @($script:SkipList[$t])
    foreach ($l in $listLines) {
        if (-not $l) { continue }
        $f = $l -split "`t"
        $g = $f[0]; $id = $f[1]; $kind = $f[2]; $exp = $f[3]
        if ($id -eq 'Click-Far-Right' -and $w -lt 230) { continue }
        if ($skip -contains $id) { $out.Add("done $id NONE skipped"); continue }
        if ($kind -like 'mouse:*') {
            if ($exp -match 'down@(\d+),(\d+),up@(\d+),(\d+)') {
                $out.Add("ready $g $id target $($Matches[1]) $($Matches[2]) $($Matches[3]) $($Matches[4]) screen $w $h")
                $out.Add("done $id OK cell $($Matches[1]) $($Matches[2]) cell2 $($Matches[3]) $($Matches[4])")
            } elseif ($exp -match 'x=(\d+),y=(\d+)') {
                $out.Add("ready $g $id target $($Matches[1]) $($Matches[2]) screen $w $h")
                $out.Add("done $id OK cell $($Matches[1]) $($Matches[2])")
            }
        } elseif ($kind -eq 'resize') {
            $out.Add("ready $g $id screen $w $h"); $out.Add("done $id OK screen $($w + 3) $($h + 2)")
        } else {
            $out.Add("ready $g $id"); $out.Add("done $id OK")
        }
    }
    $out.Add('finish-wait'); $out.Add('end complete 130')
    , $out.ToArray()
}

function Invoke-DryTerminal([string]$t, $table, [string[]]$syncLines, [string]$root) {
    [TcAuto.Inj]::Plan.Clear()
    $runDir = Join-Path $root $t
    $runSh = Join-Path $runDir 'run.sh'
    $cmd = Get-LaunchCommand $t $runSh 'NONCE'
    [TcAuto.Inj]::Plan.Add("=== $t (dry run: no window, no input)")
    [TcAuto.Inj]::Plan.Add("launch: $($cmd.Exe) $($cmd.Args)")
    [TcAuto.Inj]::Plan.Add("window: title termcheck-NONCE, class $($script:TermSpecs[$t].Class)")
    [TcAuto.Inj]::Plan.Add("skip-list (TERMCHECK_SKIP): " + (($script:SkipList[$t]) -join ',' ))
    [TcAuto.Inj]::Plan.Add("run.sh:")
    foreach ($l in ((New-RunScript $t $runDir 'NONCE' $Timeout $Groups) -split "`n")) { [TcAuto.Inj]::Plan.Add("  | $l") }
    # a made-up client rectangle: 9x18 px cells at (100,100) plus the terminal's padding
    $p = $script:Padding[$t]
    $fake = [TcAuto.RECT]@{ Left = 100; Top = 100; Right = 100 + 80 * 9 + $p[0] + $p[2]; Bottom = 100 + 24 * 18 + $p[1] + $p[3] }
    $ctx = New-Ctx $t $table ([IntPtr]::Zero) $fake
    foreach ($l in $syncLines) {
        $rec = ConvertFrom-SyncLine $l
        if (-not $rec) { continue }
        [TcAuto.Inj]::Plan.Add("sync: $l")
        Step-SyncLine $ctx $rec
        if ($ctx.State -eq 'end') { break }
    }
    [TcAuto.Inj]::Plan.Add("results: " + (($ctx.Counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ') + "; end: $($ctx.EndStatus) $($ctx.EndRc)")
    , @([TcAuto.Inj]::Plan)
}

function Write-Summary($rows, [string]$path, [string[]]$notes = @()) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('{0,-11} {1,-10} {2,5} {3,5} {4,5} {5,5}  {6,-14} {7,-16} {8}' -f 'terminal', 'run', 'OK', 'DIFF', 'NONE', 'INFO', 'stty-restored', 'end', 'notes'))
    foreach ($r in $rows) {
        $tot = Read-TermcheckTotals (Join-Path (Split-Path $path) $r.Terminal)
        $lines.Add(('{0,-11} {1,-10} {2,5} {3,5} {4,5} {5,5}  {6,-14} {7,-16} {8}' -f $r.Terminal, $r.Result, $tot.OK, $tot.DIFF, $tot.NONE, $tot.INFO, $r.Stty, $r.End, $r.Driver))
    }
    foreach ($n in $notes) { if ($n) { $lines.Add("!!! $n") } }
    Write-LfFile $path (($lines -join "`n") + "`n")
    $lines | ForEach-Object { Write-Host $_ }
}

# ---- main ------------------------------------------------------------------------------------------
function Invoke-Main {
    if ($Restore) {
        if ($Live) { throw '-Restore and -Live together: choose one' }
        Invoke-Restore $Restore
        return
    }
    if ($Live -and $DryRun) { throw '-Live and -DryRun together: choose one' }
    if ($Groups -and $Groups -notmatch '^[a-z]+(,[a-z]+)*$') { throw "-Groups '$Groups': a comma list of termcheck groups" }
    $table = Get-KeyTable
    $list = Get-ListItems
    $problems = Test-KeyTable $table $list
    if ($problems.Count) { throw ("the key table does not match termcheck --list-items:`n  " + ($problems -join "`n  ")) }
    if ($Groups) { $want = $Groups -split ','; $list = @($list | Where-Object { $want -contains ($_ -split "`t")[0] }) }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    if (-not $Live) {
        [TcAuto.Inj]::Live = $false
        $root = $OutDir ? $OutDir : (Join-Path $script:TcRepo "tools\termcheck\runs\$stamp")
        $terms = $ReplaySync ? @($Terminals[0]) : $Terminals
        $all = [System.Collections.Generic.List[string]]::new()
        $all.Add("autodrive DRY RUN: no window is opened and no input is sent. Key table: $($table.Count) entries, matches termcheck --list-items.")
        foreach ($t in $terms) {
            $sync = $ReplaySync ? @(Get-Content -LiteralPath $ReplaySync) : (New-SimulatedSync $list $t)
            foreach ($l in (Invoke-DryTerminal $t $table $sync $root)) { $all.Add($l) }
        }
        if ($OutDir) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null; Write-LfFile (Join-Path $OutDir 'plan.txt') (($all -join "`n") + "`n") }
        $all | ForEach-Object { Write-Output $_ }
        return
    }

    # ---- live ----
    if (-not [TcAuto.W]::EnsurePerMonitorV2()) { throw 'the process is not per-monitor-v2 DPI aware; mouse pixels would be wrong (nothing was sent)' }
    $mutex = [System.Threading.Mutex]::new($false, 'Local\kbool-termcheck-autodrive')
    if (-not $mutex.WaitOne(0)) { throw 'another autodrive.ps1 is running' }
    $root = $OutDir ? $OutDir : (Join-Path $script:TcRepo "tools\termcheck\runs\$stamp")
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $script:DriverLog = Join-Path $root 'driver.log'
    $clip = $null; $clipSaved = $false; $layoutOk = $true; $taken = @()
    $rows = [System.Collections.Generic.List[object]]::new()
    try {
        if ([TcAuto.W]::GetForegroundWindow() -eq [IntPtr]::Zero -or -not [Environment]::UserInteractive) { throw [TcAuto.AbortException]::new('no interactive desktop (no foreground window)') }
        Write-DLog "autodrive LIVE: terminals $($Terminals -join ','), groups $(if ($Groups) { $Groups } else { 'all' }), item timeout $Timeout s, cap $MaxMinutes min, results in $root"
        Write-DLog 'abort: move the mouse, or hold Right Shift + Right Ctrl'
        # all modifiers up before anything is sent (5 s)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $down = @(0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C | Where-Object { ([TcAuto.W]::GetAsyncKeyState($_) -band 0x8000) -ne 0 })
            if ($down.Count -eq 0) { break }
            if ($sw.Elapsed.TotalSeconds -gt 5) { throw [TcAuto.AbortException]::new('modifier keys stay pressed (5 s); release them and start again') }
            Start-Sleep -Milliseconds 100
        }
        # what has to come back, saved first (state.json, for -Restore after a crash)
        $locks = Get-LockState
        $hkl0 = Get-ForegroundHkl
        [TcAuto.Inj]::InitialNumLock = $locks.NumLock; [TcAuto.Inj]::InitialCaps = $locks.Caps; [TcAuto.Inj]::HaveInitial = $true
        [TcAuto.Inj]::OriginalHkl = $hkl0
        Write-DLog "initial: NumLock $($locks.NumLock) CapsLock $($locks.Caps) layout(foreground) $(Format-Hkl $hkl0)"
        try { $clip = Get-Clipboard -Raw; $clipSaved = $true } catch { Write-DLog "WARN clipboard not readable: $_" }
        Save-RunState $root $locks $hkl0 $clip $clipSaved
        # combos another program holds as global hotkeys are skipped (low-level hooks cannot be seen)
        $taken = Get-TakenHotkeys $table
        if ($taken.Count) { Write-DLog "hotkeys taken by other programs, skipped (taken-hotkey): $($taken -join ', ')" } else { Write-DLog 'hotkey preflight: no table combo is taken' }
        Set-Clipboard -Value 'termcheck-clip'
        [TcAuto.Inj]::InstallHandlers()
        [TcAuto.Inj]::Live = $true
        [TcAuto.Inj]::ResetCursorRef()
        $globalEnd = [DateTime]::UtcNow.AddMinutes($MaxMinutes)
        foreach ($t in $Terminals) {
            $rows.Add((Invoke-LiveTerminal $t $root $table $list.Count $globalEnd $taken))
        }
    } catch {
        # an abort thrown inside a .NET method arrives wrapped (MethodInvocationException)
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [TcAuto.AbortException])) { $ex = $ex.InnerException }
        $msg = $ex ? "ABORTED: $($ex.Message)" : "ABORTED on an error: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
        $script:RunAborted = $true
        try { Write-DLog $msg } catch { }
        if ($script:Current) { $rows.Add(@{ Terminal = $script:Current.Terminal; Result = 'ABORTED'; Stty = (Read-SttyFile $script:Current.RunDir); End = '-'; Driver = $msg }) }
    } finally {
        # every step on its own: a failing one does not stop the next
        $failed = Invoke-Cleanup @(
            , @('release keys and buttons', { [TcAuto.Inj]::Aborted = $true; [TcAuto.Inj]::ReleaseAll() })
            , @('lock keys', { [TcAuto.Inj]::RestoreLocks() })
            , @('driver log', { Sync-InjLog })
            , @('close the terminal', { if ($script:Current) { Close-Terminal $script:Current.Terminal $script:Current.Win $script:Current.RunDir } })
            , @('keyboard layout', { $script:LayoutOk = Restore-Layout ([TcAuto.Inj]::OriginalHkl) })
            , @('stop injecting', { [TcAuto.Inj]::Live = $false; [TcAuto.Inj]::Target = [IntPtr]::Zero })
            , @('clipboard', { if ($clipSaved) { if ($null -ne $clip -and $clip -ne '') { Set-Clipboard -Value $clip } else { Set-Clipboard -Value '' } } })
            , @('final state', { $l = Get-LockState; Write-DLog "final: NumLock $($l.NumLock) CapsLock $($l.Caps) layout(foreground) $(Format-Hkl (Get-ForegroundHkl))" })
            , @('mutex', { $mutex.ReleaseMutex(); $mutex.Dispose() })
        )
        $layoutOk = $script:LayoutOk -and ($failed -notcontains 'keyboard layout')
        if ($layoutOk -and $failed.Count -eq 0) { Remove-Item -LiteralPath (Join-Path $root 'state.json') -ErrorAction SilentlyContinue }
        elseif ($failed.Count) { Write-DLog "cleanup steps failed: $($failed -join ', '); state.json kept: pwsh -File tools\termcheck\autodrive.ps1 -Restore `"$root`"" }
    }
    $notes = @()
    if (-not $layoutOk) { $notes += 'keyboard layout not restored - press Win+Space' }
    if ($taken.Count) { $notes += "skipped, hotkeys taken by other programs (taken-hotkey): $($taken -join ', ')" }
    Write-Summary $rows (Join-Path $root 'summary.txt') $notes
    if (-not $layoutOk) { Write-Host '!!! keyboard layout not restored - press Win+Space !!!' -ForegroundColor Red }
    Write-DLog "results: $root (summary.txt, driver.log, one folder per terminal with the termcheck log)"
    if ($script:RunAborted) { exit 3 }
}
$script:RunAborted = $false
$script:LayoutOk = $true

if (-not $LibraryOnly) { Invoke-Main }

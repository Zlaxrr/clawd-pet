# Clawd Pet - the official Claude crab mascot living on your desktop, always on top of other windows.
# Uses the official animation assets from claude.ai (assets\ folder).
#   Eyes        : always follow the cursor; blinks every few seconds
#   Cursor near : stops walking and watches; on touch -> startled little hop
#   Typing      : "?" bubble + confused wobble for a few seconds
#   Left click  : wave / jump / wiggle / dance (random)
#   Picked up   : claw hooks onto the cursor - dangles, swings, and PANICS
#                 (eyes bulge, pupils tremble, sweat, shaking)
#   Released    : falls, squashes, then jumps for joy
#   On its own  : sometimes dances, looks around, or dozes off (Zz...)
#   Right click : exit menu
# Run with -TestBlink to test sprite generation only (no window).

param([switch]$TestBlink)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Only one Clawd allowed. An "abandoned" mutex (old owner killed) still counts as acquired.
$script:mutex = New-Object System.Threading.Mutex($false, 'ClawdPetMutex')
if (-not $TestBlink) {
    try {
        if (-not $script:mutex.WaitOne(0, $false)) { exit }
    } catch [System.Threading.AbandonedMutexException] { }
}

# C# helpers (see each class comment)
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// The ImageAnimator frame callback runs on a non-UI thread; the handler must be compiled code.
public static class ClawdAnim {
    private static void NoOp(object s, EventArgs e) { }
    public static void Start(Image i) { if (ImageAnimator.CanAnimate(i)) ImageAnimator.Animate(i, NoOp); }
    public static void Stop(Image i)  { if (ImageAnimator.CanAnimate(i)) ImageAnimator.StopAnimate(i, NoOp); }
}

// List of visible app windows -> platform footings (their top edge).
// Format: [hwnd, left, top, right, bottom] per window, ordered by z-order (topmost first).
public static class ClawdWin {
    private delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT rect, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int L, T, R, B; }
    public static long[] PlatformsArr(long selfHwnd) {
        var list = new List<long>();
        EnumWindows(delegate(IntPtr h, IntPtr lp) {
            if ((long)h == selfHwnd) return true;
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            if (GetWindowTextLength(h) == 0) return true;
            if ((GetWindowLong(h, -20) & 0x80) != 0) return true;   // WS_EX_TOOLWINDOW
            int cloaked;
            if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
            RECT r;
            if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) return true;
            if (r.R - r.L < 120 || r.B - r.T < 80) return true;
            list.Add((long)h); list.Add(r.L); list.Add(r.T); list.Add(r.R); list.Add(r.B);
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
    public static int[] GetRect(long h) {
        if (!IsWindowVisible((IntPtr)h) || IsIconic((IntPtr)h)) return null;
        int cloaked;
        if (DwmGetWindowAttribute((IntPtr)h, 14, out cloaked, 4) == 0 && cloaked != 0) return null;
        RECT r;
        if (DwmGetWindowAttribute((IntPtr)h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) return null;
        return new int[] { r.L, r.T, r.R, r.B };
    }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
    // Move a window by a few pixels (for Clawd window-tugging mischief)
    public static void Nudge(long h, int dx, int dy) {
        RECT wr;
        if (!GetWindowRect((IntPtr)h, out wr)) return;
        SetWindowPos((IntPtr)h, IntPtr.Zero, wr.L + dx, wr.T + dy, 0, 0, 0x0001 | 0x0004 | 0x0010);   // NOSIZE|NOZORDER|NOACTIVATE
    }
    [DllImport("user32.dll", CharSet = CharSet.Auto)] private static extern int GetClassName(IntPtr h, System.Text.StringBuilder sb, int max);
    // Foreground window covers the whole screen (fullscreen/borderless game)?
    public static bool IsFullscreenForeground(int bL, int bT, int bR, int bB) {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return false;
        var sb = new System.Text.StringBuilder(64);
        GetClassName(h, sb, 64);
        string c = sb.ToString();
        if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd") return false;   // the desktop/taskbar itself
        RECT r;
        if (!GetWindowRect(h, out r)) return false;
        return r.L <= bL && r.T <= bT && r.R >= bR && r.B >= bB;
    }
    // Return unused pages to the OS (lightens the reported working set in the background).
    [DllImport("psapi.dll")] private static extern bool EmptyWorkingSet(IntPtr h);
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    public static void TrimMemory() { EmptyWorkingSet(GetCurrentProcess()); }
    // Give the right-click menu the foreground. The pet window is WS_EX_NOACTIVATE, so the
    // menu opens without activation and WinForms never sees the "click outside" that would
    // dismiss it. Foregrounding the menu restores normal click-away-to-close behavior.
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
    public static void SetForeground(long h) { SetForegroundWindow((IntPtr)h); }
}

// Detect a keyboard key press (mouse buttons excluded) + how long the user has been idle.
public static class ClawdInput {
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")]
    private static extern uint GetTickCount();
    public static bool AnyKeyDown() {
        for (int vk = 0x08; vk <= 0xFE; vk++) {
            if (vk == 0x01 || vk == 0x02 || vk == 0x04 || vk == 0x05 || vk == 0x06) continue;
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) return true;
        }
        return false;
    }
    public static int IdleSeconds() {
        LASTINPUTINFO li = new LASTINPUTINFO();
        li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref li)) return 0;
        return (int)((GetTickCount() - li.dwTime) / 1000);
    }
}

// Analyze the eye pixels (black squares) on the official sprite -> blink variant, no-eyes variant,
// and the position of both eyes (to redraw them following the cursor / panic bulge).
public static class ClawdFx {
    private static byte[] Grab(Bitmap bmp, out int stride) {
        var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        stride = bd.Stride;
        byte[] d = new byte[stride * bmp.Height];
        Marshal.Copy(bd.Scan0, d, 0, d.Length);
        bmp.UnlockBits(bd);
        return d;
    }
    private static void Put(Bitmap bmp, byte[] d) {
        var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(d, 0, bd.Scan0, d.Length);
        bmp.UnlockBits(bd);
    }
    private static List<Point> Dark(byte[] d, int stride, int x0, int y0, int x1, int y1) {
        var dark = new List<Point>();
        for (int y = y0; y <= y1; y++) {
            int row = y * stride;
            for (int x = x0; x <= x1; x++) {
                int i = row + x * 4;
                if (d[i + 3] >= 200 && d[i + 2] < 70 && d[i + 1] < 70 && d[i] < 70) dark.Add(new Point(x, y));
            }
        }
        return dark;
    }
    private static int BodyColor(byte[] d, int stride, int x0, int y0, int x1, int y1) {
        var counts = new Dictionary<int, int>();
        for (int y = y0; y <= y1; y++) {
            int row = y * stride;
            for (int x = x0; x <= x1; x++) {
                int i = row + x * 4;
                byte b = d[i], g = d[i + 1], r = d[i + 2], a = d[i + 3];
                if (a < 200 || (r < 70 && g < 70 && b < 70)) continue;
                int key = (r << 16) | (g << 8) | b;
                int c; counts.TryGetValue(key, out c); counts[key] = c + 1;
            }
        }
        int best = 0, bestC = 0;
        foreach (var kv in counts) if (kv.Value > bestC) { bestC = kv.Value; best = kv.Key; }
        return best;
    }
    private static Bitmap Clone32(Bitmap src) {
        var bmp = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) g.DrawImage(src, 0, 0, src.Width, src.Height);
        return bmp;
    }
    public static int[] FindEyes(Bitmap src, int rx, int ry, int rw, int rh) {
        int stride;
        var bmp = Clone32(src);
        byte[] d = Grab(bmp, out stride);
        bmp.Dispose();
        int x1c = Math.Min(src.Width - 1, rx + rw), y1c = Math.Min(src.Height - 1, ry + rh);
        var dark = Dark(d, stride, Math.Max(0, rx), Math.Max(0, ry), x1c, y1c);
        if (dark.Count == 0) return new int[8];
        int minX = int.MaxValue, maxX = int.MinValue;
        foreach (var p in dark) { if (p.X < minX) minX = p.X; if (p.X > maxX) maxX = p.X; }
        int midX = (minX + maxX) / 2;
        int[] o = new int[8];
        for (int side = 0; side < 2; side++) {
            int cnX = int.MaxValue, cxX = int.MinValue, cnY = int.MaxValue, cxY = int.MinValue;
            foreach (var p in dark) {
                bool left = p.X <= midX;
                if ((side == 0) != left) continue;
                if (p.X < cnX) cnX = p.X; if (p.X > cxX) cxX = p.X;
                if (p.Y < cnY) cnY = p.Y; if (p.Y > cxY) cxY = p.Y;
            }
            o[side * 4] = cnX; o[side * 4 + 1] = cnY; o[side * 4 + 2] = cxX - cnX + 1; o[side * 4 + 3] = cxY - cnY + 1;
        }
        return o;
    }
    private static Bitmap Erase(Bitmap src, int rx, int ry, int rw, int rh, bool lid) {
        var bmp = Clone32(src);
        int stride;
        byte[] d = Grab(bmp, out stride);
        int x1c = Math.Min(src.Width - 1, rx + rw), y1c = Math.Min(src.Height - 1, ry + rh);
        int x0 = Math.Max(0, rx), y0 = Math.Max(0, ry);
        var dark = Dark(d, stride, x0, y0, x1c, y1c);
        int body = BodyColor(d, stride, x0, y0, x1c, y1c);
        byte br = (byte)(body >> 16), bg = (byte)((body >> 8) & 255), bb = (byte)(body & 255);
        foreach (var p in dark) {
            int i = p.Y * stride + p.X * 4;
            d[i] = bb; d[i + 1] = bg; d[i + 2] = br; d[i + 3] = 255;
        }
        if (lid && dark.Count > 0) {
            int minX = int.MaxValue, maxX = int.MinValue;
            foreach (var p in dark) { if (p.X < minX) minX = p.X; if (p.X > maxX) maxX = p.X; }
            int midX = (minX + maxX) / 2;
            byte lr = (byte)(br * 3 / 4), lg = (byte)(bg * 3 / 4), lb = (byte)(bb * 3 / 4);
            for (int side = 0; side < 2; side++) {
                int cnX = int.MaxValue, cxX = int.MinValue, cnY = int.MaxValue, cxY = int.MinValue;
                bool any = false;
                foreach (var p in dark) {
                    bool left = p.X <= midX;
                    if ((side == 0) != left) continue;
                    any = true;
                    if (p.X < cnX) cnX = p.X; if (p.X > cxX) cxX = p.X;
                    if (p.Y < cnY) cnY = p.Y; if (p.Y > cxY) cxY = p.Y;
                }
                if (!any) continue;
                int lidH = Math.Max(1, (cxY - cnY + 1) / 5);
                for (int y = cxY - lidH + 1; y <= cxY; y++)
                    for (int x = cnX; x <= cxX; x++) {
                        int i = y * stride + x * 4;
                        d[i] = lb; d[i + 1] = lg; d[i + 2] = lr; d[i + 3] = 255;
                    }
            }
        }
        Put(bmp, d);
        return bmp;
    }
    public static Bitmap MakeBlink(Bitmap src, int rx, int ry, int rw, int rh)  { return Erase(src, rx, ry, rw, rh, true); }
    public static Bitmap MakeNoEyes(Bitmap src, int rx, int ry, int rw, int rh) { return Erase(src, rx, ry, rw, rh, false); }
    // Shadow version: crop the region, body -> dark color, eyes -> the specified eye color
    public static Bitmap Darken(Bitmap src, int rx, int ry, int rw, int rh, int dr, int dg, int db, int er, int eg, int eb) {
        var bmp = new Bitmap(rw, rh, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
            g.DrawImage(src, new Rectangle(0, 0, rw, rh), new Rectangle(rx, ry, rw, rh), GraphicsUnit.Pixel);
        int stride;
        byte[] d = Grab(bmp, out stride);
        for (int y = 0; y < rh; y++) {
            int row = y * stride;
            for (int x = 0; x < rw; x++) {
                int i = row + x * 4;
                if (d[i + 3] < 200) { d[i + 3] = 0; continue; }
                if (d[i + 2] < 70 && d[i + 1] < 70 && d[i] < 70) {
                    d[i] = (byte)eb; d[i + 1] = (byte)eg; d[i + 2] = (byte)er;   // eyes
                } else {
                    d[i] = (byte)db; d[i + 1] = (byte)dg; d[i + 2] = (byte)dr;   // dark body
                }
            }
        }
        Put(bmp, d);
        return bmp;
    }
    public static int CountOpaque(Bitmap bmp) {
        int stride;
        byte[] d = Grab(bmp, out stride);
        int c = 0;
        for (int i = 3; i < d.Length; i += 4) if (d[i] >= 200) c++;
        return c;
    }
    // Find the top of the legs: the first row (from the bottom) at least half the body width
    public static int FindLegTop(Bitmap src, int rx, int ry, int rw, int rh) {
        var bmp = Clone32(src);
        int stride;
        byte[] d = Grab(bmp, out stride);
        bmp.Dispose();
        int x0 = Math.Max(0, rx), x1 = Math.Min(src.Width - 1, rx + rw);
        int yEnd = Math.Min(src.Height - 1, ry + rh);
        int maxC = 0;
        int[] counts = new int[yEnd + 1];
        for (int y = ry; y <= yEnd; y++) {
            int c = 0, row = y * stride;
            for (int x = x0; x <= x1; x++) if (d[row + x * 4 + 3] >= 200) c++;
            counts[y] = c;
            if (c > maxC) maxC = c;
        }
        int th = maxC / 2;
        for (int y = yEnd; y >= ry; y--) if (counts[y] >= th) return y + 1;
        return yEnd;
    }
    // Flatten to 2D: every opaque non-eye pixel becomes one flat body color
    // (removes the shading/ghosting that looks 3D on the GIF frames)
    public static Bitmap MakeFlat(Bitmap src, int rx, int ry, int rw, int rh) {
        var bmp = Clone32(src);
        int stride;
        byte[] d = Grab(bmp, out stride);
        int x1 = Math.Min(src.Width - 1, rx + rw), y1 = Math.Min(src.Height - 1, ry + rh);
        int x0 = Math.Max(0, rx), y0 = Math.Max(0, ry);
        int body = BodyColor(d, stride, x0, y0, x1, y1);
        byte br = (byte)(body >> 16), bg = (byte)((body >> 8) & 255), bb = (byte)(body & 255);
        for (int y = y0; y <= y1; y++) {
            int row = y * stride;
            for (int x = x0; x <= x1; x++) {
                int i = row + x * 4;
                if (d[i + 3] < 200) { d[i + 3] = 0; continue; }
                bool eye = (d[i + 2] < 70 && d[i + 1] < 70 && d[i] < 70);
                if (!eye) { d[i] = bb; d[i + 1] = bg; d[i + 2] = br; d[i + 3] = 255; }
            }
        }
        Put(bmp, d);
        return bmp;
    }
}
"@

# Sky overlay for shooting stars: layered window with per-pixel alpha
# (soft glow & real gradients - impossible with TransparencyKey),
# click-through (WS_EX_TRANSPARENT) and never steals focus.
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class StarOverlay : Form {
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
    [DllImport("user32.dll")] private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pprSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int x, y; public POINT(int a, int b) { x = a; y = b; } }
    [StructLayout(LayoutKind.Sequential)] private struct SIZE { public int cx, cy; public SIZE(int a, int b) { cx = a; cy = b; } }
    [StructLayout(LayoutKind.Sequential)] private struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

    public StarOverlay() {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x8000000;   // LAYERED | TRANSPARENT | TOOLWINDOW | NOACTIVATE
            return cp;
        }
    }
    private Bitmap _pm;     // cached premultiplied bitmap (reused across frames)
    private byte[] _buf;    // cached pixel buffer (reused across frames)
    public void Render(Bitmap src0, int x, int y) {
        int w = src0.Width, h = src0.Height;
        // UpdateLayeredWindow with AC_SRC_ALPHA needs PREMULTIPLIED alpha; a straight-alpha
        // bitmap makes fades fail (stays full color at low alpha). Premultiply into a CACHED
        // temp (reused, no per-frame allocation -> light on CPU/GC).
        if (_pm == null || _pm.Width != w || _pm.Height != h) {
            if (_pm != null) _pm.Dispose();
            _pm = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        }
        Bitmap bmp = _pm;
        Rectangle r = new Rectangle(0, 0, w, h);
        BitmapData sd = src0.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        BitmapData dd = bmp.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        int n = sd.Stride * h;
        if (_buf == null || _buf.Length < n) _buf = new byte[n];
        byte[] buf = _buf;
        Marshal.Copy(sd.Scan0, buf, 0, n);
        for (int i = 0; i < n; i += 4) {
            byte a = buf[i + 3];
            if (a == 0) { buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; }
            else if (a != 255) {
                buf[i]     = (byte)(buf[i]     * a / 255);
                buf[i + 1] = (byte)(buf[i + 1] * a / 255);
                buf[i + 2] = (byte)(buf[i + 2] * a / 255);
            }
        }
        Marshal.Copy(buf, 0, dd.Scan0, n);
        src0.UnlockBits(sd); bmp.UnlockBits(dd);
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = IntPtr.Zero, old = IntPtr.Zero;
        try {
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            old = SelectObject(memDc, hBmp);
            SIZE size = new SIZE(w, h);
            POINT src = new POINT(0, 0);
            POINT dst = new POINT(x, y);
            BLENDFUNCTION blend = new BLENDFUNCTION();
            blend.BlendOp = 0; blend.BlendFlags = 0; blend.SourceConstantAlpha = 255; blend.AlphaFormat = 1;
            UpdateLayeredWindow(this.Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref blend, 2);
        } finally {
            if (old != IntPtr.Zero) { SelectObject(memDc, old); }
            if (hBmp != IntPtr.Zero) { DeleteObject(hBmp); }
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}

// Main pet window: per-pixel alpha layered - size+position+content updated ATOMICALLY
// in one call (no black flicker on resize), WITHOUT click-through:
// automatic per-pixel hit-test (transparent areas pass clicks, the crab body is draggable).
public class PetOverlay : StarOverlay {
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle = cp.ExStyle & ~0x20;   // remove WS_EX_TRANSPARENT
            return cp;
        }
    }
}

// Claude-style right-click menu theme: warm dark background, coral highlight + edge
public class ClawdMenuColors : ProfessionalColorTable {
    static Color BG     = Color.FromArgb(38, 36, 33);
    static Color HILITE = Color.FromArgb(62, 48, 42);
    static Color CORAL  = Color.FromArgb(217, 119, 87);
    static Color MARGIN = Color.FromArgb(31, 29, 27);
    static Color SEP    = Color.FromArgb(70, 64, 58);
    static Color BORDER = Color.FromArgb(92, 72, 63);
    public override Color ToolStripDropDownBackground { get { return BG; } }
    public override Color MenuItemSelected { get { return HILITE; } }
    public override Color MenuItemSelectedGradientBegin { get { return HILITE; } }
    public override Color MenuItemSelectedGradientEnd { get { return HILITE; } }
    public override Color MenuItemBorder { get { return CORAL; } }
    public override Color MenuBorder { get { return BORDER; } }
    public override Color ImageMarginGradientBegin { get { return MARGIN; } }
    public override Color ImageMarginGradientMiddle { get { return MARGIN; } }
    public override Color ImageMarginGradientEnd { get { return MARGIN; } }
    public override Color SeparatorDark { get { return SEP; } }
    public override Color SeparatorLight { get { return SEP; } }
    public override Color MenuItemPressedGradientBegin { get { return BG; } }
    public override Color MenuItemPressedGradientEnd { get { return BG; } }
}

// Explicit renderer: the item highlight is drawn manually (warm fill + left coral bar),
// so it never falls back to the system blue highlight.
public class ClawdMenuRenderer : ToolStripProfessionalRenderer {
    public ClawdMenuRenderer() : base(new ClawdMenuColors()) { this.RoundedEdges = false; }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        Graphics g = e.Graphics;
        Rectangle r = new Rectangle(0, 0, e.Item.Width, e.Item.Height);
        if (e.Item.Selected || e.Item.Pressed) {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(60, 47, 41)))
                g.FillRectangle(b, r);
            using (SolidBrush c = new SolidBrush(Color.FromArgb(217, 119, 87)))
                g.FillRectangle(c, 0, 0, 3, r.Height);
        } else {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(38, 36, 33)))
                g.FillRectangle(b, r);
        }
    }
}
"@

# ---------- Config (clawd.json) ----------
$script:cfg = $null
$cfgPath = Join-Path $PSScriptRoot 'clawd.json'
if (Test-Path $cfgPath) {
    try { $script:cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { $script:cfg = $null }
}
function Get-Cfg([string]$path, $default) {
    $node = $script:cfg
    foreach ($k in $path.Split('.')) {
        if ($null -eq $node) { return $default }
        $prop = $node.PSObject.Properties[$k]
        if ($null -eq $prop) { return $default }
        $node = $prop.Value
    }
    if ($null -eq $node) { return $default }
    return $node
}

$script:cfgSpeed  = [Math]::Max(0.2, [Math]::Min(4.0, [double](Get-Cfg 'walkSpeed' 1.0)))
$script:cfgGrav   = [Math]::Max(0.2, [Math]::Min(3.0, [double](Get-Cfg 'gravity' 1.0)))
$script:idleMinT  = [int]([Math]::Max(2.0, [double](Get-Cfg 'idleSecondsMin' 5)) * 62.5)
$script:idleMaxT  = [int]([Math]::Max(3.0, [double](Get-Cfg 'idleSecondsMax' 10)) * 62.5)
if ($script:idleMaxT -lt ($script:idleMinT + 100)) { $script:idleMaxT = $script:idleMinT + 100 }
$script:blinkMinT = [int]([Math]::Max(1.0, [double](Get-Cfg 'blinkSecondsMin' 2.5)) * 62.5)
$script:blinkMaxT = [int]([Math]::Max(1.5, [double](Get-Cfg 'blinkSecondsMax' 5.5)) * 62.5)
if ($script:blinkMaxT -lt ($script:blinkMinT + 30)) { $script:blinkMaxT = $script:blinkMinT + 30 }
$script:featEyes  = [bool](Get-Cfg 'features.eyeTracking' $true)
$script:featPlat  = [bool](Get-Cfg 'features.windowPlatforms' $true)
$script:featType  = [bool](Get-Cfg 'features.typingReaction' $true)
$script:featLurk  = [bool](Get-Cfg 'features.edgeLurking' $true)
$script:featSys   = [bool](Get-Cfg 'features.systemAwareness' $true)
$script:featClimb = [bool](Get-Cfg 'features.climbing' $true)
$script:featMisch = [bool](Get-Cfg 'features.mischief' $true)
$script:featWatch = [bool](Get-Cfg 'features.claudeWatch' $true)
$script:termCmd   = [string](Get-Cfg 'terminal.command' 'clawd --hello')
$script:termOut   = [string](Get-Cfg 'terminal.output' 'Hello, World!')

# ---------- Official assets ----------
$assetDir = Join-Path $PSScriptRoot 'assets'
$neededAssets = @('Clawd-Still.png', 'Clawd-CrabWalking.gif', 'Clawd-Waving.gif', 'Clawd-JumpingHappy.gif', 'Clawd-Lurking.gif')
$missingAssets = @($neededAssets | Where-Object { -not (Test-Path (Join-Path $assetDir $_)) })
if ($missingAssets.Count -gt 0) {
    # Assets missing -> auto-download from claude.ai
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'download-assets.ps1') | Out-Null
    $missingAssets = @($neededAssets | Where-Object { -not (Test-Path (Join-Path $assetDir $_)) })
    if ($missingAssets.Count -gt 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Clawd's assets are incomplete (download failed):`n$($missingAssets -join "`n")`n`nRun download-assets.ps1 manually, then try again.",
            'Clawd Pet', 'OK', 'Warning')
        exit
    }
}
$script:imgStill = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Still.png'))
$script:imgWave  = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Waving.gif'))
$script:imgJump  = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-JumpingHappy.gif'))
$script:imgLurk  = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Lurking.gif'))
$script:imgDance = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Dancing.gif'))
$script:imgWork  = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Working.gif'))
$script:imgCook  = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Cooking.gif'))

# Standalone GIFs: already cropped to the character (not the 2750x1850 canvas), so they are
# drawn WHOLE - scaled to fit the window and bottom-aligned - instead of via $script:srcRect.
# Played frame-by-frame with ImageAnimator, exactly like Clawd-Waving / Clawd-JumpingHappy.
# $gifSrc holds each GIF's character-content sub-rectangle so the transparent padding around
# him is cropped out and he renders as large as the idle sprite. Bounds were measured from the
# shipped assets; if an asset's canvas size differs (re-exported), fall back to the full frame.
function Get-GifSrc($img, [int]$cw, [int]$ch, [int]$x, [int]$y, [int]$w, [int]$h) {
    if ($img.Width -eq $cw -and $img.Height -eq $ch) { return New-Object System.Drawing.Rectangle($x, $y, $w, $h) }
    return New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)
}
$script:gifStates = @{}; $script:gifSrc = @{}
$script:gifStates['dance'] = $script:imgDance; $script:gifSrc['dance'] = (Get-GifSrc $script:imgDance 267 230 14 18 226 209)
$script:gifStates['work']  = $script:imgWork;  $script:gifSrc['work']  = (Get-GifSrc $script:imgWork  438 230 22 24 372 205)
$script:gifStates['cook']  = $script:imgCook;  $script:gifSrc['cook']  = (Get-GifSrc $script:imgCook  504 368 12 14 446 347)
# Per-GIF size nudge on top of the idle-match scale (1.0 = match idle footprint). Cooking's
# pan reaches out to the side, inflating its bounds, so its crab reads small - bump it to fill
# the window. Clamped to the window afterwards, so it never clips.
$script:gifScale = @{ 'cook' = 1.4 }

# Crab area inside the 2750x1850 canvas: x 736..1935, y 351..1850 (feet at the bottom)
$script:srcRect = New-Object System.Drawing.Rectangle(736, 351, 1200, 1499)

$stillBmp = New-Object System.Drawing.Bitmap($script:imgStill)
$script:imgBlink  = [ClawdFx]::MakeBlink($stillBmp, 736, 1000, 1200, 850)
$script:imgNoEyes = [ClawdFx]::MakeNoEyes($stillBmp, 736, 1000, 1200, 850)
$script:eyeRects  = [ClawdFx]::FindEyes($stillBmp, 736, 1000, 1200, 850)
$stillBmp.Dispose()

if ($TestBlink) {
    $crop = New-Object System.Drawing.Rectangle(900, 1000, 900, 500)
    $cmp = New-Object System.Drawing.Bitmap(900, 1000)
    $g = [System.Drawing.Graphics]::FromImage($cmp)
    $g.DrawImage($script:imgStill, (New-Object System.Drawing.Rectangle(0, 0, 900, 500)), $crop, [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawImage($script:imgBlink, (New-Object System.Drawing.Rectangle(0, 500, 900, 500)), $crop, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $cmp.Save("$env:TEMP\clawd-blink-test.png")
    $cmp.Dispose()
    Write-Output "saved: $env:TEMP\clawd-blink-test.png"
    Write-Output "eyes: $($script:eyeRects -join ',')"
    exit
}

# ---------- Display size ----------
$script:destW  = [Math]::Max(48, [Math]::Min(200, [int](Get-Cfg 'size' 80)))
$script:destH  = [int](1499 / 1200 * $script:destW)   # ~100
$script:margin = 12
$script:formW  = $script:destW + 2 * $script:margin
$script:crabH  = [int](800 * $script:destW / 1200)   # body height ~53 px
# Square window while climbing: must fit the sprite at any rotation.
# Farthest distance from body center = side of head (destH - crabH/2), plus a safe margin.
$script:climbSide = [int](2 * (([int](1499 / 1200 * $script:destW)) - $script:crabH / 2.0 + 10))
$script:scale  = $script:destW / 1200.0

# ---------- Walking legs: exactly the frames of Clawd-CrabWalking.gif ----------
# Body/head STAYS STILL (Still sprite). Only the leg strip is animated, using
# ALL official GIF frames with their original per-frame timing - flattened to 2D.
$stillBmp2 = New-Object System.Drawing.Bitmap($script:imgStill)
$script:legTop = [ClawdFx]::FindLegTop($stillBmp2, 736, 1050, 1200, 799)
$stillBmp2.Dispose()
$script:legDestY = [int][Math]::Round(($script:legTop - 351) * $script:scale)
$legSrcH  = 1850 - $script:legTop
$legDestH = [int][Math]::Ceiling($legSrcH * $script:scale) + 1
$legSrc   = New-Object System.Drawing.Rectangle(736, $script:legTop, 1200, $legSrcH)

$script:legFrames  = @()
$script:legFramesL = @()
$script:legDelays  = @()
$script:legHashes  = @()
$md5 = [System.Security.Cryptography.MD5]::Create()
$walkGif = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-CrabWalking.gif'))
$wd = New-Object System.Drawing.Imaging.FrameDimension($walkGif.FrameDimensionsList[0])
$wn = $walkGif.GetFrameCount($wd)
$delayBytes = $null
try { $delayBytes = $walkGif.GetPropertyItem(20736).Value } catch { }
for ($f = 0; $f -lt $wn; $f++) {
    $null = $walkGif.SelectActiveFrame($wd, $f)
    $full = New-Object System.Drawing.Bitmap($walkGif.Width, $walkGif.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
    $gg = [System.Drawing.Graphics]::FromImage($full)
    $gg.DrawImage($walkGif, 0, 0, $walkGif.Width, $walkGif.Height)
    $gg.Dispose()
    $flat = [ClawdFx]::MakeFlat($full, 736, $script:legTop, 1200, $legSrcH)
    $small = New-Object System.Drawing.Bitmap($script:destW, $legDestH)
    $gs = [System.Drawing.Graphics]::FromImage($small)
    $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $gs.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $gs.DrawImage($flat, (New-Object System.Drawing.Rectangle(0, 0, $script:destW, $legDestH)), $legSrc, [System.Drawing.GraphicsUnit]::Pixel)
    $gs.Dispose()
    $mir = New-Object System.Drawing.Bitmap($small)
    $mir.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
    $script:legFrames  += , $small
    $script:legFramesL += , $mir
    $ms = New-Object System.IO.MemoryStream
    $small.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $script:legHashes += [System.BitConverter]::ToString($md5.ComputeHash($ms.ToArray()))
    $ms.Dispose()
    $d = 6
    if ($delayBytes -and $delayBytes.Length -ge ($f * 4 + 4)) {
        $cs = [System.BitConverter]::ToInt32($delayBytes, $f * 4)
        if ($cs -gt 0) { $d = [Math]::Max(3, [int][Math]::Round($cs * 10.0 / 16.0)) }
    }
    $script:legDelays += $d
    $flat.Dispose(); $full.Dispose()
}
$walkGif.Dispose()
$md5.Dispose()
# Walk loop = only the frames whose legs DIFFER from the standing pose (frame 0),
# so there is no "still" pause in the middle of the stepping cycle
$script:legLoop = @()
for ($f = 1; $f -lt $wn; $f++) {
    if ($script:legHashes[$f] -ne $script:legHashes[0]) { $script:legLoop += $f }
}
if ($script:legLoop.Count -eq 0) { $script:legLoop = @(0..($wn - 1)) }
$script:legFrame = 0
$script:legPos   = 0
$script:legWait  = 6

# Geometry while dangling from the cursor: pivot = tip of the right claw (src ~1930,1390)
$script:armLX  = [single]((1930 - 736) * $script:scale)   # ~79.6 (local, no margin)
$script:armLY  = [single]((1390 - 351) * $script:scale)   # ~69.3
$script:dragW  = [int](2.5 * $script:destW)   # square dangle window, scales with size
$script:dragH  = $script:dragW
$script:anchorX = [int]($script:dragW / 2)   # pivot (claw tip) at the center of the dangle window
$script:anchorY = [int]($script:dragH / 2)

# ---------- Window ----------
# Per-pixel alpha layered window: drawn via Update-PetVisual (not the Paint event)
$script:form = New-Object PetOverlay
$script:form.ClientSize = New-Object System.Drawing.Size($script:formW, $script:destH)
$script:petBmp = $null
$script:petG   = $null

function Update-PetVisual {
    $cs = $script:form.ClientSize
    if ($null -eq $script:petBmp -or $script:petBmp.Width -ne $cs.Width -or $script:petBmp.Height -ne $cs.Height) {
        if ($null -ne $script:petG)   { $script:petG.Dispose() }
        if ($null -ne $script:petBmp) { $script:petBmp.Dispose() }
        $script:petBmp = New-Object System.Drawing.Bitmap($cs.Width, $cs.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
        $script:petG = [System.Drawing.Graphics]::FromImage($script:petBmp)
    }
    $script:petG.ResetTransform()
    $script:petG.Clear([System.Drawing.Color]::Transparent)
    Render-Pet $script:petG
    $script:petG.ResetTransform()
    $script:form.Render($script:petBmp, $script:form.Left, $script:form.Top)
}

# Separate small window for the balloon during the descend phase
$script:balForm = New-Object System.Windows.Forms.Form
$script:balForm.FormBorderStyle = 'None'
$script:balForm.StartPosition   = 'Manual'
$script:balForm.TopMost         = $true
$script:balForm.ShowInTaskbar   = $false
$script:balForm.BackColor       = [System.Drawing.Color]::Magenta
$script:balForm.TransparencyKey = $script:balForm.BackColor
$script:balForm.ClientSize      = New-Object System.Drawing.Size(70, 110)
$script:balForm.Visible         = $false
$script:balForm.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($script:balForm, $true, $null)
$script:balForm.Add_Paint({
    $g2 = $_.Graphics
    $bs = $script:destW / 80.0
    Draw-Balloon $g2 35 4 $bs
    $knot = [single](4 + 44 * $bs + 2)
    $sw = [single](3 * [Math]::Sin($script:globalT * 0.08))
    $g2.DrawLine($script:stringPen, 35, $knot, (35 + $sw), ($knot + [single](30 * $bs)))
})

# The Shadow window: appears only during the rare encounter
$script:shForm = New-Object System.Windows.Forms.Form
$script:shForm.FormBorderStyle = 'None'
$script:shForm.StartPosition   = 'Manual'
$script:shForm.TopMost         = $true
$script:shForm.ShowInTaskbar   = $false
$script:shForm.BackColor       = [System.Drawing.Color]::Magenta
$script:shForm.TransparencyKey = $script:shForm.BackColor
$script:shForm.Opacity         = 0.9
$script:shForm.Visible         = $false
$script:shForm.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($script:shForm, $true, $null)
$script:shForm.Add_Paint({
    if ($script:shFrames.Count -eq 0) { return }
    $g3 = $_.Graphics
    $g3.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g3.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $w3 = $script:shDW; $h3 = $script:shDH
    if ($script:shDir -lt 0) {
        $g3.TranslateTransform([single]($w3 + 32), 0)
        $g3.ScaleTransform(-1, 1)
    }
    # During the staring phase: very subtle up-down breathing ALONG the screen edge
    # (not a tilt - tilting makes the body look detached from the edge)
    $yOff = 0
    if ($script:shT -ge 110 -and $script:shT -lt 420) {
        $yOff = [int][Math]::Round(1.5 * [Math]::Sin(($script:shT - 110) * 0.035))
    }
    $g3.DrawImage($script:shFrames[$script:shIdx], (New-Object System.Drawing.Rectangle(16, (8 + $yOff), $w3, $h3)))
})

# Sky overlay (shooting stars) - created once, shown only during the show
$script:starOv = New-Object StarOverlay

# "Claude is ..." status bubble overlay - click-through, floats above the head
$script:statusOv     = New-Object StarOverlay
$script:statusBmp    = $null   # composite per-frame bitmap (for fade)
$script:statusG      = $null
$script:statusBub    = $null   # bubble content bitmap (cached per token)
$script:statusBubTok = '~'   # token currently cached in statusBub

$script:wa      = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:bottomY = $script:wa.Bottom - $script:destH
$script:posX    = [double]($script:wa.Left + ($script:wa.Width - $script:formW) / 2)
$script:form.Location = New-Object System.Drawing.Point([int]$script:posX, $script:bottomY)

# ---------- State (1 tick = 16 ms, ~60 fps) ----------
$script:rand      = New-Object System.Random
$script:state     = 'idle'   # idle | walk | wave | jump | fall
$script:ticks     = 150
$script:dir       = 1
$script:vy        = [double]0
$script:dragging  = $false
$script:dragOff   = New-Object System.Drawing.Point(0, 0)
$script:dragStart = New-Object System.Drawing.Point(0, 0)
$script:moved     = $false
$script:globalT   = [double]0
$script:fx        = 'none'   # none | hop | wiggle | squash | lookaround | doze
$script:busyUntil = 0        # globalT until which Working/Cooking stays on cooldown (anti-thrash)
$script:lastBusy  = ''       # which busy animation ran last ('work' | 'cook') - to alternate
$script:workAnim  = ''       # the single animation locked in for the current Claude-working session
$script:gifDrawTop = 0       # y of the top of the last standalone GIF drawn (for bubble placement)
$script:fxTicks   = 0
$script:fxTotal   = 1
$script:blinkTicks= 0
$script:blinkCd   = 200
$script:hoverCd   = 0
$script:topCnt    = 0
$script:eyeOX     = [double]0
$script:eyeOY     = [double]0
$script:cursorNear= $false
$script:qmTicks   = 0
$script:qmCd      = 0
$script:theta     = [double]0   # pendulum angle while dangling (radians, 0 = hanging straight)
$script:omega     = [double]0   # angular velocity
$script:lastCpX   = 0
$script:lastCpY   = 0
$script:lastVelX  = [double]0
$script:lastVelY  = [double]0
$script:fallVX    = [double]0   # horizontal velocity when thrown
$script:posY      = [double]0
$script:ancX      = [double]0   # anchor (claw) position CHASING the cursor with easing
$script:ancY      = [double]0
$script:ancVX     = [double]0   # eased anchor velocity (for the swing)
$script:ancVY     = [double]0
$script:lastAncVX = [double]0
$script:cvX       = [double]0   # cursor velocity (EMA) - used for throw strength
$script:cvY       = [double]0
$script:walkTotal = 1   # walk duration for ease-in/ease-out
$script:platforms   = @()   # app windows used as platforms: (hwnd,L,T,R,B) per window
$script:platRefresh = 0
$script:onPlat      = $false   # currently standing on an app window?
$script:platHwnd    = [long]0
$script:supportY    = [double]0   # form.Top position when standing on the active platform
$script:lurkDir     = 1   # 1 = peeks from the left edge, -1 = from the right
$script:balMode   = 'none'   # none | descend | float | pop
$script:balX      = [double]0   # balloon position (descend phase)
$script:balY      = [double]0
$script:balVY     = [double]0   # rising speed while floating
$script:balT      = 0   # age of the floating phase
$script:balPopT   = 0   # explosion progress
$script:balDriftX = [double]0
$script:balLastDX = [double]0
$script:balWind   = [double]0   # subtle random wind (descend phase)
$script:balPosY   = [double]0   # precise sub-pixel Y position while floating
$script:balEscape = $false      # a let-go balloon drifting up & away on its own
$script:balEscX   = [double]0
$script:balEscY   = [double]0
$script:balEscVY  = [double]0
$script:balEscWind= [double]0
$script:starActive = $false   # shooting-star show in progress
$script:starT      = 0   # show timeline (ticks)
$script:meteors    = New-Object System.Collections.ArrayList
$script:sparks     = New-Object System.Collections.ArrayList
$script:twinkles   = @()
$script:starBmp    = $null
$script:starG      = $null
$script:starL      = 0   # sky canvas position & size
$script:starTop    = 0
$script:starWd     = 0
$script:starHt     = 0
# The Shadow: a dark Clawd that very rarely peeks from the screen edge
$script:shMode   = 'none'   # none | show
$script:shT      = 0   # encounter timeline
$script:shIdx    = 0   # dark lurking frame currently shown
$script:shDir    = 1   # 1 = left edge, -1 = right edge
$script:shFrames = @()   # darkened lurking frames (built on first call)
$script:shPeak   = 0   # the most "out" frame
$script:shScale  = 0.14 * ($script:destW / 80.0)
$script:shDW     = [int](330 * $script:shScale * 1.5)   # 1.5x the good Clawd: more intimidating
$script:shDH     = [int](401 * $script:shScale * 1.5)
# Climbing the screen wall
$script:climbPhase  = 'none'   # none | in | up | pause | down | out
$script:climbWall   = 1   # 1 = left wall, -1 = right
$script:climbRot    = [double]0   # current body rotation (degrees)
$script:climbX      = [double]0   # X position of the climb window
$script:climbY      = [double]0   # body center (screen Y)
$script:climbTarget = [double]0   # target height
$script:climbT      = 0
$script:wantClimb   = $false   # triggered from the menu: climb once the wall is reached
# Mischief: tugging the window he stands on
$script:shoveDir    = 1
# Mischief: shoving a window from the side (while on the floor)
$script:pushHwnd    = [long]0
$script:pushSide    = 1   # shove direction: 1 = right, -1 = left
$script:pushPhase   = 'none'   # none | approach | tug
$script:pushT       = 0
$script:pushTugs    = 0
# Work mode (system awareness): normal | busy (high CPU) | sleepy (user idle long)
$script:sysMode    = 'normal'
$script:cpuEMA     = [double]0
$script:sysCheck   = 0
$script:cpuCounter = $null
if ($script:featSys) {
    try {
        $script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
        [void]$script:cpuCounter.NextValue()   # the first sample is always 0
    } catch { $script:cpuCounter = $null }
}

# Balloon (rare animation)
$script:balBrush   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(217, 119, 87))
$script:balHiBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(242, 167, 135))
$script:balKnotBr  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(175, 88, 60))
$script:stringPen  = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(210, 195, 175))

# Claude-themed terminal: warm dark background, coral accent, cream text
$script:termBrush       = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 38, 35))
$script:termPen         = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(217, 119, 87))
$script:termTextBrush   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 238, 229))
$script:termCoralBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(217, 119, 87))
$script:termDimBrush    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, 217, 119, 87))
$script:codeFont        = New-Object System.Drawing.Font('Consolas', 7)
$script:eyeBrush    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(18, 14, 12))
$script:whiteBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(250, 248, 244))
$script:bubbleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(246, 238, 226))
$script:glyphBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 52, 44))
$script:sweatBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 140, 190, 235))

# ---------- "Claude Watch": status bubble above the head ----------
# A Claude Code hook writes a single activity token to this file; Clawd reads it and
# shows a bubble: "running a command...", "writing code...", etc.
$script:watchFile  = Join-Path $env:TEMP 'clawd-status.txt'
$script:watchTok   = ''   # current activity token
$script:watchVis   = [double]0   # 0..1 for bubble fade-in/out
$script:watchCheck = 0   # throttle for file reads
$script:watchAge   = 999.0   # age (seconds) of the last write
$script:statusTail = 7   # height of the bubble triangle tail
$script:statusFont = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Regular)
$script:watchText  = @{
    'think'  = 'thinking...'
    'bash'   = 'running a command...'
    'edit'   = 'writing code...'
    'read'   = 'reading files...'
    'web'    = 'browsing the web...'
    'task'   = 'spinning up an agent...'
    'notify' = 'needs your input...'
    'done'   = 'all done'
}
# Playful "done" verbs (like Claude Code) - a random one + timestamp is picked each finish
$script:doneVerbs = @('cooked', 'brewed', 'baked', 'steeped', 'simmered', 'served', 'plated',
                      'shipped', 'wrapped up', 'sealed', 'polished', 'buttoned up', 'nailed it')
$script:doneMsg   = 'all done'   # current finish message (regenerated on each transition to done)

# Pixel patterns for the bubble: question mark, Z (sleep), note (dancing)
function Convert-Pattern([string[]]$rows) {
    $cells = @()
    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt $rows[$r].Length; $c++) {
            if ($rows[$r][$c] -eq '#') { $cells += , @($c, $r) }
        }
    }
    return $cells
}
$script:glyphs = @{
    'qm'   = Convert-Pattern @('.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..')
    'zz'   = Convert-Pattern @('#####', '....#', '...#.', '..#..', '.#...', '#....', '#####')
    'note' = Convert-Pattern @('...#.', '...##', '...#.', '...#.', '..##.', '.###.', '..#..')
    'ex'   = Convert-Pattern @('..#..', '..#..', '..#..', '..#..', '..#..', '.....', '..#..')
}

function Get-CurrentImage {
    switch ($script:state) {
        'wave' { return $script:imgWave }
        'jump' { return $script:imgJump }
        default {
            if ($script:blinkTicks -gt 0) { return $script:imgBlink }
            return $script:imgNoEyes
        }
    }
}

function Set-State([string]$s, [int]$durTicks) {
    foreach ($img in @($script:imgWave, $script:imgJump, $script:imgLurk, $script:imgDance, $script:imgWork, $script:imgCook)) { [ClawdAnim]::Stop($img) }
    $script:state = $s
    $script:ticks = $durTicks
    if ($s -eq 'wave')  { [ClawdAnim]::Start($script:imgWave) }
    if ($s -eq 'jump')  { [ClawdAnim]::Start($script:imgJump) }
    if ($s -eq 'lurk')  { [ClawdAnim]::Start($script:imgLurk) }
    if ($s -eq 'dance') { [ClawdAnim]::Start($script:imgDance) }
    if ($s -eq 'work')  { [ClawdAnim]::Start($script:imgWork) }
    if ($s -eq 'cook')  { [ClawdAnim]::Start($script:imgCook) }
    Update-PetVisual
}

function Start-Fx([string]$f, [int]$total) {
    $script:fx = $f
    $script:fxTotal = [Math]::Max(1, $total)
    $script:fxTicks = $total
}

# True while Claude Code is actively working (a fresh, non-"done" Claude Watch token).
function Test-ClaudeWorking {
    return ($script:featWatch -and $script:watchTok -and $script:watchTok -ne 'done' -and $script:watchAge -lt 15.0)
}

# Switch to the next busy animation, alternating Working <-> Cooking so it stays lively.
# Used for the rare ambient appearance while Claude is idle.
function Start-BusyNext {
    $next = if ($script:lastBusy -eq 'work') { 'cook' } else { 'work' }
    $script:lastBusy = $next
    Set-State $next $script:rand.Next(320, 460)
}

# Keep Clawd in ONE animation (Working or Cooking) for the whole Claude-working session: the
# choice is picked once (alternating across sessions) and held until Claude is done. Calling this
# again while already in that animation just extends it, so the GIF loops without restarting.
function Start-WorkSession {
    if ($script:workAnim -eq '') {
        $script:workAnim = if ($script:lastBusy -eq 'work') { 'cook' } else { 'work' }
        $script:lastBusy = $script:workAnim
    }
    if ($script:state -eq $script:workAnim) {
        $script:ticks = $script:rand.Next(320, 460)   # already in it - keep going, no restart
    } else {
        Set-State $script:workAnim $script:rand.Next(320, 460)
    }
}

function Draw-Balloon($g, [single]$cx, [single]$top, [double]$s) {
    $w = [single](36 * $s); $h = [single](44 * $s)
    $g.FillEllipse($script:balBrush, ($cx - $w / 2), $top, $w, $h)
    $g.FillEllipse($script:balHiBrush, ($cx - $w * 0.28), ($top + $h * 0.12), ($w * 0.22), ($h * 0.26))
    $g.FillRectangle($script:balKnotBr, ($cx - 2), ($top + $h - 1), 4, 4)
}

function Start-Balloon {
    if ($script:balMode -ne 'none' -or $script:balEscape) { return }
    $bs = $script:destW / 80.0
    $crabCX = $script:form.Left + $script:formW / 2
    $off = 120 + $script:rand.Next(0, 160)
    if ($script:rand.NextDouble() -lt 0.5) { $off = -$off }
    $script:balX = [double][Math]::Max(($script:wa.Left + 60), [Math]::Min(($script:wa.Right - 60), ($crabCX + $off)))
    $script:balY = [double]($script:wa.Top - 10)
    $script:balMode = 'descend'
    $script:balT = 0
    $script:balForm.ClientSize = New-Object System.Drawing.Size(70, [int]((44 + 34) * $bs + 14))
    $script:balForm.Location = New-Object System.Drawing.Point([int]($script:balX - 35), [int]$script:balY)
    $script:balForm.Show()
    $script:balForm.TopMost = $true
    $script:form.TopMost = $true
    Set-State 'walk' 9999
    $script:walkTotal = 9999
}

function Cancel-Balloon {
    $script:balMode = 'none'
    $script:balForm.Hide()
    if ($script:state -eq 'walk' -and $script:ticks -gt 5000) {
        Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
    }
}

# ---------- Climbing the wall ----------
function Start-Climb([int]$wall) {
    $script:climbWall  = $wall
    $script:climbPhase = 'in'
    $script:climbT     = 0
    $script:climbRot   = 0
    $half = $script:climbSide / 2.0
    $cx = $script:form.Left + $script:margin + $script:destW / 2.0
    $cy = $script:form.Top + $script:destH - $script:crabH / 2.0
    $script:climbX = $cx - $half
    $script:climbY = $cy
    $script:climbTarget = $script:wa.Top + $script:wa.Height * (0.22 + $script:rand.NextDouble() * 0.30)
    $script:form.ClientSize = New-Object System.Drawing.Size($script:climbSide, $script:climbSide)
    $script:form.Location = New-Object System.Drawing.Point([int][Math]::Round($script:climbX), [int][Math]::Round($script:climbY - $half))
    Set-State 'climb' 9999
    Update-PetVisual
}

function Stop-Climb([bool]$jumpOff) {
    $half = $script:climbSide / 2.0
    $bodyCX = $script:climbX + $half
    $script:form.ClientSize = New-Object System.Drawing.Size($script:formW, $script:destH)
    $newLeft = [int][Math]::Max($script:wa.Left, [Math]::Min(($script:wa.Right - $script:formW), [Math]::Round($bodyCX - $script:formW / 2.0)))
    $newTop  = [int][Math]::Round($script:climbY - ($script:destH - $script:crabH / 2.0))
    $script:form.Location = New-Object System.Drawing.Point($newLeft, $newTop)
    Update-PetVisual
    $script:posX = [double]$newLeft
    $script:posY = [double]$newTop
    $script:climbPhase = 'none'
    if ($jumpOff) {
        $script:fallVX = -$script:climbWall * (2.5 + $script:rand.NextDouble() * 3.0)
        $script:vy = -1.5
        Set-State 'fall' 9999
    } else {
        $script:form.Top = [int]$script:bottomY
        $script:posY = [double]$script:bottomY
        Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
    }
}

# ---------- Shoving a window from the side ----------
function Find-PushTarget {
    # Find a window that reaches the floor and whose side edge he can approach
    $floorY = $script:bottomY + $script:destH
    $crabCX = $script:form.Left + $script:formW / 2
    $best = $null
    $bestDist = 600
    for ($i = 0; $i -lt $script:platforms.Length; $i += 5) {
        $L = $script:platforms[$i + 1]; $T = $script:platforms[$i + 2]
        $R = $script:platforms[$i + 3]; $B = $script:platforms[$i + 4]
        if ($B -lt ($floorY - 30)) { continue }   # does not reach the floor
        if ($T -gt ($script:bottomY + 10)) { continue }
        if (($R - $L) -lt 200) { continue }
        if (($R + 80) -lt $script:wa.Right) {   # shove from left to right
            $d = [Math]::Abs($L - $crabCX)
            if ($d -lt $bestDist) { $bestDist = $d; $best = @{ h = $script:platforms[$i]; side = 1 } }
        }
        if (($L - 80) -gt $script:wa.Left) {   # shove from right to left
            $d = [Math]::Abs($R - $crabCX)
            if ($d -lt $bestDist) { $bestDist = $d; $best = @{ h = $script:platforms[$i]; side = -1 } }
        }
    }
    return $best
}

function Start-Push($target) {
    $script:pushHwnd  = $target.h
    $script:pushSide  = $target.side
    $script:pushPhase = 'approach'
    $script:pushT     = 0
    $script:pushTugs  = 0
    Set-State 'push' 9999
}

function Stop-Push {
    $script:pushPhase = 'none'
    Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
}

# ---------- The Shadow ----------
function Build-ShadowFrames {
    if ($script:shFrames.Count -gt 0) { return }
    $gif = [System.Drawing.Image]::FromFile((Join-Path $assetDir 'Clawd-Lurking.gif'))
    $fd = New-Object System.Drawing.Imaging.FrameDimension($gif.FrameDimensionsList[0])
    $n = $gif.GetFrameCount($fd)
    $maxC = -1
    for ($f = 0; $f -lt $n; $f++) {
        $null = $gif.SelectActiveFrame($fd, $f)
        $full = New-Object System.Drawing.Bitmap($gif.Width, $gif.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
        $gg = [System.Drawing.Graphics]::FromImage($full)
        $gg.DrawImage($gif, 0, 0, $gif.Width, $gif.Height)
        $gg.Dispose()
        $dark = [ClawdFx]::Darken($full, 0, 399, 330, 401, 10, 9, 12, 205, 28, 36)   # pitch-black body, red eyes
        $full.Dispose()
        $script:shFrames += , $dark
        $c = [ClawdFx]::CountOpaque($dark)
        if ($c -gt $maxC) { $maxC = $c; $script:shPeak = $f }
    }
    $gif.Dispose()
}

function Start-Shadow {
    if ($script:shMode -ne 'none' -or $script:starActive -or $script:balMode -ne 'none' -or $script:dragging) { return }
    Build-ShadowFrames
    if ($script:shFrames.Count -eq 0) { return }
    # Appear on the edge farther from Clawd
    $crabCX = $script:form.Left + $script:formW / 2
    $script:shDir = 1
    if ($crabCX -lt ($script:wa.Left + $script:wa.Width / 2)) { $script:shDir = -1 }
    $script:shForm.ClientSize = New-Object System.Drawing.Size(($script:shDW + 32), ($script:shDH + 12))
    $left = $script:wa.Left - 16
    if ($script:shDir -lt 0) { $left = $script:wa.Right - $script:shDW - 16 }
    $script:shForm.Location = New-Object System.Drawing.Point([int]$left, [int](($script:bottomY + $script:destH) - $script:shDH - 8))
    $script:shForm.Opacity = 0
    $script:shIdx = 0
    $script:shT = 0
    $script:shMode = 'show'
    $script:shForm.Show()
    $script:shForm.TopMost = $true
    $script:form.TopMost = $true
    if ($script:state -eq 'walk' -or $script:state -eq 'idle') { Set-State 'idle' 9999 }
}

function Stop-Shadow {
    $script:shMode = 'none'
    $script:shForm.Hide()
    if ($script:state -eq 'idle' -and $script:ticks -gt 5000) {
        Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
    }
}

# ---------- Shooting stars ----------
function Start-StarShow {
    if ($script:starActive -or $script:balMode -ne 'none' -or $script:dragging) { return }
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $script:starL   = $bounds.Left
    $script:starTop = $bounds.Top
    $script:starWd  = $bounds.Width
    $script:starHt  = [int]($bounds.Height * 0.55)
    $script:starBmp = New-Object System.Drawing.Bitmap($script:starWd, $script:starHt, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
    $script:starG   = [System.Drawing.Graphics]::FromImage($script:starBmp)
    $script:starG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $script:meteors.Clear()
    $script:sparks.Clear()
    # Small twinkling stars in the sky (ambience)
    $script:twinkles = @()
    for ($i = 0; $i -lt 16; $i++) {
        $script:twinkles += , @{
            x = $script:rand.Next(30, $script:starWd - 30)
            y = $script:rand.Next(10, [int]($script:starHt * 0.8))
            ph = $script:rand.NextDouble() * 6.28
            sz = 1 + $script:rand.Next(0, 2)
        }
    }
    $script:starT = 0
    $script:starActive = $true
    $script:starOv.Show()
    $script:starOv.TopMost = $true
    $script:form.TopMost = $true
    Set-State 'stargaze' 9999
}

function Cancel-StarShow {
    $script:starActive = $false
    $script:starOv.Hide()
    if ($null -ne $script:starG)   { $script:starG.Dispose();   $script:starG = $null }
    if ($null -ne $script:starBmp) { $script:starBmp.Dispose(); $script:starBmp = $null }
    $script:meteors.Clear()
    $script:sparks.Clear()
}

# Spawn a single meteor (golden star head + fiery tail)
function Spawn-Meteor([double]$size) {
    $fromLeft = ($script:rand.NextDouble() -lt 0.5)
    $speed = 5.5 + $script:rand.NextDouble() * 3.0
    $angle = (18 + $script:rand.Next(0, 16)) * [Math]::PI / 180.0
    $vx = $speed * [Math]::Cos($angle)
    $vy = $speed * [Math]::Sin($angle)
    if ($fromLeft) {
        $x = [double]$script:rand.Next(0, [int]($script:starWd * 0.35))
    } else {
        $x = [double]$script:rand.Next([int]($script:starWd * 0.65), $script:starWd)
        $vx = -$vx
    }
    $null = $script:meteors.Add(@{ x = $x; y = [double]$script:rand.Next(0, 60); vx = $vx; vy = $vy; sz = $size })
}

function Update-StarShow {
    $script:starT++
    $t = $script:starT

    # Meteor schedule: one big, then a few small ones following
    if ($t -eq 12)  { Spawn-Meteor 5.0 }
    if ($t -eq 150) { Spawn-Meteor 3.0 }
    if ($t -eq 225) { Spawn-Meteor 2.4 }
    if ($t -eq 320) { Spawn-Meteor 4.0 }

    # Wish moment: eyes closed for a while, golden sparkle around the head (drawn on the pet form)
    if ($t -eq 415) { $script:blinkTicks = 60 }

    # Meteor physics + sparks
    for ($i = $script:meteors.Count - 1; $i -ge 0; $i--) {
        $m = $script:meteors[$i]
        $m.x += $m.vx; $m.y += $m.vy
        if (($script:starT % 2) -eq 0) {
            $null = $script:sparks.Add(@{
                x = $m.x + ($script:rand.NextDouble() - 0.5) * 6
                y = $m.y + ($script:rand.NextDouble() - 0.5) * 6
                vx = -$m.vx * 0.06 + ($script:rand.NextDouble() - 0.5) * 0.7
                vy = -$m.vy * 0.06 + ($script:rand.NextDouble() - 0.5) * 0.7
                life = 38; max = 38
                cyan = ($script:rand.NextDouble() -lt 0.35)
            })
        }
        if ($m.x -lt -80 -or $m.x -gt ($script:starWd + 80) -or $m.y -gt ($script:starHt + 40)) {
            $script:meteors.RemoveAt($i)
        }
    }
    for ($i = $script:sparks.Count - 1; $i -ge 0; $i--) {
        $p = $script:sparks[$i]
        $p.x += $p.vx; $p.y += $p.vy
        $p.vy += 0.025
        $p.life--
        if ($p.life -le 0) { $script:sparks.RemoveAt($i) }
    }

    # ===== Render the sky (per-pixel alpha) =====
    $g = $script:starG
    $g.Clear([System.Drawing.Color]::Transparent)

    # Twinkling ambience stars
    foreach ($tw in $script:twinkles) {
        $a = [int](55 + 55 * [Math]::Sin($script:globalT * 0.06 + $tw.ph))
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, 255, 246, 222))
        $g.FillEllipse($br, [single]$tw.x, [single]$tw.y, [single]$tw.sz, [single]$tw.sz)
        $br.Dispose()
    }

    # Meteor: spinning golden STAR head + a winding orange -> cyan -> blue fiery tail
    foreach ($m in $script:meteors) {
        $spd = [Math]::Sqrt($m.vx * $m.vx + $m.vy * $m.vy)
        $nx = $m.vx / $spd; $ny = $m.vy / $spd   # direction of motion
        $perpX = -$ny; $perpY = $nx   # perpendicular (for the curve & side ribbons)

        # Main tail: color runs yellow -> orange -> cyan -> blue, straight along the direction
        $segs = 24
        for ($s = $segs; $s -ge 1; $s--) {
            $f = $s / [double]$segs
            $px = $m.x - $m.vx * $s * 2.0
            $py = $m.y - $m.vy * $s * 2.0
            $a = [int](165 * [Math]::Pow(1 - $f, 1.4))
            if ($a -le 4) { continue }
            if ($f -lt 0.25) {
                $u = $f / 0.25
                $cr = [int](255); $cg = [int](250 - 80 * $u); $cb = [int](200 - 140 * $u)
            } elseif ($f -lt 0.55) {
                $u = ($f - 0.25) / 0.30
                $cr = [int](255 - 165 * $u); $cg = [int](170 + 30 * $u); $cb = [int](60 + 195 * $u)
            } else {
                $u = ($f - 0.55) / 0.45
                $cr = [int](90 - 30 * $u); $cg = [int](200 - 90 * $u); $cb = [int](255 - 35 * $u)
            }
            $r = [Math]::Max(0.7, $m.sz * (1 - $f * 0.72))
            $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $cr, $cg, $cb))
            $g.FillEllipse($br, [single]($px - $r), [single]($py - $r), [single]($r * 2), [single]($r * 2))
            $br.Dispose()
        }
        # Two thin ribbons on the tail sides (cyan & blue) like the pixel-art reference
        foreach ($band in @(@(1, 110, 80, 200, 255), @(-1, 80, 60, 100, 230))) {
            for ($s = $segs; $s -ge 3; $s -= 2) {
                $f = $s / [double]$segs
                $off = $band[0] * (1.6 + $f * 4.5)
                $px = $m.x - $m.vx * $s * 2.0 + $perpX * $off
                $py = $m.y - $m.vy * $s * 2.0 + $perpY * $off
                $a = [int]($band[1] * [Math]::Pow(1 - $f, 1.3))
                if ($a -le 4) { continue }
                $r = [Math]::Max(0.5, $m.sz * 0.45 * (1 - $f * 0.6))
                $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $band[2], $band[3], $band[4]))
                $g.FillEllipse($br, [single]($px - $r), [single]($py - $r), [single]($r * 2), [single]($r * 2))
                $br.Dispose()
            }
        }
        # Warm halo + a small glowing core orb
        $hr = $m.sz * 3.0
        $halo = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(52, 255, 200, 110))
        $g.FillEllipse($halo, [single]($m.x - $hr), [single]($m.y - $hr), [single]($hr * 2), [single]($hr * 2))
        $halo.Dispose()
        $core = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 255, 252, 240))
        $g.FillEllipse($core, [single]($m.x - $m.sz), [single]($m.y - $m.sz), [single]($m.sz * 2), [single]($m.sz * 2))
        $core.Dispose()
    }

    # Small fading sparks (gold & cyan mix like the reference)
    foreach ($p in $script:sparks) {
        $f = $p.life / [double]$p.max
        $a = [int](165 * $f)
        $col = [System.Drawing.Color]::FromArgb($a, 255, 215, 140)
        if ($p.cyan) { $col = [System.Drawing.Color]::FromArgb($a, 130, 215, 255) }
        $br = New-Object System.Drawing.SolidBrush $col
        $sz = [single](1.0 + 1.6 * $f)
        $g.FillEllipse($br, [single]($p.x - $sz / 2), [single]($p.y - $sz / 2), $sz, $sz)
        $br.Dispose()
    }

    $script:starOv.Render($script:starBmp, $script:starL, $script:starTop)

    # Done
    if ($script:starT -ge 560) {
        Cancel-StarShow
        Set-State 'jump' 190   # jump for joy after the wish is made
    }
}

function Draw-Eyes($g, [single]$ox, [single]$oy, [bool]$panic, [bool]$happy = $false) {
    for ($e = 0; $e -lt 2; $e++) {
        $ex = $script:eyeRects[$e * 4]; $ey = $script:eyeRects[$e * 4 + 1]
        $ew = $script:eyeRects[$e * 4 + 2] * $script:scale
        $eh = $script:eyeRects[$e * 4 + 3] * $script:scale
        $bx = [single]($ox + ($ex - 736) * $script:scale)
        $by = [single]($oy + ($ey - 351) * $script:scale)
        if ($panic) {
            # Bulging: white eye base grows, pupil shrinks (no tremble)
            $g.FillRectangle($script:whiteBrush, [single]($bx - 1), [single]($by - 1), [single]($ew + 2), [single]($eh + 2))
            $pw = [single]($ew * 0.55); $ph = [single]($eh * 0.55)
            $g.FillRectangle($script:eyeBrush, [single]($bx + ($ew - $pw) / 2), [single]($by + ($eh - $ph) / 2), $pw, $ph)
        } elseif ($happy) {
            # Happy eyes while dancing: PIXEL pattern (blocks) so it matches the Clawd sprite style -
            # a ^_^ arch from blocks half the eye size (real eye = 100px in the source).
            $rowsH = @('.##.', '#..#')
            $colsH = 4
            $bs    = [single]($ew * 0.5)
            $pwH   = [single]($colsH * $bs); $phH = [single]($rowsH.Count * $bs)
            $ecx   = [single]($bx + $ew / 2.0)
            $ecy2  = [single]($by + $eh / 2.0)
            $px0   = [single]($ecx - $pwH / 2.0); $py0 = [single]($ecy2 - $phH / 2.0)
            $sm = $g.SmoothingMode; $g.SmoothingMode = 'None'
            for ($ry = 0; $ry -lt $rowsH.Count; $ry++) {
                $line = $rowsH[$ry]
                for ($cxi = 0; $cxi -lt $colsH; $cxi++) {
                    if ($line[$cxi] -eq '#') {
                        $g.FillRectangle($script:eyeBrush, [single]($px0 + $cxi * $bs), [single]($py0 + $ry * $bs), $bs, $bs)
                    }
                }
            }
            $g.SmoothingMode = $sm
        } else {
            $g.FillRectangle($script:eyeBrush, [single]($bx + $script:eyeOX * $script:scale), [single]($by + $script:eyeOY * $script:scale), [single]$ew, [single]$eh)
        }
    }
}

# ---------- Drawing (called by Update-PetVisual, renders to an ARGB bitmap) ----------
function Render-Pet($g) {
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

    # ===== DANGLING MODE: claw caught on the cursor, body becomes a pendulum =====
    if ($script:dragging -and $script:moved) {
        $ang = [single](-85 + $script:theta * 180.0 / [Math]::PI)
        $g.TranslateTransform([single]$script:anchorX, [single]$script:anchorY)
        $g.RotateTransform($ang)
        $g.TranslateTransform(-$script:armLX, -$script:armLY)

        $cur = if ($script:blinkTicks -gt 0) { $script:imgBlink } else { $script:imgNoEyes }
        $dest = New-Object System.Drawing.Rectangle(0, 0, $script:destW, $script:destH)
        $g.DrawImage($cur, $dest, $script:srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        if ($script:blinkTicks -le 0) { Draw-Eyes $g 0 0 $false }
        return
    }

    # ===== BALLOON MODE: floating up on a balloon / balloon popping =====
    if ($script:state -eq 'balloon') {
        $bs = $script:destW / 80.0
        $cxw = [single]($script:form.ClientSize.Width / 2.0)
        $knotY = [single](8 + 44 * $bs)
        $pivY  = [single]($knotY + 30 * $bs)
        if ($script:balMode -eq 'float' -or $script:balMode -eq 'lift') {
            Draw-Balloon $g $cxw 8 $bs
            $g.DrawLine($script:stringPen, $cxw, $knotY, $cxw, $pivY)
        } elseif ($script:balMode -eq 'pop') {
            # Explosion: coral particles spread out then fade
            for ($i = 0; $i -lt 8; $i++) {
                $a = $i * [Math]::PI / 4
                $r = 4 + $script:balPopT * 2.4
                $px = $cxw + $r * [Math]::Cos($a)
                $py = (8 + 22 * $bs) + $r * [Math]::Sin($a)
                $sz = [Math]::Max(1.0, 4.5 - $script:balPopT * 0.32)
                $g.FillEllipse($script:termCoralBrush, [single]($px - $sz / 2), [single]($py - $sz / 2), [single]$sz, [single]$sz)
            }
        }
        # Crab hangs at the end of the string; during lift-off it rotates smoothly
        # from the standing pose (0 deg) to the hanging pose (-85 deg)
        if ($script:balMode -eq 'lift') {
            $p = [Math]::Min(1.0, $script:balT / 55.0)
            $e = $p * $p * (3 - 2 * $p)
            $ang = [single](-85.0 * $e)
        } else {
            $ang = [single](-85 + $script:theta * 180.0 / [Math]::PI)
        }
        $g.TranslateTransform($cxw, $pivY)
        $g.RotateTransform($ang)
        $g.TranslateTransform(-$script:armLX, -$script:armLY)
        $cur3 = $script:imgNoEyes
        if ($script:blinkTicks -gt 0) { $cur3 = $script:imgBlink }
        $dest3 = New-Object System.Drawing.Rectangle(0, 0, $script:destW, $script:destH)
        $g.DrawImage($cur3, $dest3, $script:srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        if ($script:blinkTicks -le 0) { Draw-Eyes $g 0 0 $false }
        return
    }

    # ===== CLIMBING MODE: body rotates 90 deg, legs planted on the wall =====
    if ($script:state -eq 'climb') {
        $half = [single]($script:climbSide / 2.0)
        $g.TranslateTransform($half, $half)
        $g.RotateTransform([single]$script:climbRot)
        $g.TranslateTransform([single](-($script:margin + $script:destW / 2.0)), [single](-($script:destH - $script:crabH / 2.0)))
        $cur2 = Get-CurrentImage
        $bsrc = New-Object System.Drawing.Rectangle(736, 351, 1200, ($script:legTop - 351))
        $bdst = New-Object System.Drawing.Rectangle($script:margin, 0, $script:destW, $script:legDestY)
        $g.DrawImage($cur2, $bdst, $bsrc, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawImage($script:legFrames[$script:legFrame], [single]$script:margin, [single]$script:legDestY)
        if ($script:blinkTicks -le 0) { Draw-Eyes $g ([single]$script:margin) ([single]0) $false }
        return
    }

    # ===== LURKING MODE: peeks shyly from the screen edge (official GIF) =====
    if ($script:state -eq 'lurk') {
        [System.Drawing.ImageAnimator]::UpdateFrames($script:imgLurk)
        if ($script:lurkDir -lt 0) {
            $g.TranslateTransform([single]$script:formW, 0)
            $g.ScaleTransform(-1, 1)
        }
        $ldest = New-Object System.Drawing.Rectangle(0, ($script:destH - 40), 33, 40)
        $lsrc  = New-Object System.Drawing.Rectangle(0, 399, 330, 401)
        $g.DrawImage($script:imgLurk, $ldest, $lsrc, [System.Drawing.GraphicsUnit]::Pixel)
        return
    }

    # ===== CODE MODE: hide -> type hello world -> wave (still hidden) -> then wake up =====
    if ($script:state -eq 'code') {
        $elapsed = 380 - $script:ticks
        # Stays submerged through the sequence; only rises in the last 25 ticks
        $t = 1.0
        if ($elapsed -lt 25) { $t = $elapsed / 25.0 }
        elseif ($elapsed -gt 355) { $t = (380 - $elapsed) / 25.0 }
        $ease = $t * $t * (3 - 2 * $t)
        $yy = [int](($script:crabH - 16) * $ease)
        if ($elapsed -ge 205 -and $elapsed -lt 355) {
            # Waving from behind the edge: only the head + hand peek out
            [System.Drawing.ImageAnimator]::UpdateFrames($script:imgWave)
            $dest = New-Object System.Drawing.Rectangle($script:margin, $yy, $script:destW, $script:destH)
            $g.DrawImage($script:imgWave, $dest, $script:srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        } else {
            $cur2 = $script:imgNoEyes
            if ($script:blinkTicks -gt 0) { $cur2 = $script:imgBlink }
            $dest = New-Object System.Drawing.Rectangle($script:margin, $yy, $script:destW, $script:destH)
            $g.DrawImage($cur2, $dest, $script:srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            if ($script:blinkTicks -le 0) { Draw-Eyes $g ([single]$script:margin) ([single]$yy) $false }
        }
        # Claude-themed terminal (shown while he hides & waves)
        if ($elapsed -ge 30 -and $elapsed -lt 355) {
            $g.ResetTransform()
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
            $tw = 96; $th = 38
            $tx = [single](($script:formW - $tw) / 2)
            $ty = [single]2
            $g.FillRectangle($script:termBrush, $tx, $ty, $tw, $th)
            $g.DrawRectangle($script:termPen, $tx, $ty, $tw, $th)
            # Three macOS-style window dots, coral colored
            $g.FillEllipse($script:termCoralBrush, ($tx + 4), ($ty + 4), 4, 4)
            $g.FillEllipse($script:termDimBrush,   ($tx + 11), ($ty + 4), 4, 4)
            $g.FillEllipse($script:termDimBrush,   ($tx + 18), ($ty + 4), 4, 4)
            $l1 = '> ' + $script:termCmd
            $n1 = [Math]::Max(0, [Math]::Min($l1.Length, [int](($elapsed - 35) / 3)))
            if ($n1 -gt 0) {
                $g.DrawString($l1.Substring(0, $n1), $script:codeFont, $script:termTextBrush, ($tx + 3), ($ty + 11))
            }
            if ($elapsed -gt (35 + $l1.Length * 3 + 25)) {
                $l2 = $script:termOut
                if (([int]($script:globalT / 18)) % 2 -eq 0) { $l2 += '_' }
                $g.DrawString($l2, $script:codeFont, $script:termCoralBrush, ($tx + 3), ($ty + 24))
            }
        }
        return
    }

    # ===== STANDALONE GIF STATES: dance / work / cook =====
    # These GIFs are already cropped to the character, so draw the WHOLE frame scaled to fit
    # the window and bottom-aligned (feet on the floor). Frame-by-frame via ImageAnimator -
    # the same smooth playback as Clawd-Waving / Clawd-JumpingHappy.
    if ($script:gifStates.ContainsKey($script:state)) {
        $img = $script:gifStates[$script:state]
        $src = $script:gifSrc[$script:state]
        [System.Drawing.ImageAnimator]::UpdateFrames($img)
        # Size to match the idle crab: scale up until either the width reaches the sprite width
        # (destW) OR the height reaches the idle crab height (crabH) - whichever needs more - so he
        # never looks smaller than idle in either dimension. Clamp to the window to avoid clipping.
        $scale = [Math]::Max($script:destW / [double]$src.Width, $script:crabH / [double]$src.Height)
        if ($script:gifScale.ContainsKey($script:state)) { $scale *= $script:gifScale[$script:state] }
        if (($src.Width * $scale) -gt $script:formW) { $scale = $script:formW / [double]$src.Width }
        if (($src.Height * $scale) -gt $script:destH) { $scale = $script:destH / [double]$src.Height }
        $dw  = [int]($src.Width * $scale)
        $dh  = [int]($src.Height * $scale)
        $dx  = [int](($script:formW - $dw) / 2.0)
        $dy  = [int]($script:destH - $dh)
        $script:gifDrawTop = $dy   # head top, so the Claude Watch bubble can sit just above it
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)), $src, [System.Drawing.GraphicsUnit]::Pixel)
        return
    }

    # ===== NORMAL MODE =====
    $cur = Get-CurrentImage
    if ([System.Drawing.ImageAnimator]::CanAnimate($cur)) {
        [System.Drawing.ImageAnimator]::UpdateFrames($cur)
    }

    $cx = [single]($script:margin + $script:destW / 2.0)
    $bottom = [single]$script:destH
    $baseSprite = ($script:state -ne 'wave' -and $script:state -ne 'jump' -and $script:state -ne 'code')
    $y = 0

    if ($script:qmTicks -gt 0 -and $baseSprite) {
        # Smooth ramp-in so the confused tilt does not jerk at the start
        $ramp = [Math]::Min(1.0, (160 - $script:qmTicks) / 12.0)
        $angle = [single](4.0 * [Math]::Sin($script:globalT * 0.12) * $ramp)
        $g.TranslateTransform($cx, $bottom); $g.RotateTransform($angle); $g.TranslateTransform(-$cx, -$bottom)
    }
    elseif ($script:state -eq 'push' -and $script:pushPhase -eq 'tug') {
        # Shoving a window: lean TOWARD the window + shake -> SHOVE (recoil + squash)
        $c = $script:pushT % 36
        $lean = 0.0
        if ($c -lt 18) {
            $p = $c / 18.0
            $lean = (4.0 + 9.0 * $p * $p) - (1.2 * [Math]::Sin($script:globalT * 1.1) * $p)
        } elseif ($c -lt 26) {
            $p = ($c - 18) / 8.0
            $lean = 13.0 - 8.0 * $p
            $sq = [single](0.05 * (1 - $p))
            $g.TranslateTransform($cx, $bottom); $g.ScaleTransform((1.0 + $sq), (1.0 - $sq)); $g.TranslateTransform(-$cx, -$bottom)
        } else {
            $p = ($c - 26) / 10.0
            $lean = 5.0 - 1.0 * $p
        }
        $lean *= [Math]::Min(1.0, $script:pushT / 12.0)   # smooth ramp-in at the start
        $angle = [single]($lean * $script:pushSide)
        $g.TranslateTransform($cx, $bottom); $g.RotateTransform($angle); $g.TranslateTransform(-$cx, -$bottom)
    }
    elseif ($script:state -eq 'idle' -and $script:fx -eq 'none') {
        $s = [single](1.0 + 0.015 * [Math]::Sin($script:globalT * 0.05))
        $g.TranslateTransform($cx, $bottom); $g.ScaleTransform(1.0, $s); $g.TranslateTransform(-$cx, -$bottom)
    }

    switch ($script:fx) {
        'squash' {
            $g.TranslateTransform($cx, $bottom); $g.ScaleTransform(1.18, 0.78); $g.TranslateTransform(-$cx, -$bottom)
        }
        'hop' {
            $p = ($script:fxTotal - $script:fxTicks) / [double]$script:fxTotal
            $y -= [int](9 * [Math]::Sin([Math]::PI * $p))
        }
        'wiggle' {
            $wp = ($script:fxTotal - $script:fxTicks) * 0.9
            $damp = $script:fxTicks / [double]$script:fxTotal
            $angle = 10.0 * [Math]::Sin($wp) * $damp
            $g.TranslateTransform($cx, $bottom); $g.RotateTransform($angle); $g.TranslateTransform(-$cx, -$bottom)
        }
        'lookaround' {
            $angle = 2.0 * [Math]::Sin(($script:fxTotal - $script:fxTicks) * 0.06)
            $g.TranslateTransform($cx, $bottom); $g.RotateTransform($angle); $g.TranslateTransform(-$cx, -$bottom)
        }
        'doze' {
            # Sleeping: deep and slow breathing
            $s = [single](1.0 + 0.03 * [Math]::Sin($script:globalT * 0.03))
            $g.TranslateTransform($cx, $bottom); $g.ScaleTransform(1.0, $s); $g.TranslateTransform(-$cx, -$bottom)
        }
        'duck' {
            # Hiding behind the edge: sink smoothly until only the head + eyes remain
            $elapsed = $script:fxTotal - $script:fxTicks
            $f1 = [Math]::Min(1.0, $elapsed / 25.0)
            $f2 = [Math]::Min(1.0, $script:fxTicks / 25.0)
            $t = [Math]::Min($f1, $f2)
            $ease = $t * $t * (3 - 2 * $t)
            $y += [int](($script:crabH - 16) * $ease)
        }
        'shove' {
            # Tugging the window rhythmically: wind-up (lean + shake) -> YANK (recoil + squash)
            $els = $script:fxTotal - $script:fxTicks
            $c = $els % 36
            $lean = 0.0
            if ($c -lt 18) {
                # Wind-up: leaning more, shaking under the load
                $p = $c / 18.0
                $lean = -(4.0 + 10.0 * $p * $p) + (1.3 * [Math]::Sin($script:globalT * 1.1) * $p)
            } elseif ($c -lt 26) {
                # Yank: quick recoil + body squashes from the effort
                $p = ($c - 18) / 8.0
                $lean = -14.0 + 9.0 * $p
                $sq = [single](0.05 * (1 - $p))
                $g.TranslateTransform($cx, $bottom); $g.ScaleTransform((1.0 + $sq), (1.0 - $sq)); $g.TranslateTransform(-$cx, -$bottom)
            } else {
                # Catch a breath before the next pull
                $p = ($c - 26) / 10.0
                $lean = -5.0 + 1.0 * $p
            }
            $lean *= [Math]::Min(1.0, $els / 12.0)   # smooth ramp-in at the start
            $angle = [single](-$lean * $script:shoveDir)
            $g.TranslateTransform($cx, $bottom); $g.RotateTransform($angle); $g.TranslateTransform(-$cx, -$bottom)
        }
    }

    if ((($script:state -eq 'walk' -and -not $script:cursorNear) -or $script:fx -eq 'shove' -or $script:state -eq 'push') -and $script:legFrames.Count -gt 0) {
        # Body/head STAYS STILL from the Still sprite; legs = official GIF frames as-is
        # (also used while dragging a window: legs step when yanking)
        $bsrc = New-Object System.Drawing.Rectangle(736, 351, 1200, ($script:legTop - 351))
        $bdst = New-Object System.Drawing.Rectangle($script:margin, $y, $script:destW, $script:legDestY)
        $g.DrawImage($cur, $bdst, $bsrc, [System.Drawing.GraphicsUnit]::Pixel)
        $set = if ($script:dir -lt 0) { $script:legFramesL } else { $script:legFrames }
        $g.DrawImage($set[$script:legFrame], [single]$script:margin, [single]($y + $script:legDestY))
        if ($script:blinkTicks -le 0) {
            Draw-Eyes $g ([single]$script:margin) ([single]$y) $false
        }
    } else {
        $dest = New-Object System.Drawing.Rectangle($script:margin, $y, $script:destW, $script:destH)
        $g.DrawImage($cur, $dest, $script:srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        if ($baseSprite -and $script:blinkTicks -le 0) {
            Draw-Eyes $g ([single]$script:margin) ([single]$y) $false
        }
    }

    # Busy mode (high CPU): a sweat drop runs down the side of the head
    if ($script:sysMode -eq 'busy' -and $baseSprite -and -not $script:dragging) {
        $sp = ([int]$script:globalT % 55) / 55.0
        if ($sp -lt 0.75) {
            $sy = [single](($script:destH - $script:crabH) + 2 + $sp * 16)
            $sx = [single]($script:margin + $script:destW - 14)
            $g.FillEllipse($script:sweatBrush, $sx, $sy, 4, 6)
        }
    }

    # Golden "wish" sparkle around the head while eyes are closed under a star
    if ($script:state -eq 'stargaze' -and $script:starT -ge 415 -and $script:starT -lt 490) {
        $g.ResetTransform()
        $hx = [single]($script:margin + $script:destW / 2.0)
        $hy = [single]($script:destH - $script:crabH + 4)
        $offs = @(@(-26, -4), @(24, -8), @(-13, -19), @(17, -22), @(1, -29), @(-31, -22))
        for ($i = 0; $i -lt $offs.Count; $i++) {
            if (((([int]$script:starT + $i * 7) / 9) % 3) -eq 0) { continue }   # alternating twinkle
            $sx = $hx + $offs[$i][0]; $sy = $hy + $offs[$i][1]
            $g.FillRectangle($script:bubbleBrush, [single]($sx - 2), [single]($sy - 0.5), 5, 2)
            $g.FillRectangle($script:bubbleBrush, [single]($sx - 0.5), [single]($sy - 2), 2, 5)
        }
    }

    # Bubble above the head: "!" (startled) / "?" (confused) / "Z" (sleep) / note (dancing)
    $glyph = $null
    if ($script:shMode -eq 'show' -and $script:shT -ge 85 -and $script:shT -lt 170) { $glyph = 'ex' }
    elseif ($script:qmTicks -gt 0) { $glyph = 'qm' }
    elseif ($script:fx -eq 'doze') { $glyph = 'zz' }
    if ($glyph) {
        $g.ResetTransform()
        $bob = [single](1.5 * [Math]::Sin($script:globalT * 0.1))
        $bx = [single]($cx + 14)
        $by = [single]($script:destH - $script:crabH - 26 + $bob)
        $g.FillEllipse($script:bubbleBrush, $bx, $by, 22, 22)
        foreach ($cell in $script:glyphs[$glyph]) {
            $g.FillRectangle($script:glyphBrush, [single]($bx + 6 + $cell[0] * 2), [single]($by + 4 + $cell[1] * 2), 2, 2)
        }
    }
}

# ---------- "Claude Watch" bubble ----------
function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $p.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90)
    $p.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Build the bubble content bitmap for one token (cached; the pulsing dot is drawn separately)
# Tight text format (no trailing padding from MeasureString) so the text is truly centered
$script:statusFmt = [System.Drawing.StringFormat]::GenericTypographic.Clone()
$script:statusFmt.FormatFlags = $script:statusFmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces

function Draw-ClaudeSpark($g, [single]$cx, [single]$cy, [int]$alpha, [single]$scale) {
    # 6-arm spark: all arms equal length with EQUAL 60-degree gaps (3 lines at 30/90/150, so
    # one arm points straight up). Straight pen strokes through the center, six tips on one
    # circle. The throb scales the ARM LENGTH only (pen width stays fixed): at the bottom of
    # the pulse the arms collapse under the round caps, so the spark shrinks to a single dot.
    $col = [System.Drawing.Color]::FromArgb($alpha, 217, 119, 87)
    $pen = New-Object System.Drawing.Pen $col, ([single]1.5)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $st = $g.Save()
    $g.SmoothingMode = 'AntiAlias'
    $g.TranslateTransform($cx, $cy)
    $r = [single](5.0 * $scale)
    foreach ($ang in 30, 90, 150) {   # 3 lines, 60 degrees apart = 6 evenly spaced arms
        $rad = $ang * [Math]::PI / 180.0
        $dx  = [single]($r * [Math]::Cos($rad))
        $dy  = [single]($r * [Math]::Sin($rad))
        $g.DrawLine($pen, (-$dx), (-$dy), $dx, $dy)
    }
    $g.Restore($st)
    $pen.Dispose()
}

function Build-StatusBubble([string]$tok) {
    $done = ($tok -eq 'done')
    $txt = if ($done) { $script:doneMsg } else { $script:watchText[$tok] }
    if (-not $txt) { $txt = $tok }
    $mB = New-Object System.Drawing.Bitmap 1, 1
    $mG = [System.Drawing.Graphics]::FromImage($mB)
    $ts = $mG.MeasureString($txt, $script:statusFont, [int]1000, $script:statusFmt)
    $mG.Dispose(); $mB.Dispose()
    $tw = [int][Math]::Ceiling($ts.Width)
    $th = [int][Math]::Ceiling($ts.Height)
    $padL = 27; $padR = 13; $padV = 5; $rad = 9; $tail = $script:statusTail
    $w = $tw + $padL + $padR
    $h = $th + 2 * $padV
    $bmp = New-Object System.Drawing.Bitmap ([int]$w), ([int]($h + $tail)), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $rr = New-RoundRect 0.5 0.5 ([single]($w - 1)) ([single]($h - 1)) $rad
    $g.FillPath($script:termBrush, $rr)
    $g.DrawPath($script:termPen, $rr)
    $rr.Dispose()
    # Triangle tail at the bottom-center pointing to the head
    $cxq = [single]($w / 2.0)
    $tri = New-Object 'System.Drawing.PointF[]' 3
    $tri[0] = New-Object System.Drawing.PointF (($cxq - 6), ([single]($h - 1)))
    $tri[1] = New-Object System.Drawing.PointF (($cxq + 6), ([single]($h - 1)))
    $tri[2] = New-Object System.Drawing.PointF ($cxq, ([single]($h + $tail - 1)))
    $g.FillPolygon($script:termBrush, $tri)
    $g.DrawLine($script:termPen, $tri[0], $tri[2])
    $g.DrawLine($script:termPen, $tri[1], $tri[2])
    # Close the bottom border segment right at the tail base so it blends in
    $g.FillRectangle($script:termBrush, [single]($cxq - 5.5), [single]($h - 2), 11, 3)
    # Coral checkmark when done
    if ($done) {
        $cp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(217, 119, 87)), 1.9
        $iy = [single]($h / 2.0)
        $g.DrawLines($cp, @(
            (New-Object System.Drawing.PointF 8, $iy),
            (New-Object System.Drawing.PointF 11, ($iy + 3)),
            (New-Object System.Drawing.PointF 16, ($iy - 4))
        ))
        $cp.Dispose()
    }
    $g.DrawString($txt, $script:statusFont, $script:termTextBrush, [single]($padL - 2), [single](($h - $th) / 2.0), $script:statusFmt)
    $g.Dispose()
    return $bmp
}

# Render the bubble to the layered overlay, positioned above the head with alpha = watchVis
function Render-Status {
    if (-not $script:statusOv.Visible) { $script:statusOv.Show(); $script:statusOv.TopMost = $true }
    $tok = $script:watchTok
    if ($script:statusBubTok -ne $tok -or $null -eq $script:statusBub) {
        if ($null -ne $script:statusBub) { $script:statusBub.Dispose() }
        $script:statusBub = Build-StatusBubble $tok
        $script:statusBubTok = $tok
    }
    $bub = $script:statusBub
    $bw = $bub.Width; $bh = $bub.Height
    if ($null -eq $script:statusBmp -or $script:statusBmp.Width -ne $bw -or $script:statusBmp.Height -ne $bh) {
        if ($null -ne $script:statusG)   { $script:statusG.Dispose() }
        if ($null -ne $script:statusBmp) { $script:statusBmp.Dispose() }
        $script:statusBmp = New-Object System.Drawing.Bitmap ([int]$bw), ([int]$bh), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $script:statusG = [System.Drawing.Graphics]::FromImage($script:statusBmp)
        $script:statusG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    }
    $g = $script:statusG
    $g.Clear([System.Drawing.Color]::Transparent)
    $vis = [single][Math]::Max(0.0, [Math]::Min(1.0, $script:watchVis))
    $ia = New-Object System.Drawing.Imaging.ImageAttributes
    $cm = New-Object System.Drawing.Imaging.ColorMatrix
    $cm.Matrix33 = $vis
    $ia.SetColorMatrix($cm)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bw, $bh
    $g.DrawImage($bub, $rect, 0, 0, $bw, $bh, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $ia.Dispose()
    # Spark like the Claude Code loading (the "live" indicator); done already has a checkmark
    if ($tok -ne 'done') {
        # The spark throbs: it RESTS at full size for ~0.5s, then a quick dip down to a single
        # dot and straight back up (a heartbeat-style beat) while the color stays bright. Tweak
        # the three tick counts below to taste (1 second ~= 62 ticks) and the 0.05..1.0 range
        # for how small/big the dot and the full spark get.
        $holdTicks = 8.0   # how long it stays at full size between beats
        $dipTicks  = 8.0    # how fast it shrinks down to a dot (smaller = faster)
        $riseTicks = 8.0    # how fast it grows back up to full
        $period = $holdTicks + $dipTicks + $riseTicks
        $ph = $script:globalT % $period
        if ($ph -lt $holdTicks) {
            $p = 1.0                                                                  # hold at full
        } elseif ($ph -lt ($holdTicks + $dipTicks)) {
            $f = ($ph - $holdTicks) / $dipTicks;            $p = 1.0 - ($f * $f * (3.0 - 2.0 * $f))   # full -> dot (eased)
        } else {
            $f = ($ph - $holdTicks - $dipTicks) / $riseTicks; $p = $f * $f * (3.0 - 2.0 * $f)         # dot -> full (eased)
        }
        $scale = [single](0.05 + 0.95 * $p)
        $a = [int](255 * $vis)
        if ($a -gt 0) {
            $iy = [single](($bh - $script:statusTail) / 2.0)
            Draw-ClaudeSpark $g 14 $iy $a $scale   # cx 14 = leave a gap on the left
        }
    }
    # Position: centered above the head; rises smoothly 6px on fade-in.
    # For the standalone GIFs (work/cook) use the actual drawn top so the bubble never
    # overlaps the head, whatever the GIF's height.
    $cxs = $script:form.Left + $script:formW / 2.0
    $crabTop = $script:destH - $script:crabH
    if ($script:gifStates.ContainsKey($script:state)) { $crabTop = $script:gifDrawTop }
    $headTop = $script:form.Top + $crabTop
    $x = [int]($cxs - $bw / 2.0)
    $y = [int]($headTop - $bh - 1 + (1.0 - $vis) * 6)
    $x = [int][Math]::Max($script:wa.Left, [Math]::Min($x, ($script:wa.Right - $bw)))
    $script:statusOv.Render($script:statusBmp, $x, $y)
}

# ---------- State machine ----------
$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 16
$script:timer.Add_Tick({
    $script:globalT++
    if ($script:hoverCd -gt 0) { $script:hoverCd-- }
    if ($script:qmCd -gt 0) { $script:qmCd-- }
    if ($script:qmTicks -gt 0) { $script:qmTicks-- }

    # A let-go balloon drifting up & away on its own. Runs FIRST, before any early return
    # (e.g. the dragging block returns), so it keeps animating even while you hold the crab.
    if ($script:balEscape) {
        $bs = $script:destW / 80.0
        $script:balEscVY = [Math]::Max(-3.8, $script:balEscVY - 0.05)   # accelerates upward
        $script:balEscWind = ($script:balEscWind + ($script:rand.NextDouble() - 0.5) * 0.16) * 0.97
        $script:balEscX += $script:balEscWind + 0.5 * [Math]::Sin($script:globalT * 0.02)
        $script:balEscY += $script:balEscVY
        $script:balForm.Location = New-Object System.Drawing.Point([int]($script:balEscX - 35), [int]($script:balEscY - 4))
        $script:balForm.Invalidate()
        if (($script:balEscY + 44 * $bs) -lt ($script:wa.Top - 30)) {   # fully off the top -> done
            $script:balForm.Hide()
            $script:balEscape = $false
        }
    }

    # ===== Claude Watch: read the status & show the bubble above the head =====
    # Runs up HERE, before the state-machine early-returns below, so the bubble can never
    # freeze in place when a heavy animation (balloon, meteor, push, climb, fall...) takes
    # over: the moment Clawd leaves a calm pose the bubble hides, and it only returns once
    # he's back in a normal pose.
    if ($script:featWatch) {
        $script:watchCheck++
        if ($script:watchCheck -ge 10) {   # ~6x / second
            $script:watchCheck = 0
            try {
                if ([System.IO.File]::Exists($script:watchFile)) {
                    $script:watchAge = ([DateTime]::Now - [System.IO.File]::GetLastWriteTime($script:watchFile)).TotalSeconds
                    $tk = ([System.IO.File]::ReadAllText($script:watchFile)).Trim().ToLowerInvariant()
                    if ($tk) {
                        if ($tk -eq 'done' -and $script:watchTok -ne 'done') {
                            # Fresh finish: pick a random playful verb + timestamp (like Claude Code)
                            $v = $script:doneVerbs[$script:rand.Next($script:doneVerbs.Count)]
                            $script:doneMsg = "$v at $([DateTime]::Now.ToString('HH:mm'))"
                            # If he dozed off, wake him up so he never sleeps through a finish
                            if ($script:fx -eq 'doze') { $script:fx = 'none'; $script:fxTicks = 0 }
                            # Hop for joy so the finish is noticeable - only from a safe, calm pose
                            if (($script:state -eq 'idle' -or $script:state -eq 'walk') -and $script:fx -eq 'none' -and -not $script:dragging -and $script:balMode -eq 'none' -and -not $script:starActive -and $script:shMode -eq 'none') {
                                Set-State 'jump' 190
                            }
                        }
                        $script:watchTok = $tk
                    }
                } else {
                    $script:watchAge = 999.0
                }
            } catch { }
        }
        # Keep the bubble up through the small everyday animations: idle (incl. walk and brief
        # fx like hop / look-around), wave, hide (duck), and jump. Still hidden during the big
        # "performances" (dance, sleep) and the special modes (dragging, balloon, meteor shower,
        # shadow); heavier states (fall/climb/push/code/...) fall out by not being whitelisted.
        $gentleIdle = ((($script:state -eq 'idle') -or ($script:state -eq 'walk')) -and ($script:fx -ne 'doze'))
        $calmPose = (($gentleIdle -or ($script:state -eq 'wave') -or ($script:state -eq 'jump') -or ($script:state -eq 'work') -or ($script:state -eq 'cook')) -and (-not $script:dragging) -and ($script:balMode -eq 'none') -and (-not $script:starActive) -and ($script:shMode -eq 'none'))
        $maxAge = if ($script:watchTok -eq 'done') { 8.0 } else { 15.0 }
        $fresh  = ($script:watchTok -and ($script:watchAge -lt $maxAge))
        $target = if ($calmPose -and $fresh) { 1.0 } else { 0.0 }
        $script:watchVis += ($target - $script:watchVis) * 0.09   # slow enough to read the fade
        if ($script:watchVis -lt 0.02 -and $target -eq 0.0) { $script:watchVis = 0 }
        # Only draw while still in a calm pose; if a heavy animation took over, hide at once
        # (no trailing/freezing). watchVis keeps easing to 0 so it fades back in cleanly later.
        if ($calmPose -and $script:watchVis -gt 0.001) { Render-Status }
        elseif ($script:statusOv.Visible) { $script:statusOv.Hide() }
    }

    # While Claude Code is working, lock Clawd into ONE animation (Working or Cooking) for the whole
    # session - it loops until Claude is done, then ends together with the status text. No wandering,
    # dancing, or mischief meanwhile. Everyday poses are interrupted at once (bigger one-off
    # performances are left to finish; the transition picker keeps the loop going afterwards).
    $busyStates = @('idle', 'walk', 'wave', 'jump', 'dance')
    if (Test-ClaudeWorking) {
        if (-not $script:dragging -and $script:fx -eq 'none' -and $script:balMode -eq 'none' -and -not $script:starActive -and $script:shMode -eq 'none' -and ($busyStates -contains $script:state)) {
            Start-WorkSession
        }
    } elseif ($script:workAnim -ne '') {
        # Claude finished and the status text is gone -> end the work animation right now
        $script:workAnim = ''
        if ($script:state -eq 'work' -or $script:state -eq 'cook') {
            Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
        }
    }

    # Shooting-star show: update + render; cancel if its state gets taken over by another action
    if ($script:starActive) {
        if ($script:state -eq 'stargaze') { Update-StarShow }
        else { Cancel-StarShow }
    }

    # ===== The Shadow: encounter timeline =====
    if ($script:shMode -eq 'show') {
        $script:shT++
        $t2 = $script:shT
        # Fade-in then fade-out (full opacity while shown)
        if ($t2 -le 35) { $script:shForm.Opacity = [Math]::Min(1.0, $t2 / 35.0) }
        elseif ($t2 -ge 480 -and $t2 -le 530) { $script:shForm.Opacity = [Math]::Max(0, 1.0 - ($t2 - 480) / 50.0) }
        elseif ($t2 -lt 480) { $script:shForm.Opacity = 1.0 }
        # Frames: peek out (0-110), stare (110-420), retreat and vanish (420-530)
        $last = $script:shFrames.Count - 1
        if ($t2 -lt 110) {
            $p2 = $t2 / 110.0
            $e2 = $p2 * $p2 * (3 - 2 * $p2)
            $script:shIdx = [int]([Math]::Round($e2 * $script:shPeak))
        } elseif ($t2 -lt 420) {
            $script:shIdx = $script:shPeak
        } else {
            $p2 = [Math]::Min(1.0, ($t2 - 420) / 110.0)
            $e2 = $p2 * $p2 * (3 - 2 * $p2)
            $script:shIdx = [int]($script:shPeak + [Math]::Round($e2 * ($last - $script:shPeak)))
        }
        if ($script:shIdx -gt $last) { $script:shIdx = $last }
        $script:shForm.Invalidate()
        # The good Clawd notices: startled + "!"
        if ($t2 -eq 85) {
            if (-not $script:dragging -and $script:fx -eq 'none') { Start-Fx 'hop' 20 }
            $script:blinkTicks = 8
        }
        # Nervous blinking during the staredown
        if ($t2 -ge 110 -and $t2 -lt 420 -and $script:blinkCd -gt 45) { $script:blinkCd = 45 }
        # Shadow vanishes -> confused searching
        if ($t2 -eq 530) {
            $script:shForm.Hide()
            if (($script:state -eq 'idle' -or $script:state -eq 'walk') -and $script:fx -eq 'none') { Start-Fx 'lookaround' 170 }
        }
        if ($t2 -ge 560) { Stop-Shadow }
    }

    $cp = [System.Windows.Forms.Cursor]::Position

    # ===== Dangling from the cursor =====
    if ($script:dragging) {
        if ($script:moved) {
            # Raw cursor velocity (light EMA) - sets the throw strength
            $script:cvX = 0.6 * ($cp.X - $script:lastCpX) + 0.4 * $script:cvX
            $script:cvY = 0.6 * ($cp.Y - $script:lastCpY) + 0.4 * $script:cvY

            # === DRAGGING (easing / inertia lag) ===
            # The anchor (claw) does not stick rigidly to the cursor - it CHASES the cursor with
            # a LERP so it feels like it has mass.
            $script:ancVX = ($cp.X - $script:ancX) * 0.35
            $script:ancVY = ($cp.Y - $script:ancY) * 0.35
            $script:ancX += $script:ancVX
            $script:ancY += $script:ancVY

            # Spring-damper pendulum (under-damped) driven by the anchor acceleration;
            # the spring stiffens non-linearly at large angles -> never flips a full 360.
            $accX = $script:ancVX - $script:lastAncVX
            $stiff = 1.0 + ($script:theta * $script:theta * 1.6)
            $alpha = (-0.0075 * $script:theta * $stiff) - (0.03 * $script:omega) - (0.012 * $accX) - (0.0022 * $script:ancVX)
            $script:omega = [Math]::Max(-0.28, [Math]::Min(0.28, $script:omega + $alpha))
            $script:theta += $script:omega
            if ($script:theta -gt 1.35)  { $script:theta = 1.35;  $script:omega *= 0.5 }   # soft limit ~77 deg
            if ($script:theta -lt -1.35) { $script:theta = -1.35; $script:omega *= 0.5 }
            $script:lastAncVX = $script:ancVX
            $script:form.Location = New-Object System.Drawing.Point([int][Math]::Round($script:ancX - $script:anchorX), [int][Math]::Round($script:ancY - $script:anchorY))
        }
        # Blinking keeps running normally while dangling
        if ($script:blinkTicks -gt 0) { $script:blinkTicks-- }
        else {
            $script:blinkCd--
            if ($script:blinkCd -le 0) { $script:blinkTicks = 10; $script:blinkCd = $script:rand.Next($script:blinkMinT, $script:blinkMaxT) }
        }
        $script:lastCpX = $cp.X
        $script:lastCpY = $cp.Y
        Update-PetVisual
        return
    }
    $script:lastCpX = $cp.X
    $script:lastCpY = $cp.Y

    # Eyes follow the cursor
    $ccx = $script:form.Left + $script:formW / 2.0
    $ccy = $script:form.Top + $script:destH - $script:crabH / 2.0
    $dx = $cp.X - $ccx; $dy = $cp.Y - $ccy
    $tx = [Math]::Max(-1.0, [Math]::Min(1.0, $dx / 240.0)) * 55
    $ty = [Math]::Max(-1.0, [Math]::Min(1.0, $dy / 240.0)) * 35
    if (-not $script:featEyes) { $tx = 0; $ty = 0 }
    # While the balloon descends: eyes lock onto the balloon, not the cursor
    if ($script:balMode -eq 'descend') {
        $dxB = $script:balX - $ccx
        $dyB = ($script:balY + 30) - $ccy
        $tx = [Math]::Max(-1.0, [Math]::Min(1.0, $dxB / 240.0)) * 55
        $ty = [Math]::Max(-1.0, [Math]::Min(1.0, $dyB / 240.0)) * 35
    }
    # Looking around: glance left then right, ignore the cursor for a moment
    if ($script:fx -eq 'lookaround') {
        $p = $script:fxTotal - $script:fxTicks
        if ($p -lt 60) { $tx = -55; $ty = 5 }
        elseif ($p -lt 120) { $tx = 55; $ty = 5 }
    }
    # Focus on the window being shoved
    if ($script:state -eq 'push') {
        $tx = 55.0 * $script:pushSide
        $ty = 5
    }
    # Eyes locked onto The Shadow at the screen edge
    if ($script:shMode -eq 'show' -and $script:shT -gt 70) {
        $tx = -55.0 * $script:shDir
        $ty = 8
    }
    # Stargazing: eyes follow the meteor crossing the sky
    if ($script:state -eq 'stargaze') {
        $tx = 0; $ty = -38
        if ($script:meteors.Count -gt 0) {
            $m = $script:meteors[$script:meteors.Count - 1]
            $mdx = ($script:starL + $m.x) - $ccx
            $mdy = ($script:starTop + $m.y) - $ccy
            $tx = [Math]::Max(-1.0, [Math]::Min(1.0, $mdx / 500.0)) * 55
            $ty = [Math]::Max(-1.0, [Math]::Min(1.0, $mdy / 500.0)) * 38
        }
    }
    $script:eyeOX += ($tx - $script:eyeOX) * 0.22
    $script:eyeOY += ($ty - $script:eyeOY) * 0.22
    $script:cursorNear = ([Math]::Sqrt($dx * $dx + $dy * $dy) -lt 150)

    # Typing -> confused "?" (wakes him if sleeping)
    # Scanning the keyboard 15x/sec is enough (saves ~75% of API calls with no visible difference)
    if ($script:featType -and $script:qmCd -le 0 -and ($script:globalT % 4) -eq 0 -and [ClawdInput]::AnyKeyDown()) {
        if ($script:fx -eq 'doze') { $script:fx = 'none'; Start-Fx 'hop' 20 }
        $script:qmTicks = 160
        $script:qmCd = 500
        $script:blinkTicks = 8
    }

    # Blink (while sleeping the eyes stay closed)
    if ($script:fx -eq 'doze') { if ($script:blinkTicks -lt 2) { $script:blinkTicks = 2 } }
    elseif ($script:blinkTicks -gt 0) { $script:blinkTicks-- }
    elseif ($script:state -ne 'wave' -and $script:state -ne 'jump') {
        $script:blinkCd--
        if ($script:blinkCd -le 0) {
            $script:blinkTicks = 10
            $script:blinkCd = $script:rand.Next($script:blinkMinT, $script:blinkMaxT)
        }
    }

    if ($script:fxTicks -gt 0) {
        $script:fxTicks--
        if ($script:fxTicks -le 0) {
            if ($script:fx -eq 'doze') { Start-Fx 'hop' 20 } else { $script:fx = 'none' }
        }
    }

    # ===== Balloon logic =====
    if ($script:balMode -eq 'descend') {
        if ($script:state -ne 'walk') { Cancel-Balloon }
        else {
            $bs = $script:destW / 80.0
            $script:balY += 0.9 * $bs
            # Natural wind (same strength as the rise): decaying random wander + two gusts
            $script:balWind = ($script:balWind + ($script:rand.NextDouble() - 0.5) * 0.16) * 0.975
            $script:balWind = [Math]::Max(-1.5, [Math]::Min(1.5, $script:balWind))
            $script:balX += $script:balWind + 0.6 * [Math]::Sin($script:globalT * 0.019) + 0.35 * [Math]::Sin($script:globalT * 0.047)
            # Soft edge: near the screen border the wind is gently pushed back so the
            # balloon curves away - instead of being pinned to a vertical wall line.
            $soft = 90
            if ($script:balX -lt ($script:wa.Left + $soft))  { $script:balWind += 0.07 }
            if ($script:balX -gt ($script:wa.Right - $soft)) { $script:balWind -= 0.07 }
            $script:balX = [Math]::Max(($script:wa.Left + 8), [Math]::Min(($script:wa.Right - 8), $script:balX))
            $script:balForm.Location = New-Object System.Drawing.Point([int]($script:balX - 35), [int]$script:balY)
            $script:balForm.Invalidate()
            $stringBot = $script:balY + (44 + 30) * $bs + 6
            $armX = $script:form.Left + $script:margin + $script:armLX
            $armY = $script:form.Top + $script:armLY
            if ($stringBot -ge $armY -and [Math]::Abs($script:balX - $armX) -lt 26) {
                # CAUGHT! enter the lift-off phase: slowly pulled upward
                $script:balForm.Hide()
                $script:balMode = 'lift'
                $script:balT = 0
                $script:theta = 0; $script:omega = 0
                $script:balVY = 0
                $script:onPlat = $false
                $w2 = $script:dragW
                $h2 = $script:dragH + [int](80 * $bs)
                $script:form.ClientSize = New-Object System.Drawing.Size($w2, $h2)
                $pivY2 = (8 + 44 * $bs) + (30 * $bs)
                $script:form.Location = New-Object System.Drawing.Point([int]($armX - $w2 / 2), [int]($armY - $pivY2))
                $script:balDriftX = [double]$script:form.Left
                $script:balPosY   = [double]$script:form.Top
                $script:balLastDX = 0
                Set-State 'balloon' 9999
                Update-PetVisual
            } elseif (($script:balY + 44 * $bs) -ge (($script:bottomY + $script:destH) - 6)) {
                Cancel-Balloon   # balloon landed too soon
            }
        }
    }
    elseif ($script:balMode -eq 'lift') {
        # Lift-off: pulled up slowly, body rotation handled in Paint
        $script:balT++
        $p = [Math]::Min(1.0, $script:balT / 55.0)
        $e = $p * $p * (3 - 2 * $p)
        $script:balPosY += (-0.7 * $e)
        $drift = 0.3 * [Math]::Sin($script:globalT * 0.03)
        $script:balDriftX += $drift
        $script:balLastDX = $drift
        $script:form.Location = New-Object System.Drawing.Point([int][Math]::Round($script:balDriftX), [int][Math]::Round($script:balPosY))
        if ($script:balT -ge 55) {
            $script:balMode = 'float'
            $script:balT = 0
            $script:balVY = -0.7
            $script:theta = 0
            $script:omega = 0.02   # a little initial swing to keep it alive
        }
        Update-PetVisual
        return
    }
    elseif ($script:balMode -eq 'float') {
        $script:balT++
        $script:balVY = [Math]::Max(-1.4, $script:balVY - 0.02)   # rises faster, smoothly
        # Natural wind (no fixed path): decaying random walk + two gusts of different frequency
        $script:balWind = ($script:balWind + ($script:rand.NextDouble() - 0.5) * 0.16) * 0.975
        $script:balWind = [Math]::Max(-1.5, [Math]::Min(1.5, $script:balWind))
        $fw = $script:form.Width
        $crabX = $script:balDriftX + $fw / 2.0
        if ($crabX -lt ($script:wa.Left + 80))  { $script:balWind += 0.05 }   # soft push off the edges
        if ($crabX -gt ($script:wa.Right - 80)) { $script:balWind -= 0.05 }
        $drift = $script:balWind + 0.5 * [Math]::Sin($script:globalT * 0.017) + 0.3 * [Math]::Sin($script:globalT * 0.041)
        $accX = $drift - $script:balLastDX
        $script:balLastDX = $drift
        $script:balDriftX += $drift
        $crabX = $script:balDriftX + $fw / 2.0   # hard clamp keeps the crab on screen (gentle, ~24px)
        if ($crabX -lt ($script:wa.Left + 24))  { $script:balDriftX = $script:wa.Left + 24 - $fw / 2.0 }
        if ($crabX -gt ($script:wa.Right - 24)) { $script:balDriftX = $script:wa.Right - 24 - $fw / 2.0 }
        # Pendulum at the end of the string
        $stiff = 1.0 + ($script:theta * $script:theta * 1.6)
        $alpha = (-0.0075 * $script:theta * $stiff) - (0.03 * $script:omega) - (0.012 * $accX)
        $script:omega = [Math]::Max(-0.28, [Math]::Min(0.28, $script:omega + $alpha))
        $script:theta += $script:omega
        $script:balPosY += $script:balVY
        $script:form.Location = New-Object System.Drawing.Point([int][Math]::Round($script:balDriftX), [int][Math]::Round($script:balPosY))
        if ($script:form.Top -le ($script:wa.Top + [int]($script:wa.Height * 0.16)) -or $script:balT -gt 480) {
            $script:balMode = 'pop'
            $script:balPopT = 0
        }
        Update-PetVisual
        return
    }
    elseif ($script:balMode -eq 'pop') {
        $script:balPopT++
        if ($script:balPopT -ge 13) {
            # Done popping -> back to the normal layout then free-fall
            $bs = $script:destW / 80.0
            $pivY2 = (8 + 44 * $bs) + (30 * $bs)
            $bodyX = $script:form.Left + $script:form.ClientSize.Width / 2.0 + 40 * [Math]::Sin($script:theta)
            $bodyY = $script:form.Top + $pivY2 + 40 * [Math]::Cos($script:theta)
            $script:form.ClientSize = New-Object System.Drawing.Size($script:formW, $script:destH)
            $newLeft = [Math]::Max($script:wa.Left, [Math]::Min(($script:wa.Right - $script:formW), [int]($bodyX - $script:formW / 2)))
            $newTop  = [Math]::Max($script:wa.Top, [int]($bodyY - ($script:destH - $script:crabH / 2.0)))
            $script:form.Location = New-Object System.Drawing.Point($newLeft, $newTop)
            $script:posX = [double]$newLeft
            $script:posY = [double]$newTop
            $script:fallVX = $script:balLastDX * 2
            $script:vy = 0
            $script:balMode = 'none'
            Set-State 'fall' 9999
            Update-PetVisual
        }
        Update-PetVisual
        return
    }

    # System awareness: check CPU & user idle every ~2 seconds
    if ($null -ne $script:cpuCounter) {
        $script:sysCheck--
        if ($script:sysCheck -le 0) {
            $script:sysCheck = 125
            try {
                $cpu = $script:cpuCounter.NextValue()
                $script:cpuEMA = 0.6 * $script:cpuEMA + 0.4 * $cpu
            } catch { }
            $idleSec = [ClawdInput]::IdleSeconds()
            $prevMode = $script:sysMode
            if ($script:cpuEMA -gt 75) { $script:sysMode = 'busy' }
            elseif ($idleSec -gt 90)   { $script:sysMode = 'sleepy' }
            else                       { $script:sysMode = 'normal' }
            # User returns after a long idle -> wakes up startled
            if ($prevMode -eq 'sleepy' -and $script:sysMode -ne 'sleepy') {
                if ($script:fx -eq 'doze') { $script:fx = 'none'; Start-Fx 'hop' 20 }
            }
            # Just went idle -> hand unused pages back to the OS (lighter in the background)
            if ($prevMode -ne 'sleepy' -and $script:sysMode -eq 'sleepy') {
                [System.GC]::Collect(); [ClawdWin]::TrimMemory()
            }
        }
    }

    # Platform window list refreshed periodically (0.5s) + floor detection
    $script:platRefresh--
    if ($script:platRefresh -le 0) {
        $script:platRefresh = 30
        if ($script:featPlat) { $script:platforms = [ClawdWin]::PlatformsArr($script:selfHwnd) }
        else { $script:platforms = @() }

        # Dynamic floor: a fullscreen game hides the taskbar -> floor = bottom of the screen;
        # otherwise floor = top edge of the taskbar (working area)
        $script:wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $bnd = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $floorBottom = $script:wa.Bottom
        if ([ClawdWin]::IsFullscreenForeground($bnd.Left, $bnd.Top, $bnd.Right, $bnd.Bottom)) {
            $floorBottom = $bnd.Bottom
        }
        $newBottomY = $floorBottom - $script:destH
        if ($newBottomY -ne $script:bottomY) {
            $oldB = $script:bottomY
            $script:bottomY = $newBottomY
            # Ground drops (taskbar gone) -> fall smoothly to the new bottom
            if ($newBottomY -gt $oldB -and -not $script:onPlat -and -not $script:dragging -and
                $script:balMode -eq 'none' -and ($script:state -eq 'idle' -or $script:state -eq 'walk' -or $script:state -eq 'wave' -or $script:state -eq 'jump')) {
                $script:posY = [double]$script:form.Top
                $script:posX = [double]$script:form.Left
                $script:vy = 0; $script:fallVX = 0
                if ($script:fx -ne 'none') { $script:fx = 'none'; $script:fxTicks = 0 }
                Set-State 'fall' 9999
            }
            # Ground rises (taskbar back) -> the supportY sync below will lift him
        }
    }

    # === FLOATING / FALLING (Euler integration) ===
    # Holy Trinity: acceleration (gravity) -> velocity -> position, every frame.
    if ($script:state -eq 'fall') {
        $oldFeet = $script:posY + $script:destH
        $script:vy += (0.8 * $script:cfgGrav)   # gravity
        $script:fallVX *= 0.995   # air drag
        $script:vy *= 0.995
        $script:posX += $script:fallVX
        $script:posY += $script:vy

        # Walls & ceiling: bounce with restitution
        $maxX = $script:wa.Right - $script:formW
        if ($script:posX -le $script:wa.Left) { $script:posX = $script:wa.Left; $script:fallVX = [Math]::Abs($script:fallVX) * 0.5 }
        if ($script:posX -ge $maxX) { $script:posX = $maxX; $script:fallVX = -[Math]::Abs($script:fallVX) * 0.5 }
        if ($script:posY -lt $script:wa.Top) { $script:posY = $script:wa.Top; $script:vy = [Math]::Abs($script:vy) * 0.4 }

        # Top edge of an app window = platform: he can land on it
        $landT = $null; $landH = [long]0
        if ($script:vy -gt 0) {
            $newFeet = $script:posY + $script:destH
            $crabL = $script:posX + $script:margin + 6
            $crabR = $script:posX + $script:formW - $script:margin - 6
            for ($i = 0; $i -lt $script:platforms.Length; $i += 5) {
                $T = $script:platforms[$i + 2]
                if ($T -le ($script:wa.Top + 20) -or $T -ge $script:wa.Bottom) { continue }
                if ($oldFeet -le ($T + 2) -and $newFeet -ge $T -and $crabR -ge $script:platforms[$i + 1] -and $crabL -le $script:platforms[$i + 3]) {
                    if ($null -eq $landT -or $T -lt $landT) { $landT = $T; $landH = $script:platforms[$i] }
                }
            }
        }

        $surfaceY = $script:bottomY
        $hitSurface = $false
        if ($null -ne $landT) {
            $surfaceY = $landT - $script:destH
            $hitSurface = $true
        } elseif ($script:posY -ge $script:bottomY) {
            $hitSurface = $true
        }

        if ($hitSurface) {
            $script:posY = $surfaceY
            if ($script:vy -gt 4.5) {
                # Bounce with restitution + friction
                $script:vy = -$script:vy * 0.32
                $script:fallVX *= 0.85
                Start-Fx 'squash' 8
            } else {
                $script:vy = 0
                $script:fallVX *= 0.85
                if ([Math]::Abs($script:fallVX) -lt 0.6) {
                    # Anti-jitter settle -> land on this platform
                    $script:fallVX = 0
                    $script:supportY = $script:posY
                    $script:onPlat = ($null -ne $landT)
                    if ($script:onPlat) { $script:platHwnd = $landH }
                    Start-Fx 'squash' 10
                    Set-State 'jump' 275
                }
            }
        }
        $script:form.Location = New-Object System.Drawing.Point([int][Math]::Round($script:posX), [int][Math]::Round($script:posY))
        Update-PetVisual
        return
    }

    # ===== Climbing the wall: phase machine =====
    if ($script:state -eq 'climb') {
        $half = $script:climbSide / 2.0
        $feetOff = $script:crabH / 2.0
        $wallRot = 90.0 * $script:climbWall
        $targetX = $script:wa.Left - ($half - $feetOff)
        if ($script:climbWall -lt 0) { $targetX = $script:wa.Right - ($half + $feetOff) }
        switch ($script:climbPhase) {
            'in' {
                # Rotating from standing to clinging to the wall
                $script:climbT++
                $p = [Math]::Min(1.0, $script:climbT / 22.0)
                $e = $p * $p * (3 - 2 * $p)
                $script:climbRot = $wallRot * $e
                $script:climbX += ($targetX - $script:climbX) * 0.18
                if ($script:climbT -ge 22) { $script:climbX = $targetX; $script:climbPhase = 'up' }
            }
            'up' {
                $script:climbY -= 0.5
                $script:legWait--
                if ($script:legWait -le 0) {
                    $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
                    $script:legFrame = $script:legLoop[$script:legPos]
                    $script:legWait = $script:legDelays[$script:legFrame]
                }
                if ($script:climbY -le $script:climbTarget) {
                    $script:climbPhase = 'pause'
                    $script:climbT = $script:rand.Next(90, 240)
                    $script:legFrame = 0
                }
            }
            'pause' {
                $script:climbT--
                if ($script:climbT -le 0) {
                    if ($script:rand.NextDouble() -lt 0.5) {
                        $script:climbPhase = 'down'
                    } else {
                        Stop-Climb $true   # jump off the wall!
                        return
                    }
                }
            }
            'down' {
                $script:climbY += 0.55
                $script:legWait--
                if ($script:legWait -le 0) {
                    $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
                    $script:legFrame = $script:legLoop[$script:legPos]
                    $script:legWait = $script:legDelays[$script:legFrame]
                }
                $floorCY = $script:bottomY + $script:destH - $script:crabH / 2.0
                if ($script:climbY -ge $floorCY) {
                    $script:climbY = $floorCY
                    $script:climbPhase = 'out'
                    $script:climbT = 0
                    $script:legFrame = 0
                }
            }
            'out' {
                # Rotating back upright while sliding in from the wall
                $script:climbT++
                $p = [Math]::Min(1.0, $script:climbT / 22.0)
                $e = $p * $p * (3 - 2 * $p)
                $script:climbRot = $wallRot * (1 - $e)
                $standCX = $script:wa.Left + $script:margin + $script:destW / 2.0
                if ($script:climbWall -lt 0) { $standCX = $script:wa.Right - $script:margin - $script:destW / 2.0 }
                $script:climbX += (($standCX - $half) - $script:climbX) * 0.18
                if ($script:climbT -ge 22) {
                    Stop-Climb $false
                    return
                }
            }
        }
        if ($script:state -eq 'climb') {
            $script:form.Location = New-Object System.Drawing.Point([int][Math]::Round($script:climbX), [int][Math]::Round($script:climbY - $half))
        }
        Update-PetVisual
        return
    }

    # ===== Shoving a window from the side: approach the window edge then shove rhythmically =====
    if ($script:state -eq 'push') {
        $r3 = [ClawdWin]::GetRect($script:pushHwnd)
        if ($null -eq $r3) { Stop-Push; return }
        # Standing position against the window side
        $targetX = $r3[0] - $script:formW + $script:margin   # stand on the left, shove to the right
        if ($script:pushSide -lt 0) { $targetX = $r3[2] - $script:margin }
        switch ($script:pushPhase) {
            'approach' {
                $script:pushT++
                $d = $targetX - $script:posX
                if ([Math]::Abs($d) -le 2) {
                    $script:posX = $targetX
                    $script:pushPhase = 'tug'
                    $script:pushT = 0
                    $script:legFrame = 0
                    $script:dir = $script:pushSide   # facing the window
                } elseif ($script:pushT -gt 900) {
                    Stop-Push; return   # took too long (window ran away?) -> give up
                } else {
                    $script:dir = [Math]::Sign($d)
                    $script:posX += $script:dir * 0.7
                    $script:legWait--
                    if ($script:legWait -le 0) {
                        $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
                        $script:legFrame = $script:legLoop[$script:legPos]
                        $script:legWait = $script:legDelays[$script:legFrame]
                    }
                }
            }
            'tug' {
                $script:pushT++
                $c = $script:pushT % 36
                if ($c -ge 18 -and $c -lt 26) {
                    $room = $false
                    if ($script:pushSide -gt 0 -and ($r3[2] + 2) -lt ($script:wa.Right - 40)) { $room = $true }
                    if ($script:pushSide -lt 0 -and ($r3[0] - 2) -gt ($script:wa.Left + 40)) { $room = $true }
                    if ($room) {
                        [ClawdWin]::Nudge($script:pushHwnd, (2 * $script:pushSide), 0)
                        $script:posX += (2 * $script:pushSide)   # advance along with the shoved window
                        $script:legWait--
                        if ($script:legWait -le 0) {
                            $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
                            $script:legFrame = $script:legLoop[$script:legPos]
                            $script:legWait = 2
                        }
                    } else {
                        Stop-Push; return
                    }
                }
                if ($c -eq 35) {
                    $script:pushTugs++
                    if ($script:pushTugs -ge 4) { Stop-Push; return }
                }
            }
        }
        $script:form.Left = [int][Math]::Round($script:posX)
        $script:form.Top  = [int]$script:bottomY
        Update-PetVisual
        return
    }

    # === Active platform: follow the window movement, fall if it is gone/shifted ===
    if ($script:state -ne 'lurk') {
        if ($script:onPlat) {
            $r = [ClawdWin]::GetRect($script:platHwnd)
            $drop = $false
            if ($null -eq $r) { $drop = $true }
            else {
                $script:supportY = [double]($r[1] - $script:destH)
                $crabL = $script:posX + $script:margin + 6
                $crabR = $script:posX + $script:formW - $script:margin - 6
                if ($crabR -lt ($r[0] + 10) -or $crabL -gt ($r[2] - 10)) { $drop = $true }
                if ($script:supportY -gt $script:bottomY -or $r[1] -le ($script:wa.Top + 20)) { $drop = $true }
            }
            if ($drop) {
                $script:onPlat = $false
                $script:posY = [double]$script:form.Top
                $script:vy = 0
                $script:fallVX = $script:dir * 1.2
                $script:fx = 'none'; $script:fxTicks = 0
                Set-State 'fall' 9999
                Update-PetVisual
                return
            }
            $script:form.Top = [int]$script:supportY
            # Mischief: tugging the window with a rhythmic YANK (window moves only on the yank)
            if ($script:fx -eq 'shove') {
                $els = $script:fxTotal - $script:fxTicks
                $c = $els % 36
                if ($c -eq 0) { $script:legFrame = 0; $script:legWait = 2 }
                if ($c -ge 18 -and $c -lt 26) {
                    $r2 = [ClawdWin]::GetRect($script:platHwnd)
                    $okPush = $false
                    if ($null -ne $r2) {
                        if ($script:shoveDir -gt 0 -and $r2[0] -lt ($script:wa.Right - 280)) { $okPush = $true }
                        if ($script:shoveDir -lt 0 -and $r2[2] -gt ($script:wa.Left + 280)) { $okPush = $true }
                    }
                    if ($okPush) {
                        [ClawdWin]::Nudge($script:platHwnd, ($script:shoveDir * 2), 0)
                        $script:posX += ($script:shoveDir * 2)   # jerk along with the window
                        $script:form.Left = [int][Math]::Round($script:posX)
                        $script:legWait--
                        if ($script:legWait -le 0) {
                            $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
                            $script:legFrame = $script:legLoop[$script:legPos]
                            $script:legWait = 2
                        }
                    } else {
                        $script:fx = 'none'; $script:fxTicks = 0
                    }
                }
            }
        } else {
            $script:supportY = [double]$script:bottomY
            if ($script:fx -eq 'shove') { $script:fx = 'none'; $script:fxTicks = 0 }
            # Sync to the active floor (e.g. taskbar reappears after exiting a game)
            if ($script:state -ne 'fall' -and $script:state -ne 'balloon' -and $script:form.Top -gt [int]$script:supportY) {
                $script:form.Top = [int]$script:supportY
            }
        }
    }

    $script:ticks--
    # Code sequence: start the wave animation right as the typing phase ends
    if ($script:state -eq 'code' -and $script:ticks -eq 175) {
        [ClawdAnim]::Start($script:imgWave)
    }
    # Chasing the balloon: walk toward the balloon position (ignore the cursor-near freeze)
    if ($script:state -eq 'walk' -and $script:balMode -eq 'descend') {
        $armX = $script:form.Left + $script:margin + $script:armLX
        $ddx = $script:balX - $armX
        if ([Math]::Abs($ddx) -gt 8) {
            $script:dir = [Math]::Sign($ddx)
            $script:posX += $script:dir * (0.9 * $script:cfgSpeed)
            $maxX = $script:wa.Right - $script:formW
            if ($script:posX -lt $script:wa.Left) { $script:posX = $script:wa.Left }
            if ($script:posX -gt $maxX) { $script:posX = $maxX }
            $script:form.Left = [int][Math]::Round($script:posX)
            $script:form.Top  = [int]$script:supportY
            $script:legWait--
            if ($script:legWait -le 0) {
                $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
                $script:legFrame = $script:legLoop[$script:legPos]
                $script:legWait = [Math]::Max(2, [int]($script:legDelays[$script:legFrame] * 0.6))
            }
        } else {
            $script:legFrame = 0
        }
        Update-PetVisual
        $script:topCnt++
        if ($script:topCnt -ge 600) { $script:topCnt = 0; $script:form.TopMost = $true }
        return
    }
    if ($script:state -eq 'walk' -and -not $script:cursorNear) {
        # Ease-in/ease-out: start slow, speed up, slow down before stopping
        $elapsed = $script:walkTotal - $script:ticks
        $speedF = [Math]::Min(1.0, [Math]::Min(($elapsed + 5) / 35.0, ($script:ticks + 5) / 35.0))
        $spdMul = 1.0
        if ($script:sysMode -eq 'busy') { $spdMul = 1.9 }   # restless: walks faster
        $script:posX += $script:dir * (0.45 * $script:cfgSpeed * $spdMul) * $speedF
        # Advance the leg frame per the original GIF timing (stepping frames only)
        $script:legWait--
        if ($script:legWait -le 0) {
            $script:legPos = ($script:legPos + 1) % $script:legLoop.Count
            $script:legFrame = $script:legLoop[$script:legPos]
            $script:legWait = $script:legDelays[$script:legFrame]
        }
        $maxX = $script:wa.Right - $script:formW
        if ($script:posX -le $script:wa.Left) {
            $script:posX = $script:wa.Left
            # Reached the left wall: sometimes climbs instead of turning back
            if ($script:featClimb -and -not $script:onPlat -and ($script:wantClimb -or $script:rand.NextDouble() -lt 0.40)) {
                $script:wantClimb = $false
                $script:form.Left = [int]$script:posX
                Start-Climb 1
                return
            }
            $script:dir = 1
        }
        if ($script:posX -ge $maxX) {
            $script:posX = $maxX
            if ($script:featClimb -and -not $script:onPlat -and ($script:wantClimb -or $script:rand.NextDouble() -lt 0.40)) {
                $script:wantClimb = $false
                $script:form.Left = [int]$script:posX
                Start-Climb (-1)
                return
            }
            $script:dir = -1
        }
        $script:form.Left = [int][Math]::Round($script:posX)
        $script:form.Top  = [int]$script:supportY
    } elseif ($script:fx -ne 'shove') {
        # Standing: legs return to the neutral pose (unless dragging a window)
        $script:legFrame = 0
        $script:legWait = 2
    }

    if ($script:ticks -le 0) {
        # Claude still working -> keep looping the one chosen animation; never fall through to idle
        if ((Test-ClaudeWorking) -and -not $script:dragging -and $script:fx -eq 'none' -and $script:balMode -eq 'none' -and -not $script:starActive -and $script:shMode -eq 'none') {
            Start-WorkSession
            return
        }
        switch ($script:state) {
            'idle' {
                # Rare: a balloon drops from the sky (~3%, only on the floor)
                if ((-not $script:onPlat) -and $script:balMode -eq 'none' -and $script:rand.NextDouble() -lt 0.03) {
                    Start-Balloon
                    return
                }
                # Rare: shooting-star shower (~2.5%) - he stops, gazes at the sky, makes a wish
                if ($script:rand.NextDouble() -lt 0.025) {
                    Start-StarShow
                    return
                }
                # Very rare (~1%): The Shadow peeks from the screen edge
                if ((-not $script:onPlat) -and $script:shMode -eq 'none' -and $script:rand.NextDouble() -lt 0.01) {
                    Start-Shadow
                    return
                }
                # Ambient: when Claude is idle, Clawd still tinkers occasionally (Working/Cooking).
                # While Claude is actually working this is unreachable - that case is handled up top
                # by the lock-in force. Rare (~6% combined), spaced out by busyUntil, alternating.
                if ($script:globalT -ge $script:busyUntil -and $script:rand.NextDouble() -lt 0.06) {
                    Start-BusyNext
                    $script:busyUntil = $script:globalT + $script:ticks + $script:rand.Next(600, 1100)
                    return
                }
                # Mischief: perched on a window? sometimes drags it (~20%)
                if ($script:featMisch -and $script:onPlat -and $script:fx -eq 'none' -and $script:rand.NextDouble() -lt 0.20) {
                    $script:shoveDir = 1
                    if ($script:rand.NextDouble() -lt 0.5) { $script:shoveDir = -1 }
                    Start-Fx 'shove' 110
                    Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
                    return
                }
                # Mischief: a window nearby on the floor? sometimes shoves it from the side (~10%)
                if ($script:featMisch -and -not $script:onPlat -and $script:fx -eq 'none' -and $script:rand.NextDouble() -lt 0.10) {
                    $pt = Find-PushTarget
                    if ($null -ne $pt) {
                        Start-Push $pt
                        return
                    }
                }
                # Work mode: CPU busy -> pacing restlessly with short pauses
                if ($script:sysMode -eq 'busy') {
                    if ($script:rand.NextDouble() -lt 0.75) {
                        $script:dir *= -1
                        $wdur = $script:rand.Next(120, 280)
                        Set-State 'walk' $wdur
                        $script:walkTotal = $wdur
                    } else {
                        Set-State 'idle' $script:rand.Next(60, 160)   # short restless pause
                    }
                    return
                }
                # Old laptop left alone -> drowsy, dozes off more often
                if ($script:sysMode -eq 'sleepy' -and $script:rand.NextDouble() -lt 0.6) {
                    Start-Fx 'doze' $script:rand.Next(400, 800)
                    Set-State 'idle' $script:rand.Next(($script:idleMaxT), ($script:idleMaxT + 400))
                    return
                }
                # Near the screen edge (on the floor) -> sometimes lurks: peeks from the edge
                $nearL = ($script:posX - $script:wa.Left) -lt 60
                $nearR = (($script:wa.Right - $script:formW) - $script:posX) -lt 60
                if ($script:featLurk -and (-not $script:onPlat) -and ($nearL -or $nearR) -and $script:rand.NextDouble() -lt 0.45) {
                    $script:lurkDir = 1
                    if ($nearR) { $script:lurkDir = -1; $script:posX = [double]($script:wa.Right - $script:formW) }
                    else        { $script:posX = [double]$script:wa.Left }
                    $script:form.Left = [int]$script:posX
                    $script:form.Top  = [int]$script:supportY
                    Set-State 'lurk' 430   # peek out ~7s
                    return
                }
                $r = $script:rand.NextDouble()
                if ($r -lt 0.32) {   # wander 32%
                    if ($script:rand.NextDouble() -lt 0.5) { $script:dir *= -1 }
                    $wdur = $script:rand.Next(250, 560)   # walk 4-9s
                    Set-State 'walk' $wdur
                    $script:walkTotal = $wdur
                } elseif ($r -lt 0.48) {
                    Set-State 'wave' 240   # wave 16%
                } elseif ($r -lt 0.62) {
                    Set-State 'jump' 190   # jump 14%
                } elseif ($r -lt 0.72) {
                    Set-State 'dance' $script:rand.Next(280, 380)   # dance 10% (~4.5-6s of the GIF)
                } elseif ($r -lt 0.82) {
                    Start-Fx 'lookaround' 170   # look around 10%
                    Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
                } elseif ($r -lt 0.90) {
                    Set-State 'code' 380   # hello world 8%
                } elseif ($r -lt 0.96) {
                    Start-Fx 'duck' 300   # hide 6%
                    Set-State 'idle' $script:rand.Next(($script:idleMinT + 60), ($script:idleMaxT + 65))
                } else {
                    Start-Fx 'doze' 320   # doze off 4%
                    Set-State 'idle' $script:rand.Next(($script:idleMinT + 80), ($script:idleMaxT + 85))
                }
            }
            default {
                Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)   # idle 5-10s
            }
        }
    }

    # Power saving: while calm (idle with no effect), repaint at 30 fps is enough -
    # breathing & eye motion are too slow to tell the difference
    $calm = ($script:state -eq 'idle' -and $script:fx -eq 'none' -and $script:qmTicks -le 0 -and -not $script:dragging)
    if (-not $calm -or ($script:globalT % 2) -eq 0) { Update-PetVisual }

    $script:topCnt++
    if ($script:topCnt -ge 600) { $script:topCnt = 0; $script:form.TopMost = $true }
})

# ---------- Mouse interaction ----------
$script:form.Add_MouseEnter({
    if ($script:fx -eq 'doze') {
        $script:fx = 'none'
        Start-Fx 'hop' 20
        $script:hoverCd = 500
        return
    }
    if (($script:state -eq 'idle' -or $script:state -eq 'walk') -and $script:fx -eq 'none' -and $script:hoverCd -le 0) {
        Start-Fx 'hop' 20
        $script:blinkTicks = 8
        $script:hoverCd = 500
    }
})
$script:form.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:state -eq 'balloon') {
            # Grabbed while floating: the balloon lets go and drifts up & away on its own,
            # the crab drops into your grip at its current body position.
            $bs2 = $script:destW / 80.0
            $pivY2 = (8 + 44 * $bs2) + (30 * $bs2)
            $balCX  = $script:form.Left + $script:form.ClientSize.Width / 2.0   # balloon was at top-center
            $balTop = $script:form.Top + 8
            $bodyX = $script:form.Left + $script:form.ClientSize.Width / 2.0 + 40 * [Math]::Sin($script:theta)
            $bodyY = $script:form.Top + $pivY2 + 40 * [Math]::Cos($script:theta)
            $script:balMode = 'none'
            $script:form.ClientSize = New-Object System.Drawing.Size($script:formW, $script:destH)
            $script:form.Location = New-Object System.Drawing.Point([int]($bodyX - $script:formW / 2), [int]($bodyY - ($script:destH - $script:crabH / 2.0)))
            $script:posX = [double]$script:form.Left
            $script:posY = [double]$script:form.Top
            Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
            Update-PetVisual
            # let the freed balloon float off by itself (separate window, drifts up + wind)
            $script:balEscX   = [double]$balCX
            $script:balEscY   = [double]$balTop
            $script:balEscVY  = -1.2
            $script:balEscWind = $script:balLastDX * 3.0
            $script:balForm.ClientSize = New-Object System.Drawing.Size(70, [int]((44 + 34) * $bs2 + 14))
            $script:balForm.Location = New-Object System.Drawing.Point([int]($balCX - 35), [int]($balTop - 4))
            $script:balForm.Show(); $script:balForm.TopMost = $true
            $script:balEscape = $true
            # continue to the drag setup below
        }
        if ($script:state -eq 'climb') { Stop-Climb $false }   # taken off the wall: climb down first
        if ($script:starActive) { Cancel-StarShow; Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT) }
        if ($script:balMode -eq 'descend') { Cancel-Balloon }   # cancel the balloon chase
        $script:dragging  = $true
        $script:moved     = $false
        $script:dragOff   = $_.Location
        $script:dragStart = [System.Windows.Forms.Cursor]::Position
        $script:lastCpX   = $script:dragStart.X
        $script:lastCpY   = $script:dragStart.Y
        $script:lastVelX  = 0
        $script:lastVelY  = 0
        $script:theta     = 0
        $script:omega     = 0
    }
})
$script:form.Add_MouseMove({
    if ($script:dragging) {
        $p = [System.Windows.Forms.Cursor]::Position
        if (-not $script:moved) {
            if ([Math]::Abs($p.X - $script:dragStart.X) -gt 5 -or [Math]::Abs($p.Y - $script:dragStart.Y) -gt 5) {
                # Start dangling: the window grows so the swing is not clipped.
                # The next position is driven by the timer (easing), not MouseMove.
                $script:moved = $true
                $script:ancX = [double]$p.X
                $script:ancY = [double]$p.Y
                $script:ancVX = 0; $script:ancVY = 0; $script:lastAncVX = 0
                $script:cvX = 0; $script:cvY = 0
                $script:onPlat = $false
                if ($script:fx -eq 'doze' -or $script:fx -eq 'duck') { $script:fx = 'none'; $script:fxTicks = 0 }
                # Resize + position + paint in sync, in one breath:
                # prevents a single dirty frame (old sprite + black area) from showing
                $script:form.ClientSize = New-Object System.Drawing.Size($script:dragW, $script:dragH)
                $script:form.Location = New-Object System.Drawing.Point([int]($p.X - $script:anchorX), [int]($p.Y - $script:anchorY))
                Update-PetVisual
            }
        }
    }
})
$script:form.Add_MouseUp({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:dragging = $false
    if ($script:moved) {
        # === VELOCITY TRANSFER (handover) ===
        # The eased anchor velocity is handed to the body right at release - the throw
        # matches the motion you saw. The body position is preserved
        # (computed from anchor + hang direction) so the transition is smooth.
        $script:form.ClientSize = New-Object System.Drawing.Size($script:formW, $script:destH)
        $bodyX = $script:ancX + 40.0 * [Math]::Sin($script:theta)
        $bodyY = $script:ancY + 40.0 * [Math]::Cos($script:theta)
        $newLeft = [Math]::Max($script:wa.Left, [Math]::Min($script:wa.Right - $script:formW, [int]($bodyX - $script:formW / 2)))
        $newTop  = [Math]::Min($script:bottomY, [int]($bodyY - ($script:destH - $script:crabH / 2.0)))
        $newTop  = [Math]::Max($script:wa.Top, $newTop)
        $script:form.Location = New-Object System.Drawing.Point($newLeft, $newTop)
        Update-PetVisual
        $script:posX = [double]$newLeft
        $script:posY = [double]$newTop
        # Throw strength = the real cursor velocity at release
        $script:fallVX = [Math]::Max(-45.0, [Math]::Min(45.0, $script:cvX * 0.9))
        $script:vy     = [Math]::Max(-45.0, [Math]::Min(45.0, $script:cvY * 0.9))
        if ($newTop -lt ($script:bottomY - 4) -or [Math]::Abs($script:fallVX) -gt 1.5 -or $script:vy -lt -1.5) {
            Set-State 'fall' 9999
        } else {
            $script:form.Top = $script:bottomY
            $script:fallVX = 0
            $script:vy = 0
            Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
        }
    } else {
        $script:posX = [double]$script:form.Left
        $r = $script:rand.NextDouble()
        if ($r -lt 0.40)     { Set-State 'wave' 240 }
        elseif ($r -lt 0.75) { Set-State 'jump' 190 }
        else                 { Set-State 'dance' $script:rand.Next(280, 380) }
    }
})

# ---------- Right-click menu ----------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Renderer   = New-Object ClawdMenuRenderer
$menu.BackColor  = [System.Drawing.Color]::FromArgb(38, 36, 33)
$menu.ForeColor  = [System.Drawing.Color]::FromArgb(236, 231, 223)
$menu.ShowImageMargin = $false
$menu.Font       = New-Object System.Drawing.Font('Segoe UI', 9)
$miShadow = $menu.Items.Add('The Shadow')
$miShadow.Add_Click({ Start-Shadow })
$miClimb = $menu.Items.Add('Climb the Wall')
$miClimb.Add_Click({
    if (($script:state -eq 'idle' -or $script:state -eq 'walk') -and -not $script:onPlat -and $script:balMode -eq 'none') {
        $script:wantClimb = $true
        $cx2 = $script:form.Left + $script:formW / 2
        $script:dir = 1
        if (($cx2 - $script:wa.Left) -lt (($script:wa.Right - $cx2))) { $script:dir = -1 }   # toward the nearest wall
        Set-State 'walk' 6000
        $script:walkTotal = 6000
    }
})
$miShove = $menu.Items.Add('Drag the Window')
$miShove.Add_Click({
    if ($script:onPlat -and $script:fx -eq 'none' -and ($script:state -eq 'idle' -or $script:state -eq 'walk')) {
        $script:shoveDir = 1
        if ($script:rand.NextDouble() -lt 0.5) { $script:shoveDir = -1 }
        Start-Fx 'shove' 110
        Set-State 'idle' $script:rand.Next($script:idleMinT, $script:idleMaxT)
    }
})
$miPush = $menu.Items.Add('Push a Window')
$miPush.Add_Click({
    if ((-not $script:onPlat) -and $script:fx -eq 'none' -and ($script:state -eq 'idle' -or $script:state -eq 'walk') -and $script:balMode -eq 'none') {
        $pt = Find-PushTarget
        if ($null -ne $pt) { Start-Push $pt }
    }
})
$miStar = $menu.Items.Add('Meteor Shower')
$miStar.Add_Click({
    if (-not $script:starActive -and $script:state -ne 'fall' -and $script:state -ne 'balloon' -and -not $script:dragging) {
        Start-StarShow
    }
})
$miBal = $menu.Items.Add('Balloon Ride')
$miBal.Add_Click({
    if ($script:balMode -eq 'none' -and $script:state -ne 'fall' -and -not $script:dragging -and -not $script:onPlat) {
        Start-Balloon
    }
})
$miCode = $menu.Items.Add('Hello World!')
$miCode.Add_Click({ Set-State 'code' 380 })
$miDance = $menu.Items.Add('Dance')
$miDance.Add_Click({ Set-State 'dance' 340 })
$miWork = $menu.Items.Add('Working')
$miWork.Add_Click({ $script:lastBusy = 'work'; Set-State 'work' 460 })
$miCook = $menu.Items.Add('Cooking')
$miCook.Add_Click({ $script:lastBusy = 'cook'; Set-State 'cook' 460 })
$miDuck = $menu.Items.Add('Hide')
$miDuck.Add_Click({ Start-Fx 'duck' 300; Set-State 'idle' 500 })
$miDoze = $menu.Items.Add('Sleep')
$miDoze.Add_Click({ Start-Fx 'doze' 320; Set-State 'idle' 500 })
$miWave = $menu.Items.Add('Wave')
$miWave.Add_Click({ Set-State 'wave' 240 })
$null = $menu.Items.Add('-')
$exitItem = $menu.Items.Add('Bye Clawd (quit)')
$exitItem.Add_Click({ $script:form.Close() })
foreach ($it in $menu.Items) { $it.ForeColor = [System.Drawing.Color]::FromArgb(236, 231, 223) }
# Foreground the menu once it's shown so a click anywhere outside dismisses it
# (the pet window is NoActivate, which otherwise breaks click-away-to-close).
$menu.Add_Opened({ [ClawdWin]::SetForeground($menu.Handle.ToInt64()) })
$script:form.ContextMenuStrip = $menu

$script:selfHwnd = $script:form.Handle.ToInt64()
$script:supportY = [double]$script:bottomY
Set-State 'idle' 150
# Release the one-off sprite-processing garbage back to the OS before we settle in
[System.GC]::Collect()
[ClawdWin]::TrimMemory()
$script:timer.Start()
[System.Windows.Forms.Application]::Run($script:form)
$script:mutex.ReleaseMutex()

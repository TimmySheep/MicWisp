using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace MicWisp.Windows;

internal sealed class WindowsTray : IDisposable
{
    private const uint CallbackMessage = NativeWindow.WM_APP + 41;
    private const uint NotifyAdd = 0x00000000;
    private const uint NotifyDelete = 0x00000002;
    private const uint NotifyMessage = 0x00000001;
    private const uint NotifyIcon = 0x00000002;
    private const uint NotifyTip = 0x00000004;
    private const uint MouseLeftUp = 0x0202;
    private const uint MouseRightUp = 0x0205;
    private const uint MenuShow = 1001;
    private const uint MenuQuit = 1002;
    private readonly IntPtr _hwnd;
    private readonly Action _show;
    private readonly Action _quit;
    private readonly UIntPtr _subclassId = (UIntPtr)0x4D574953;
    private readonly SubclassProc _callback;
    private bool _disposed;

    public WindowsTray(IntPtr hwnd, Action show, Action quit)
    {
        _hwnd = hwnd;
        _show = show;
        _quit = quit;
        _callback = WindowProc;
        NativeWindow.SetWindowSubclass(hwnd, _callback, _subclassId, UIntPtr.Zero);
        var data = new NotifyIconData
        {
            Size = (uint)Marshal.SizeOf<NotifyIconData>(),
            Window = hwnd,
            Id = 1,
            Flags = NotifyMessage | NotifyIcon | NotifyTip,
            CallbackMessage = CallbackMessage,
            Icon = NativeWindow.LoadApplicationIcon(),
            Tip = Strings.Get("ProductName"),
        };
        if (!ShellNotifyIcon(NotifyAdd, ref data))
            throw new InvalidOperationException("Windows could not create the system tray icon.");
    }

    private IntPtr WindowProc(IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam, UIntPtr subclassId, UIntPtr referenceData)
    {
        if (message == CallbackMessage)
        {
            var mouse = unchecked((uint)lParam.ToInt64());
            if (mouse == MouseLeftUp) _show();
            else if (mouse == MouseRightUp) ShowMenu();
            return IntPtr.Zero;
        }
        if (message == NativeWindow.WM_COMMAND)
        {
            var command = unchecked((uint)wParam.ToUInt64()) & 0xFFFF;
            if (command == MenuShow) _show();
            else if (command == MenuQuit) _quit();
            return IntPtr.Zero;
        }
        if (message == NativeWindow.WM_CLOSE && MainWindowWindowClose()) return IntPtr.Zero;
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }

    private bool MainWindowWindowClose() => NativeWindow.HandleCloseMessage(_hwnd);

    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero) return;
        try
        {
            AppendMenu(menu, 0, MenuShow, Strings.Get("TrayShow"));
            AppendMenu(menu, 0, MenuQuit, Strings.Get("TrayQuit"));
            GetCursorPos(out var point);
            SetForegroundWindow(_hwnd);
            var command = TrackPopupMenu(menu, 0x0100, point.X, point.Y, 0, _hwnd, IntPtr.Zero);
            if (command == MenuShow) _show();
            else if (command == MenuQuit) _quit();
        }
        finally { DestroyMenu(menu); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        var data = new NotifyIconData { Size = (uint)Marshal.SizeOf<NotifyIconData>(), Window = _hwnd, Id = 1 };
        ShellNotifyIcon(NotifyDelete, ref data);
        RemoveWindowSubclass(_hwnd, _callback, _subclassId);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public uint Size;
        public IntPtr Window;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string? Tip;
        public uint State;
        public uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string? Info;
        public uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string? InfoTitle;
        public uint InfoFlags;
        public Guid ItemGuid;
        public IntPtr BalloonIcon;
    }

    private delegate IntPtr SubclassProc(IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam, UIntPtr subclassId, UIntPtr referenceData);

    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool ShellNotifyIcon(uint message, ref NotifyIconData data);
    [DllImport("comctl32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetWindowSubclass(IntPtr hwnd, SubclassProc callback, UIntPtr subclassId, UIntPtr referenceData);
    [DllImport("comctl32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool RemoveWindowSubclass(IntPtr hwnd, SubclassProc callback, UIntPtr subclassId);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool AppendMenu(IntPtr menu, uint flags, uint id, string text);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenu(IntPtr menu, uint flags, int x, int y, int reserved, IntPtr hwnd, IntPtr rect);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetCursorPos(out NativeWindow.Point point);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetActiveWindow();
}

internal static class NativeWindow
{
    public const uint WM_CLOSE = 0x0010;
    public const uint WM_COMMAND = 0x0111;
    public const uint WM_APP = 0x8000;
    private const int SW_HIDE = 0;
    private const int SW_SHOW = 5;
    private static Func<uint, bool>? _closeHandler;

    public static void RegisterCloseHandler(Func<uint, bool> callback) => _closeHandler = callback;
    public static bool HandleCloseMessage(IntPtr hwnd) => _closeHandler?.Invoke(WM_CLOSE) ?? false;
    public static void Hide(IntPtr hwnd) => ShowWindow(hwnd, SW_HIDE);
    public static void Show(IntPtr hwnd) => ShowWindow(hwnd, SW_SHOW);
    public static IntPtr LoadApplicationIcon() => LoadIcon(IntPtr.Zero, new IntPtr(32512));

    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X; public int Y; }
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll", EntryPoint = "LoadIconW")] private static extern IntPtr LoadIcon(IntPtr instance, IntPtr name);
}

using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using WinRT.Interop;

namespace MicWisp.Windows;

public sealed partial class MainWindow : Window
{
    private readonly BackendController _backend = App.Backend;
    private readonly IntPtr _hwnd;
    private readonly WindowsTray _tray;
    private bool _quitting;
    private string _selectedPage = "dashboard";

    public MainWindow()
    {
        InitializeComponent();
        Title = Strings.Get("ProductName");
        _hwnd = WindowNative.GetWindowHandle(this);
        _backend.AttachDispatcher(DispatcherQueue.GetForCurrentThread());
        NativeWindow.RegisterCloseHandler(HandleWindowMessage);
        BuildNavigation();
        ServiceButton.Click += ServiceButton_Click;
        _backend.PropertyChanged += Backend_PropertyChanged;
        Strings.LanguageChanged += LanguageChanged;
        _tray = new WindowsTray(_hwnd, ShowWindow, QuitFromTray);
        Navigation.SelectedItem = Navigation.MenuItems.FirstOrDefault();
        ShowPage("dashboard");
        RefreshChrome();
    }

    private void BuildNavigation()
    {
        Navigation.MenuItems.Clear();
        Navigation.MenuItems.Add(NavItem("dashboard", "NavDashboard", Symbol.Home));
        Navigation.MenuItems.Add(NavItem("connection", "NavConnection", Symbol.Globe));
        Navigation.MenuItems.Add(NavItem("audio", "NavAudio", Symbol.Audio));
        Navigation.MenuItems.Add(NavItem("about", "NavAbout", Symbol.Help));
        Navigation.PaneTitle = Strings.Get("ProductName");
    }

    private void LanguageChanged()
    {
        BuildNavigation();
        ShowPage(_selectedPage);
        RefreshChrome();
    }

    private static NavigationViewItem NavItem(string tag, string label, Symbol symbol) => new()
    {
        Tag = tag,
        Content = Strings.Get(label),
        Icon = new SymbolIcon(symbol),
    };

    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem item && item.Tag is string page)
            ShowPage(page);
    }

    private void ShowPage(string page)
    {
        _selectedPage = page;
        ContentFrame.Content = page switch
        {
            "connection" => new ConnectionPage(_backend),
            "audio" => new AudioPage(_backend),
            "about" => new AboutPage(_backend),
            _ => new DashboardPage(_backend),
        };
    }

    private async void ServiceButton_Click(object sender, RoutedEventArgs e)
    {
        ServiceButton.IsEnabled = false;
        try
        {
            if (_backend.CanStop) await _backend.StopAsync();
            else await _backend.StartAsync();
        }
        catch (Exception ex) { _backend.ShowError(ex.Message); }
        finally { ServiceButton.IsEnabled = true; RefreshChrome(); }
    }

    private void Backend_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(BackendController.Phase) or nameof(BackendController.IsReady) or nameof(BackendController.Error))
            RefreshChrome();
    }

    private void RefreshChrome()
    {
        StatusText.Text = _backend.Error ?? _backend.PhaseText;
        ServiceButton.Label = Strings.Get(_backend.CanStop ? "Stop" : "Start");
        ServiceButton.Icon = new SymbolIcon(_backend.CanStop ? Symbol.Stop : Symbol.Microphone);
        ServiceButton.IsEnabled = _backend.Phase != "Starting";
    }

    private void ShowWindow()
    {
        NativeWindow.Show(_hwnd);
        Activate();
    }

    private async void QuitFromTray()
    {
        if (_quitting) return;
        _quitting = true;
        await _backend.StopAsync();
        _tray.Dispose();
        _backend.Dispose();
        Application.Current.Exit();
    }

    private bool HandleWindowMessage(uint message)
    {
        if (message != NativeWindow.WM_CLOSE || _quitting) return false;
        NativeWindow.Hide(_hwnd);
        return true;
    }
}

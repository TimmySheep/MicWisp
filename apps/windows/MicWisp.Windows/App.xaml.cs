using Microsoft.UI.Xaml;

namespace MicWisp.Windows;

public partial class App : Application
{
    public static BackendController Backend { get; } = new();
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}

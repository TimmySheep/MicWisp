using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MicWisp.Windows;

internal sealed class ConnectionPage : Page
{
    private readonly BackendController _backend;
    private readonly ComboBox _mode = new() { MinWidth = 220 };
    private readonly NumberBox _port = new() { Minimum = 1, Maximum = 65534, Value = 8554, SmallChange = 1, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact };
    private readonly NumberBox _webPort = new() { Minimum = 1, Maximum = 65535, Value = 8443, SmallChange = 1, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact };
    private readonly TextBox _bindAddress = new() { Text = "0.0.0.0" };
    private readonly ToggleSwitch _autoBind = new() { IsOn = true };
    private readonly ToggleSwitch _muteSync = new() { IsOn = true };
    private readonly ComboBox _output = new() { MinWidth = 300 };
    private readonly TextBlock _adb = Ui.Note(Strings.Get("NoAdb"));
    private readonly TextBlock _addresses = Ui.Note("");
    private readonly TextBlock _services = Ui.Note(Strings.Get("NoServices"));
    private readonly TextBlock _virtualStatus = Ui.Note(Strings.Get("NotDetected"));
    private readonly TextBlock _result = Ui.Note("");
    private readonly Button _webInstructions = new() { Content = Strings.Get("Setup") };
    private readonly Button _browse = new() { Content = "mDNS" };
    private CancellationTokenSource? _browseCts;

    public ConnectionPage(BackendController backend)
    {
        _backend = backend;
        var root = Ui.Page(this, Strings.Get("ConnectionTitle"));
        _mode.Items.Add(new ComboBoxItem { Content = Strings.Get("Wifi"), Tag = "wifi" });
        _mode.Items.Add(new ComboBoxItem { Content = Strings.Get("Usb"), Tag = "usb" });
        _mode.Items.Add(new ComboBoxItem { Content = Strings.Get("Web"), Tag = "web" });
        _mode.SelectedIndex = ModeIndex(backend.Connection.Mode);
        root.Children.Add(Ui.Row(Strings.Get("Mode"), _mode));
        root.Children.Add(Ui.Row(Strings.Get("Port"), _port));
        root.Children.Add(Ui.Row(Strings.Get("WebPort"), _webPort));
        root.Children.Add(Ui.Row(Strings.Get("BindAddress"), _bindAddress));
        root.Children.Add(Ui.Row(Strings.Get("AutoBind"), _autoBind));
        root.Children.Add(Ui.Row(Strings.Get("MuteSync"), _muteSync));
        root.Children.Add(Ui.Row(Strings.Get("OutputDevice"), _output));
        root.Children.Add(Ui.Note(Strings.Get("OutputHint")));
        root.Children.Add(Ui.Note(Strings.Get("RestartHint")));
        var save = new Button { Content = Strings.Get("Apply"), Style = Application.Current.Resources["AccentButtonStyle"] as Style };
        save.Click += Save_Click;
        root.Children.Add(save);
        root.Children.Add(_result);

        Ui.Section(root, Strings.Get("LocalAddresses"));
        root.Children.Add(_addresses);
        Ui.Section(root, Strings.Get("Discovery"));
        root.Children.Add(Ui.Note(Strings.Get("DiscoveryHint")));
        _browse.Click += Browse_Click;
        root.Children.Add(_browse);
        root.Children.Add(_services);
        Ui.Section(root, Strings.Get("Usb"));
        root.Children.Add(Ui.Note(Strings.Get("UsbHint")));
        root.Children.Add(_adb);
        Ui.Section(root, Strings.Get("VirtualStatus"));
        root.Children.Add(_virtualStatus);
        _webInstructions.Click += (_, _) => OpenUrl(_backend.VirtualAudioUrl ?? "https://vb-audio.com/Cable/");
        root.Children.Add(_webInstructions);

        _mode.SelectionChanged += (_, _) => UpdateModeControls();
        Loaded += OnLoaded;
        Unloaded += (_, _) => { _backend.PropertyChanged -= BackendChanged; _browseCts?.Cancel(); };
        UpdateModeControls();
        UpdateReadOnlyData();
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        _backend.PropertyChanged += BackendChanged;
        try { await _backend.RefreshAsync(); }
        catch (Exception ex) { _result.Text = ex.Message; }
        UpdateReadOnlyData();
    }

    private void BackendChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => UpdateReadOnlyData();

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        if (_port.Value is < 1 or > 65534 || _webPort.Value is < 1 or > 65535)
        {
            _result.Text = "Ports are outside the supported range.";
            return;
        }
        var updated = new ServerPreferences
        {
            Mode = CurrentMode,
            Port = (ushort)_port.Value,
            WebPort = (ushort)_webPort.Value,
            BindAddress = _bindAddress.Text.Trim(),
            AutoBind = _autoBind.IsOn,
            MuteSync = _muteSync.IsOn,
            OutputDevice = (_output.SelectedItem as ComboBoxItem)?.Tag as string ?? "",
        };
        try
        {
            await _backend.ApplyConnectionAsync(updated);
            _result.Text = Strings.Get("RestartRequired");
        }
        catch (Exception ex) { _result.Text = ex.Message; _backend.ShowError(ex.Message); }
    }

    private async void Browse_Click(object sender, RoutedEventArgs e)
    {
        _browse.IsEnabled = false;
        _browseCts?.Cancel();
        _browseCts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        try
        {
            var services = await BackendController.BrowseMdnsAsync(_browseCts.Token);
            _backend.SetDiscoveredServices(services);
            _services.Text = services.Count == 0 ? Strings.Get("NoServices") : string.Join("\n", services);
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { _services.Text = ex.Message; }
        finally { _browse.IsEnabled = true; }
    }

    private string CurrentMode => (_mode.SelectedItem as ComboBoxItem)?.Tag as string ?? "wifi";

    private void UpdateModeControls()
    {
        var mode = CurrentMode;
        _port.Visibility = mode == "web" ? Visibility.Collapsed : Visibility.Visible;
        _webPort.Visibility = mode == "web" ? Visibility.Visible : Visibility.Collapsed;
        _bindAddress.Visibility = mode == "usb" || mode == "web" ? Visibility.Collapsed : Visibility.Visible;
        _autoBind.Visibility = mode == "usb" || mode == "web" ? Visibility.Collapsed : Visibility.Visible;
        _addresses.Visibility = mode == "wifi" ? Visibility.Visible : Visibility.Collapsed;
        _adb.Visibility = mode == "usb" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateReadOnlyData()
    {
        var prefs = _backend.Connection;
        if (_port.FocusState == Microsoft.UI.Xaml.FocusState.Unfocused) _port.Value = prefs.Port;
        if (_webPort.FocusState == Microsoft.UI.Xaml.FocusState.Unfocused) _webPort.Value = prefs.WebPort;
        if (_bindAddress.FocusState == Microsoft.UI.Xaml.FocusState.Unfocused) _bindAddress.Text = prefs.BindAddress;
        if (_mode.FocusState == Microsoft.UI.Xaml.FocusState.Unfocused) _mode.SelectedIndex = ModeIndex(prefs.Mode);
        _autoBind.IsOn = prefs.AutoBind;
        _muteSync.IsOn = prefs.MuteSync;
        _addresses.Text = _backend.LocalAddresses.Count == 0
            ? Strings.Get("NoAddresses")
            : string.Join("\n", _backend.LocalAddresses.Select(address => $"{address}:{prefs.Port}"));
        _services.Text = _backend.DiscoveredServices.Count == 0 ? Strings.Get("NoServices") : string.Join("\n", _backend.DiscoveredServices);
        _adb.Text = _backend.AdbDevices.Count == 0 ? Strings.Get("NoAdb") : string.Join("\n", _backend.AdbDevices);
        _virtualStatus.Text = _backend.VirtualAudioInstalled == true ? Strings.Get("Available") : Strings.Get("NotDetected");
        _webInstructions.Visibility = _backend.VirtualAudioInstalled == true ? Visibility.Collapsed : Visibility.Visible;
        if (_output.FocusState == Microsoft.UI.Xaml.FocusState.Unfocused)
        {
            var selected = Array.IndexOf(_backend.AudioDevices.ToArray(), prefs.OutputDevice);
            _output.Items.Clear();
            _output.Items.Add(new ComboBoxItem { Content = Strings.Get("DefaultOutput"), Tag = "" });
            foreach (var device in _backend.AudioDevices)
                _output.Items.Add(new ComboBoxItem { Content = device, Tag = device });
            _output.SelectedIndex = selected >= 0 ? selected + 1 : 0;
        }
        UpdateModeControls();
    }

    private static int ModeIndex(string mode) => mode switch { "usb" => 1, "web" => 2, _ => 0 };
    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { }
    }
}

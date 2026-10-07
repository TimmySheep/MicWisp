using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MicWisp.Windows;

internal sealed class DashboardPage : Page
{
    private readonly BackendController _backend;
    private readonly TextBlock _device = Ui.Value(Strings.Get("NoDevice"));
    private readonly TextBlock _metrics = Ui.Value();
    private readonly TextBlock _diagnostic = Ui.Note("");
    private readonly ProgressBar _level = new() { Minimum = 0, Maximum = 1, Height = 18 };
    private readonly ToggleSwitch _muted = new() { IsOn = false };
    private readonly ToggleSwitch _monitoring = new() { IsOn = false };
    private bool _updating;

    public DashboardPage(BackendController backend)
    {
        _backend = backend;
        var root = Ui.Page(this, Strings.Get("ServiceTitle"));
        Ui.Section(root, Strings.Get("Device"));
        root.Children.Add(_device);
        root.Children.Add(Ui.Note(Strings.Get("ConnectHint")));
        Ui.Section(root, Strings.Get("Level"));
        root.Children.Add(Ui.Row(Strings.Get("Level"), _level));
        Ui.Section(root, Strings.Get("Metrics"));
        root.Children.Add(_metrics);
        var mutedRow = Ui.Row(Strings.Get("Muted"), _muted);
        var monitoringRow = Ui.Row(Strings.Get("Monitoring"), _monitoring);
        root.Children.Add(mutedRow);
        root.Children.Add(monitoringRow);
        root.Children.Add(_diagnostic);

        _muted.Toggled += async (_, _) =>
        {
            if (_updating) return;
            try { await _backend.SetMutedAsync(_muted.IsOn); }
            catch (Exception ex) { _backend.ShowError(ex.Message); }
        };
        _monitoring.Toggled += async (_, _) =>
        {
            if (_updating) return;
            try { await _backend.SetMonitoringAsync(_monitoring.IsOn); }
            catch (Exception ex) { _backend.ShowError(ex.Message); }
        };
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        Update();
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        _backend.PropertyChanged += BackendChanged;
        try { await _backend.SetSpectrumAsync(false); }
        catch (Exception ex) { _backend.ShowError(ex.Message); }
        Update();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e) => _backend.PropertyChanged -= BackendChanged;
    private void BackendChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => Update();

    private void Update()
    {
        _updating = true;
        if (_backend.Device is { } device)
        {
            _device.Text = $"{device.Name} · {device.Ip} · {Strings.Get("PhoneLatency")}: {device.Latency} ms";
        }
        else _device.Text = Strings.Get("NoDevice");
        _level.Value = _backend.AudioFraction;
        _metrics.Text = string.Join("\n", new[]
        {
            $"{Strings.Get("Latency")}: {_backend.Latency} ms",
            $"{Strings.Get("NetworkLatency")}: {_backend.NetworkLatency} ms",
            $"{Strings.Get("Jitter")}: {_backend.Jitter:0.0} ms",
            $"{Strings.Get("Loss")}: {_backend.PacketLoss * 100:0.00}%",
            $"{Strings.Get("Buffer")}: {_backend.BufferDuration} ms",
            $"{Strings.Get("Bitrate")}: {_backend.Bitrate}",
            $"{Strings.Get("SampleRate")}: {_backend.SampleRate} Hz",
            $"{Strings.Get("WebClients")}: {_backend.WebClientCount}",
        });
        _muted.IsOn = _backend.IsMuted;
        _monitoring.IsOn = _backend.IsMonitoring;
        _muted.IsEnabled = _backend.IsReady;
        _monitoring.IsEnabled = _backend.IsReady;
        _diagnostic.Text = _backend.Error ?? _backend.Diagnostic ?? "";
        _diagnostic.Visibility = string.IsNullOrWhiteSpace(_diagnostic.Text) ? Visibility.Collapsed : Visibility.Visible;
        _updating = false;
    }
}

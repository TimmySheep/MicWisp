using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MicWisp.Windows;

internal sealed class AudioPage : Page
{
    private readonly BackendController _backend;
    private bool _initializing;
    private readonly StackPanel _chain = new() { Spacing = 8 };

    public AudioPage(BackendController backend)
    {
        _backend = backend;
        _initializing = true;
        var root = Ui.Page(this, Strings.Get("AudioTitle"));
        AddToggle(root, "Noise", value => _backend.Dsp.NsEnabled = value, () => _backend.Dsp.NsEnabled);
        AddPicker(root, "NoiseType", new[] { "PureVox", "RNNoise", "Speexdsp" }, value => _backend.Dsp.NsType = value, () => _backend.Dsp.NsType, !_backend.Dsp.NsEnabled);
        AddSlider(root, "Intensity", 0, 100, value => _backend.Dsp.NsIntensity = (float)value, () => _backend.Dsp.NsIntensity, !_backend.Dsp.NsEnabled);
        AddSlider(root, "Gain", -50, 50, value => _backend.Dsp.Gain = (float)value, () => _backend.Dsp.Gain);
        AddToggle(root, "Aec", value => _backend.Dsp.AecEnabled = value, () => _backend.Dsp.AecEnabled);
        AddToggle(root, "Dereverb", value => _backend.Dsp.DereverbEnabled = value, () => _backend.Dsp.DereverbEnabled);
        AddSlider(root, "DereverbLevel", 0, 100, value => _backend.Dsp.DereverbLevel = (float)value, () => _backend.Dsp.DereverbLevel, !_backend.Dsp.DereverbEnabled);
        AddToggle(root, "Agc", value => _backend.Dsp.AgcEnabled = value, () => _backend.Dsp.AgcEnabled);
        AddSlider(root, "AgcTarget", 0, 32767, value => _backend.Dsp.AgcTarget = (float)value, () => _backend.Dsp.AgcTarget, !_backend.Dsp.AgcEnabled);
        AddSlider(root, "AgcAttack", 1, 100, value => _backend.Dsp.AgcAttack = (float)value, () => _backend.Dsp.AgcAttack, !_backend.Dsp.AgcEnabled);
        AddSlider(root, "AgcDecay", 1, 100, value => _backend.Dsp.AgcDecay = (float)value, () => _backend.Dsp.AgcDecay, !_backend.Dsp.AgcEnabled);
        AddToggle(root, "Vad", value => _backend.Dsp.VadEnabled = value, () => _backend.Dsp.VadEnabled);
        AddSlider(root, "VadThreshold", -100, 0, value => _backend.Dsp.VadThreshold = (float)value, () => _backend.Dsp.VadThreshold, !_backend.Dsp.VadEnabled);
        AddSlider(root, "OutputBuffer", 100, 1200, value => _backend.Dsp.OutputBufferMs = (uint)value, () => _backend.Dsp.OutputBufferMs);

        Ui.Section(root, Strings.Get("Equalizer"));
        AddToggle(root, "Equalizer", value => _backend.Dsp.Equalizer.Enabled = value, () => _backend.Dsp.Equalizer.Enabled);
        AddSlider(root, "Preamp", -12, 12, value => _backend.Dsp.Equalizer.PreAmp = (float)value, () => _backend.Dsp.Equalizer.PreAmp, !_backend.Dsp.Equalizer.Enabled);
        var bands = new[] { 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 };
        for (var index = 0; index < bands.Length; index++)
        {
            var bandIndex = index;
            var slider = new Slider { Minimum = -12, Maximum = 12, StepFrequency = 0.5, Value = ReadBand(bandIndex), IsEnabled = _backend.Dsp.Equalizer.Enabled };
            slider.ValueChanged += (_, args) => UpdateDsp(() => WriteBand(bandIndex, args.NewValue));
            root.Children.Add(Ui.Row(bands[index] >= 1000 ? $"{bands[index] / 1000} kHz" : $"{bands[index]} Hz", slider));
        }

        Ui.Section(root, Strings.Get("Chain"));
        root.Children.Add(_chain);
        root.Children.Add(Ui.Note(Strings.Get("DspApplied")));
        UpdateChain();
        _initializing = false;
        Loaded += OnLoaded;
        Unloaded += (_, _) => _backend.PropertyChanged -= BackendChanged;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        _backend.PropertyChanged += BackendChanged;
        try
        {
            await _backend.RefreshAsync();
            await _backend.SetSpectrumAsync(true);
        }
        catch (Exception ex) { _backend.ShowError(ex.Message); }
        UpdateChain();
    }

    private void BackendChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(BackendController.Dsp)) UpdateChain();
    }

    private void AddToggle(StackPanel root, string key, Action<bool> setter, Func<bool> getter)
    {
        var toggle = new ToggleSwitch { IsOn = getter() };
        toggle.Toggled += (_, _) =>
        {
            if (_initializing) return;
            UpdateDsp(() => setter(toggle.IsOn));
        };
        root.Children.Add(Ui.Row(Strings.Get(key), toggle));
    }

    private void AddPicker(StackPanel root, string key, IReadOnlyList<string> items, Action<string> setter, Func<string> getter, bool disabled)
    {
        var picker = new ComboBox { IsEnabled = !disabled, MinWidth = 220 };
        foreach (var item in items) picker.Items.Add(item);
        picker.SelectedItem = getter();
        picker.SelectionChanged += (_, _) =>
        {
            if (!_initializing && picker.SelectedItem is string value) UpdateDsp(() => setter(value));
        };
        root.Children.Add(Ui.Row(Strings.Get(key), picker));
    }

    private void AddSlider(StackPanel root, string key, double min, double max, Action<double> setter, Func<double> getter, bool disabled = false)
    {
        var slider = new Slider { Minimum = min, Maximum = max, Value = Math.Clamp(getter(), min, max), IsEnabled = !disabled, StepFrequency = (max - min) > 1000 ? 100 : 1 };
        slider.ValueChanged += (_, args) =>
        {
            if (!_initializing) UpdateDsp(() => setter(args.NewValue));
        };
        root.Children.Add(Ui.Row(Strings.Get(key), slider));
    }

    private void UpdateDsp(Action change)
    {
        change();
        _backend.UpdateDsp(_backend.Dsp);
    }

    private float ReadBand(int index) => _backend.Dsp.Equalizer.Gains.Count > index ? _backend.Dsp.Equalizer.Gains[index] : 0;

    private void WriteBand(int index, double value)
    {
        while (_backend.Dsp.Equalizer.Gains.Count < 10) _backend.Dsp.Equalizer.Gains.Add(0);
        _backend.Dsp.Equalizer.Gains[index] = (float)value;
        _backend.UpdateDsp(_backend.Dsp);
    }

    private void UpdateChain()
    {
        _chain.Children.Clear();
        for (var index = 0; index < _backend.Dsp.ProcessingChain.Count; index++)
        {
            var current = index;
            var node = _backend.Dsp.ProcessingChain[index];
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
            row.Children.Add(new TextBlock { Text = NodeName(node), Width = 220, VerticalAlignment = VerticalAlignment.Center });
            var up = new Button { Content = Strings.Get("MoveUp"), IsEnabled = index > 0 };
            up.Click += (_, _) => MoveNode(current, -1);
            var down = new Button { Content = Strings.Get("MoveDown"), IsEnabled = index < _backend.Dsp.ProcessingChain.Count - 1 };
            down.Click += (_, _) => MoveNode(current, 1);
            row.Children.Add(up); row.Children.Add(down); _chain.Children.Add(row);
        }
    }

    private void MoveNode(int index, int delta)
    {
        var target = index + delta;
        if (target < 0 || target >= _backend.Dsp.ProcessingChain.Count) return;
        (_backend.Dsp.ProcessingChain[index], _backend.Dsp.ProcessingChain[target]) = (_backend.Dsp.ProcessingChain[target], _backend.Dsp.ProcessingChain[index]);
        UpdateDsp(() => { });
        UpdateChain();
    }

    private static string NodeName(string node) => node switch
    {
        "NoiseReduction" => Strings.Get("Noise"),
        "Dereverb" => Strings.Get("Dereverb"),
        "Equalizer" => Strings.Get("Equalizer"),
        "Amplifier" => Strings.Get("Gain"),
        "AGC" => Strings.Get("Agc"),
        "VAD" => Strings.Get("Vad"),
        "AEC" => Strings.Get("Aec"),
        _ => node,
    };
}

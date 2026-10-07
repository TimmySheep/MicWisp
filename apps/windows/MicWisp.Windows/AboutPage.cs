using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MicWisp.Windows;

internal sealed class AboutPage : Page
{
    private readonly BackendController _backend;
    private readonly ToggleSwitch _startup = new();
    private bool _loadingStartup;

    public AboutPage(BackendController backend)
    {
        _backend = backend;
        var root = Ui.Page(this, Strings.Get("AboutTitle"));
        root.Children.Add(Ui.Value(Strings.Get("ProductName")));
        root.Children.Add(Ui.Note($"{Strings.Get("Version")}: 0.1.0"));
        root.Children.Add(Ui.Note("Copyright (C) 2026 TimmySheep"));
        root.Children.Add(Ui.Note("Upstream backend copyright (C) 2026 LanRhyme"));
        root.Children.Add(Ui.Note(Strings.Get("IndependentNotice")));
        root.Children.Add(Ui.Note(Strings.Get("LicenseNotice")));
        var gpl = new Button { Content = Strings.Get("OpenGPL") };
        gpl.Click += (_, _) => OpenLicense("GPL-3.0.txt");
        root.Children.Add(gpl);
        var upstream = new Button { Content = Strings.Get("OpenUpstream") };
        upstream.Click += (_, _) => OpenLicense("UPSTREAM-LICENSE.txt");
        root.Children.Add(upstream);

        Ui.Section(root, Strings.Get("Settings"));
        var language = new ComboBox { MinWidth = 220 };
        language.Items.Add(new ComboBoxItem { Content = Strings.Get("System"), Tag = "system" });
        language.Items.Add(new ComboBoxItem { Content = Strings.Get("English"), Tag = "en" });
        language.Items.Add(new ComboBoxItem { Content = Strings.Get("Chinese"), Tag = "zh" });
        var savedLanguage = Windows.Storage.ApplicationData.Current.LocalSettings.Values["language"] as string ?? "system";
        language.SelectedIndex = savedLanguage switch { "en" => 1, "zh" => 2, _ => 0 };
        language.SelectionChanged += (_, _) =>
        {
            if (language.SelectedItem is ComboBoxItem item && item.Tag is string value) Strings.SetLanguage(value);
        };
        root.Children.Add(Ui.Row(Strings.Get("Language"), language));
        root.Children.Add(Ui.Row(Strings.Get("LaunchAtLogin"), _startup));
        root.Children.Add(Ui.Note(Strings.Get("ExplicitStart")));
        _startup.Toggled += Startup_Toggled;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            var task = await Windows.ApplicationModel.StartupTask.GetAsync("MicWispStartup");
            _loadingStartup = true;
            _startup.IsOn = task.State is Windows.ApplicationModel.StartupTaskState.Enabled or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
            _loadingStartup = false;
        }
        catch (Exception ex) { _loadingStartup = false; _backend.ShowError(ex.Message); }
    }

    private async void Startup_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loadingStartup) return;
        _startup.IsEnabled = false;
        try { await _backend.SetLaunchAtLoginAsync(_startup.IsOn); }
        catch (Exception ex) { _backend.ShowError(ex.Message); _startup.IsOn = false; }
        finally { _startup.IsEnabled = true; }
    }

    private void OpenLicense(string file)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "Licenses", file);
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch (Exception ex) { _backend.ShowError(ex.Message); }
    }
}

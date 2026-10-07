using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MicWisp.Windows;

internal static class Ui
{
    public static StackPanel Page(Page page, string title)
    {
        var content = new StackPanel { Spacing = 18, MaxWidth = 980, Padding = new Thickness(28) };
        content.Children.Add(new TextBlock { Text = title, Style = Application.Current.Resources["TitleTextBlockStyle"] as Style, TextWrapping = TextWrapping.Wrap });
        page.Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        return content;
    }

    public static void Section(StackPanel root, string title)
    {
        root.Children.Add(new Border
        {
            Margin = new Thickness(0, 10, 0, 2),
            Padding = new Thickness(0, 0, 0, 6),
            BorderBrush = (Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = new TextBlock { Text = title, FontSize = 18, FontWeight = Windows.UI.Text.FontWeights.SemiBold },
        });
    }

    public static StackPanel Row(string label, UIElement control)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 18, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(new TextBlock { Text = label, Width = 260, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap });
        if (control is FrameworkElement element) element.MinWidth = Math.Max(element.MinWidth, 220);
        row.Children.Add(control);
        return row;
    }

    public static TextBlock Note(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        FontSize = 13,
    };

    public static TextBlock Value(string text = "—") => new()
    {
        Text = text,
        FontSize = 19,
        FontWeight = Windows.UI.Text.FontWeights.SemiBold,
        TextWrapping = TextWrapping.Wrap,
    };
}

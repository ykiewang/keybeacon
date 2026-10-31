using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace KeyBeacon.App.Ui;

public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is Visibility.Visible;
}

public sealed class NonEmptyToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is string s && !string.IsNullOrEmpty(s) ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Active modifier chip fill: highlighted when pressed, subtle otherwise.</summary>
public sealed class ActiveToBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush Active = new(Color.FromRgb(0x3D, 0x7E, 0xFF));
    private static readonly SolidColorBrush Inactive = new(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF));

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Active : Inactive;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class ActiveToTextConverter : IValueConverter
{
    private static readonly SolidColorBrush Active = new(Colors.White);
    private static readonly SolidColorBrush Inactive = new(Color.FromArgb(0x88, 0xFF, 0xFF, 0xFF));

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Active : Inactive;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

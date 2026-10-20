import QtQuick 2.15
import Lomiri.Components 1.3

// Background of a QQuickControls Dialog that follows the app palette.
// QQuickControls' default background uses the application palette, which does
// not know about the app's light / dark / OLED colour modes.
Rectangle {
    property var appTheme

    color: appTheme && appTheme.colors ? appTheme.colors.surface : "#FFFFFF"
    radius: units.gu(1)
    border.width: units.dp(1)
    border.color: appTheme && appTheme.colors ? appTheme.colors.divider : "#E0E0E0"
}

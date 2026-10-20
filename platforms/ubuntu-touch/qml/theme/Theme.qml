import QtQuick 2.15
import Lomiri.Components 1.3

// Central color/metric source for the Ubuntu Touch UI.
// Mirrors the Flutter ThemeSettings:
//   mode      -> ThemeMode       ("system" | "light" | "dark")
//   colorMode -> ColorMode       ("system" | "localsend" | "oled" | "yaru" | "custom")
// "system" uses the Lomiri palette, which Main.qml reads from the MainView's
// theme (this object is a QtObject, so it has no attached `Theme` itself).
QtObject {
    id: theme

    property string mode: "system"
    property string colorMode: "localsend"
    property color customColor: "#009688"

    /// Lomiri's background is dark (filled in by Main.qml).
    property bool systemDark: false

    /// Lomiri's accent color (filled in by Main.qml).
    property color systemAccent: "#00695C"

    /// OLED always uses the dark palette, matching Flutter's ThemeMode.dark.
    readonly property bool dark: mode === "dark" || (mode === "system" && systemDark) || colorMode === "oled"

    readonly property color primary: {
        if (colorMode === "system")
            return dark ? Qt.lighter(systemAccent, 1.45) : systemAccent
        if (colorMode === "custom")
            return dark ? Qt.lighter(customColor, 1.6) : Qt.darker(customColor, 1.05)
        if (colorMode === "yaru")
            return dark ? "#F7A57C" : "#E95420"
        if (colorMode === "oled")
            return "#4DB6AC"
        return dark ? "#4DB6AC" : "#00695C"
    }

    // JS object literals are used instead of nested QtObject blocks:
    // inline QtObject inside a readonly property does not reliably
    // materialize on Qt 5.15, leaving colors/metrics as undefined.
    readonly property var colors: {
        var background, surface, surfaceTint, surfaceText, surfaceTextMuted, divider;

        if (colorMode === "oled") {
            background = "#000000";
            surface = "#050505";
            surfaceTint = "#141414";
            surfaceText = "#F2F2F2";
            surfaceTextMuted = "#9AA0A6";
            divider = "#232323";
        } else if (colorMode === "yaru") {
            if (dark) {
                background = "#1C1C1C";
                surface = "#262626";
                surfaceTint = "#303030";
                surfaceText = "#F5F5F5";
                surfaceTextMuted = "#B3B3B3";
                divider = "#3A3A3A";
            } else {
                background = "#FAFAFA";
                surface = "#FFFFFF";
                surfaceTint = "#F1EDEA";
                surfaceText = "#2C2C2C";
                surfaceTextMuted = "#6D6D6D";
                divider = "#DEDEDE";
            }
        } else {
            if (dark) {
                background = "#111214";
                surface = "#1B1D21";
                surfaceTint = "#23262B";
                surfaceText = "#F2F2F2";
                surfaceTextMuted = "#9AA0A6";
                divider = "#2A2D31";
            } else {
                background = "#F6F6F6";
                surface = "#FFFFFF";
                surfaceTint = "#ECEFF1";
                surfaceText = "#1B1D21";
                surfaceTextMuted = "#5F6368";
                divider = "#E0E0E0";
            }
        }

        return {
            background: background,
            surface: surface,
            surfaceTint: surfaceTint,
            primary: theme.primary,
            primaryText: theme.dark ? "#0B0B0B" : "#FFFFFF",
            surfaceText: surfaceText,
            surfaceTextMuted: surfaceTextMuted,
            divider: divider,
            danger: theme.dark ? "#F28B82" : "#C0392B",
            warning: theme.dark ? "#FFB74D" : "#C77700",
            success: theme.dark ? "#81C995" : "#2E7D32"
        };
    }

    readonly property var metrics: ({
        pagePadding:      units.gu(2),
        cardRadius:       units.gu(0.6),
        touchTarget:      units.gu(6),
        cardMarginH:      units.gu(2),
        cardMarginB:      units.gu(1),
        sectionSpacing:   units.gu(1.5),
        bottomNavHeight:  units.gu(7),
        bigButtonMinWidth: units.gu(18)
    })

    /// Blend `overlay` into `base` by `factor` (0..1), used for tinted chips.
    function blend(base, overlay, factor) {
        return Qt.rgba(
            base.r * (1 - factor) + overlay.r * factor,
            base.g * (1 - factor) + overlay.g * factor,
            base.b * (1 - factor) + overlay.b * factor,
            base.a * (1 - factor) + overlay.a * factor);
    }
}

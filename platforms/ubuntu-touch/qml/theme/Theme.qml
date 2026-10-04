import QtQuick 2.15

QtObject {
    id: theme

    // Bound from Main.qml to settingsController.{theme, colorMode, customColor}.
    property string mode: "system"        // "system" | "light" | "dark"
    property string colorMode: "localsend" // "system" | "localsend" | "oled" | "yaru" | "custom"
    property color  customColor: "#009688"

    // Resolved dark flag.
    // For "system" we default to light until Lomiri system theme
    // detection is wired (TODO: read from Ubuntu.SystemSettings).
    readonly property bool dark: {
        if (mode === "dark") return true
        if (mode === "light") return false
        return false // "system" fallback
    }

    readonly property Colors  colors:  Colors {
        dark: theme.dark
        colorMode: theme.colorMode
        customColor: theme.customColor
    }
    readonly property Metrics metrics: Metrics {}
}
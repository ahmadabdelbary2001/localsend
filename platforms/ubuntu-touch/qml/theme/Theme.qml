import QtQuick 2.15

QtObject {
    id: theme

    property string mode: "system"        // "system" | "light" | "dark"
    property string colorMode: "localsend" // "system" | "localsend" | "oled" | "yaru" | "custom"
    property color  customColor: "#009688"

    // TODO: when mode === "system", read from Lomiri system settings.
    // For now, default to light.
    readonly property bool dark: mode === "dark"

    readonly property Colors  colors:  Colors {
        dark: theme.dark
        colorMode: theme.colorMode
        customColor: theme.customColor
    }
    readonly property Metrics metrics: Metrics {}
}
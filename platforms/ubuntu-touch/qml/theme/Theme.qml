import QtQuick 2.15

QtObject {
    id: theme

    // Mirrors Flutter's settingsProvider.theme + colorMode.
    // Values: "system" | "light" | "dark"
    property string mode: "system"

    // Values: "localsend" | "oled" | "custom" | "yaru"
    // (dynamic is Android-only; yaru is a desktop variant, kept for parity)
    property string colorMode: "localsend"

    // Hex string, used when colorMode === "custom"
    property color customColor: "#009688"

    // Resolved by Rust once settings load. Defaults to light.
    property bool dark: false

    property Colors  colors:  Colors  { dark: theme.dark; colorMode: theme.colorMode; customColor: theme.customColor }
    property Metrics metrics: Metrics {}

    onModeChanged: _recompute()
    Component.onCompleted: _recompute()

    function _recompute() {
        if (mode === "dark")      dark = true
        else if (mode === "light") dark = false
        // "system": leave dark as-is; Rust updates it when the platform reports a change.
    }
}
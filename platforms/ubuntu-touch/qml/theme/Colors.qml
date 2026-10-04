import QtQuick 2.15

QtObject {
    id: colors

    property bool   dark: false
    property string colorMode: "localsend"
    property color  customColor: "#009688"

    // Base palette derived from the seed used by Flutter (teal → #009688).
    // A full Material-3 color generation is out of scope for this skeleton.
    // TODO(theme): generate the palette from customColor via a Material-3 algorithm.
    readonly property color _primary:      "#00695C" // teal[800]
    readonly property color _primaryLight: "#4DB6AC" // teal[300]

    // Resolved values
    readonly property color background:     dark ? "#111214" : "#F6F6F6"
    readonly property color surface:        colorMode === "oled" && dark ? "#000000"
                                            : (dark ? "#1B1D21" : "#FFFFFF")
    readonly property color surfaceTint:    dark ? "#23262B" : "#ECEFF1"
    readonly property color primary:        dark ? _primaryLight : _primary
    readonly property color onPrimary:      dark ? "#001F1A" : "#FFFFFF"
    readonly property color onSurface:      dark ? "#F2F2F2" : "#1B1D21"
    readonly property color onSurfaceMuted: dark ? "#9AA0A6" : "#5F6368"
    readonly property color divider:        dark ? "#2A2D31" : "#E0E0E0"
    readonly property color danger:         "#C0392B"
    readonly property color warning:        "#FF9800" // Flutter: Colors.orange
}
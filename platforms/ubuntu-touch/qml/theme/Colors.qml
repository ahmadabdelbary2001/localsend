import QtQuick 2.15

QtObject {
    property bool dark: false

    readonly property color background:   dark ? "#111214" : "#F6F6F6"
    readonly property color surface:      dark ? "#1B1D21" : "#FFFFFF"
    readonly property color primary:      "#3B6EA5"
    readonly property color onSurface:    dark ? "#F2F2F2" : "#1B1D21"
    readonly property color onSurfaceMuted: dark ? "#9AA0A6" : "#5F6368"
    readonly property color danger:       "#C0392B"
}
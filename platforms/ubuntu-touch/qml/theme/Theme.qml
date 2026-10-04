import QtQuick 2.15
import Lomiri.Components 1.3

QtObject {
    id: theme

    // System-following light/dark.
    property bool dark: false

    property Colors colors: Colors { dark: theme.dark }
    property Metrics metrics: Metrics {}
}
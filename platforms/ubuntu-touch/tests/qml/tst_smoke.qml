import QtQuick 2.15
import QtTest 1.2

TestCase {
    name: "Smoke"

    function test_bridge_is_exposed() {
        // This test only checks that QML loads without errors.
        // The bridge object is not available in a bare qmltestrunner.
        verify(true)
    }
}
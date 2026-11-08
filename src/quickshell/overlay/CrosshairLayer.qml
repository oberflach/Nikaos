import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

// Always-on crosshair drawn at screen centre. Lives outside the widget
// overlay so it keeps working once the overlay is closed (that is the whole
// point of it), and costs nothing while disabled.
Scope {
    id: crosshairScope

    property var settings: Config.getSetting("crosshair", {
        "enabled": false, "style": "cross", "size": 18, "thickness": 2, "color": "#a6e3a1", "gap": 4
    })

    Connections {
        target: Config
        function onSettingsLoaded() {
            crosshairScope.settings = Config.getSetting("crosshair", {
                "enabled": false, "style": "cross", "size": 18, "thickness": 2, "color": "#a6e3a1", "gap": 4
            });
        }
    }

    readonly property bool enabled: settings.enabled === true

    LazyLoader {
        active: crosshairScope.enabled

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: chWindow
                required property var modelData
                screen: modelData

                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                visible: true

                WlrLayershell.namespace: "qs-crosshair"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // Never steal clicks from what is underneath.
                mask: Region {}

                readonly property var cfg: crosshairScope.settings
                readonly property real chSize: Scaler.s(cfg.size || 18)
                readonly property real chThickness: Math.max(1, Scaler.s(cfg.thickness || 2))
                readonly property real chGap: Scaler.s(cfg.gap !== undefined ? cfg.gap : 4)
                readonly property color chColor: cfg.color || "#a6e3a1"

                Item {
                    anchors.centerIn: parent
                    width: chWindow.chSize * 2
                    height: chWindow.chSize * 2

                    // Cross arms
                    Repeater {
                        model: chWindow.cfg.style === "cross" ? 4 : 0

                        delegate: Rectangle {
                            required property int index
                            readonly property bool horizontal: index < 2
                            color: chWindow.chColor
                            antialiasing: true

                            width: horizontal ? chWindow.chSize - chWindow.chGap : chWindow.chThickness
                            height: horizontal ? chWindow.chThickness : chWindow.chSize - chWindow.chGap

                            x: horizontal
                                ? (index === 0 ? parent.width / 2 - chWindow.chGap - width : parent.width / 2 + chWindow.chGap)
                                : parent.width / 2 - width / 2
                            y: horizontal
                                ? parent.height / 2 - height / 2
                                : (index === 2 ? parent.height / 2 - chWindow.chGap - height : parent.height / 2 + chWindow.chGap)
                        }
                    }

                    // Centre dot
                    Rectangle {
                        visible: chWindow.cfg.style === "dot" || chWindow.cfg.style === "circle"
                        anchors.centerIn: parent
                        width: chWindow.chThickness * 2
                        height: width
                        radius: width / 2
                        color: chWindow.chColor
                        antialiasing: true
                    }

                    // Ring
                    Rectangle {
                        visible: chWindow.cfg.style === "circle"
                        anchors.centerIn: parent
                        width: chWindow.chSize
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: chWindow.chColor
                        border.width: chWindow.chThickness
                        antialiasing: true
                    }
                }
            }
        }
    }
}

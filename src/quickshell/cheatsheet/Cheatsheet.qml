import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../reusables"
import "../"

// Keybind cheatsheet (SUPER + /). Reads the live bind table from Hyprland so
// it can never drift from the actual config, and groups it by the
// "Category: action" convention used in keybinds.lua.
Scope {
    id: cheatsheetScope

    property bool isOpen: false

    onIsOpenChanged: {
        if (isOpen) bindsProc.running = true;
    }

    property var categories: []

    function modmaskToKeys(mask) {
        let mods = [];
        if (mask & 64) mods.push("SUPER");
        if (mask & 4) mods.push("CTRL");
        if (mask & 8) mods.push("ALT");
        if (mask & 1) mods.push("SHIFT");
        return mods;
    }

    function prettifyKey(key) {
        if (!key) return "";
        if (key.indexOf("mouse:") === 0) {
            if (key === "mouse:272") return I18n.t("cheatsheet.keys.leftclick");
            if (key === "mouse:273") return I18n.t("cheatsheet.keys.rightclick");
            if (key === "mouse:274") return I18n.t("cheatsheet.keys.middleclick");
            return I18n.t("cheatsheet.keys.mouse");
        }
        const map = {
            "mouse_up": "Scroll ↑", "mouse_down": "Scroll ↓",
            "Page_Up": "Page ↑", "Page_Down": "Page ↓",
            "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
            "RETURN": "Enter", "Return": "Enter", "Escape": "Esc",
            "Slash": "/", "Period": ".", "Comma": ",",
            "Print": "Print", "space": "Space"
        };
        return map[key] || key;
    }

    function parseBinds(raw) {
        let list = [];
        try { list = JSON.parse(raw); } catch (e) { return; }

        let groups = {};
        for (let i = 0; i < list.length; i++) {
            let b = list[i];
            let desc = String(b.description || "").trim();
            if (desc === "") continue;

            let category = I18n.t("cheatsheet.other");
            let action = desc;
            let sep = desc.indexOf(":");
            if (sep > 0) {
                category = desc.substring(0, sep).trim();
                action = desc.substring(sep + 1).trim();
            }

            let combo = cheatsheetScope.modmaskToKeys(b.modmask);
            combo.push(cheatsheetScope.prettifyKey(b.key));

            if (!groups[category]) groups[category] = [];
            groups[category].push({ "keys": combo, "action": action });
        }

        let out = [];
        for (let name in groups) {
            out.push({ "name": name, "binds": groups[name] });
        }
        out.sort((a, b) => b.binds.length - a.binds.length);
        cheatsheetScope.categories = out;
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            id: bindsOut
            onStreamFinished: cheatsheetScope.parseBinds(bindsOut.text)
        }
    }

    LazyLoader {
        active: cheatsheetScope.isOpen

        PanelWindow {
            id: sheetWindow
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            visible: true

            WlrLayershell.namespace: "qs-cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            screen: Quickshell.cursorScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function s(val) { return Scaler.s(val); }

            property string filterText: ""

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(ThemeBackend.crust, 0.6)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 180 } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: cheatsheetScope.isOpen = false
                }
            }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(parent.width - sheetWindow.s(80), sheetWindow.s(1180))
                height: Math.min(parent.height - sheetWindow.s(80), sheetWindow.s(760))
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.base, 0.98)
                border.color: ThemeBackend.surface1
                border.width: 1

                scale: 0.96
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                focus: true
                Keys.onEscapePressed: cheatsheetScope.isOpen = false

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: sheetWindow.s(20)
                    spacing: sheetWindow.s(14)

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: sheetWindow.s(12)

                        Text {
                            text: "keyboard"
                            color: ThemeBackend.mauve
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: sheetWindow.s(24)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: I18n.t("cheatsheet.title")
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: sheetWindow.s(17)
                                font.bold: true
                            }
                            Text {
                                text: I18n.t("cheatsheet.subtitle", { count: bindCount.value })
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: sheetWindow.s(11)
                            }
                        }

                        QtObject {
                            id: bindCount
                            readonly property int value: {
                                let n = 0;
                                for (let i = 0; i < cheatsheetScope.categories.length; i++) {
                                    n += cheatsheetScope.categories[i].binds.length;
                                }
                                return n;
                            }
                        }

                        Input {
                            id: searchInput
                            Layout.preferredWidth: sheetWindow.s(240)
                            implicitHeight: sheetWindow.s(32)
                            cornerRadius: ThemeBackend.clampedBorderRadius
                            baseColor: ThemeBackend.surface0
                            borderColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            subTextColor: ThemeBackend.subtext0
                            accentColor: ThemeBackend.mauve
                            fontFamily: ThemeBackend.fontFamily
                            fontPixelSize: sheetWindow.s(12)
                            placeholderText: I18n.t("cheatsheet.search")
                            showClearButton: true
                            onTextEdited: (t) => sheetWindow.filterText = t.toLowerCase()
                        }

                        DeleteButton {
                            size: sheetWindow.s(30)
                            cornerRadius: sheetWindow.s(9)
                            iconFontSize: sheetWindow.s(13)
                            buttonIcon: "✕"
                            onClicked: cheatsheetScope.isOpen = false
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: ThemeBackend.surface0
                    }

                    // Categories
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        Flow {
                            width: sheet.width - sheetWindow.s(56)
                            spacing: sheetWindow.s(14)

                            Repeater {
                                model: cheatsheetScope.categories

                                delegate: Rectangle {
                                    required property var modelData

                                    readonly property var visibleBinds: {
                                        if (sheetWindow.filterText === "") return modelData.binds;
                                        return modelData.binds.filter(b =>
                                            b.action.toLowerCase().indexOf(sheetWindow.filterText) !== -1 ||
                                            b.keys.join(" ").toLowerCase().indexOf(sheetWindow.filterText) !== -1 ||
                                            String(modelData.name).toLowerCase().indexOf(sheetWindow.filterText) !== -1);
                                    }

                                    visible: visibleBinds.length > 0
                                    width: sheetWindow.s(360)
                                    height: visible ? (catCol.implicitHeight + sheetWindow.s(20)) : 0
                                    radius: ThemeBackend.clampedBorderRadius
                                    color: ThemeBackend.mantle
                                    border.color: ThemeBackend.surface0
                                    border.width: 1

                                    ColumnLayout {
                                        id: catCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: sheetWindow.s(10)
                                        spacing: sheetWindow.s(6)

                                        Text {
                                            text: modelData.name
                                            color: ThemeBackend.mauve
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: sheetWindow.s(12)
                                            font.bold: true
                                        }

                                        Repeater {
                                            model: visibleBinds

                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: sheetWindow.s(8)

                                                Row {
                                                    spacing: sheetWindow.s(3)

                                                    Repeater {
                                                        model: modelData.keys

                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            implicitWidth: keyLabel.implicitWidth + sheetWindow.s(10)
                                                            implicitHeight: sheetWindow.s(20)
                                                            radius: sheetWindow.s(5)
                                                            color: ThemeBackend.surface1
                                                            border.color: ThemeBackend.surface2
                                                            border.width: 1

                                                            Text {
                                                                id: keyLabel
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                color: ThemeBackend.text
                                                                font.family: ThemeBackend.fontFamily
                                                                font.pixelSize: sheetWindow.s(10)
                                                                font.bold: true
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.action
                                                    color: ThemeBackend.subtext0
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: sheetWindow.s(11)
                                                    elide: Text.ElideRight
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { cheatsheetScope.isOpen = !cheatsheetScope.isOpen; }
        function open(): void { cheatsheetScope.isOpen = true; }
        function close(): void { cheatsheetScope.isOpen = false; }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggle the keybind cheatsheet"
        onPressed: cheatsheetScope.isOpen = !cheatsheetScope.isOpen
    }
}

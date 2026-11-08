import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../reusables"
import "../"

// A small file browser scoped to images/GIFs, used to pick the floating
// image overlay card's picture. Lets you navigate folders (starting at
// ~/Images/Stickers) and see each GIF actually animating before picking it,
// rather than typing a path blind.
Scope {
    id: pickerScope

    readonly property var imageExts: ["png", "jpg", "jpeg", "gif", "webp", "bmp"]

    property string currentDir: StickerPickerController.startDir
    property var entries: []
    property string errorText: ""

    function refresh() {
        listProc.running = false;
        listProc.running = true;
    }

    onCurrentDirChanged: {
        if (pickerScope.currentDir) pickerScope.refresh();
    }

    Connections {
        target: StickerPickerController
        function onIsOpenChanged() {
            if (StickerPickerController.isOpen) {
                pickerScope.currentDir = StickerPickerController.startDir;
                pickerScope.refresh();
            }
        }
    }

    function parentDir(dir) {
        let parts = dir.split("/").filter(p => p.length > 0);
        parts.pop();
        return "/" + parts.join("/");
    }

    function extOf(name) {
        let i = name.lastIndexOf(".");
        return i === -1 ? "" : name.substring(i + 1).toLowerCase();
    }

    Process {
        id: listProc
        running: false
        command: {
            let py =
                "import os, sys, json\n" +
                "d = sys.argv[1]\n" +
                "out = []\n" +
                "try:\n" +
                "    for e in sorted(os.scandir(d), key=lambda x: (not x.is_dir(follow_symlinks=True), x.name.lower())):\n" +
                "        if e.name.startswith('.'): continue\n" +
                "        out.append({'name': e.name, 'dir': e.is_dir(follow_symlinks=True)})\n" +
                "except Exception as ex:\n" +
                "    print(json.dumps({'error': str(ex)})); sys.exit(0)\n" +
                "print(json.dumps({'entries': out}))\n";
            return ["python3", "-c", py, pickerScope.currentDir];
        }
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                try {
                    let res = JSON.parse(listOut.text);
                    if (res.error) {
                        pickerScope.entries = [];
                        pickerScope.errorText = res.error;
                    } else {
                        pickerScope.entries = res.entries.filter(e => e.dir || pickerScope.imageExts.indexOf(pickerScope.extOf(e.name)) !== -1);
                        pickerScope.errorText = "";
                    }
                } catch (e) {
                    pickerScope.entries = [];
                    pickerScope.errorText = String(e);
                }
            }
        }
    }

    LazyLoader {
        active: StickerPickerController.isOpen

        PanelWindow {
            id: pickerWindow
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            visible: true

            WlrLayershell.namespace: "qs-sticker-picker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            screen: Quickshell.cursorScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            anchors { top: true; bottom: true; left: true; right: true }

            function s(val) { return Scaler.s(val); }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(ThemeBackend.crust, 0.6)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 180 } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: StickerPickerController.close()
                }
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(parent.width - pickerWindow.s(80), pickerWindow.s(560))
                height: Math.min(parent.height - pickerWindow.s(80), pickerWindow.s(520))
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.base, 0.98)
                border.color: ThemeBackend.surface1
                border.width: 1

                scale: 0.96
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 160 } }

                focus: true
                Keys.onEscapePressed: StickerPickerController.close()

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: pickerWindow.s(16)
                    spacing: pickerWindow.s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: pickerWindow.s(8)

                        Rectangle {
                            implicitWidth: pickerWindow.s(28)
                            implicitHeight: pickerWindow.s(28)
                            radius: pickerWindow.s(8)
                            color: upMa.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0
                            opacity: pickerScope.currentDir !== "/" ? 1 : 0.4

                            Text {
                                anchors.centerIn: parent
                                text: "arrow_upward"
                                color: ThemeBackend.text
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: pickerWindow.s(15)
                            }

                            MouseArea {
                                id: upMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: pickerScope.currentDir !== "/"
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pickerScope.currentDir = pickerScope.parentDir(pickerScope.currentDir)
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: pickerScope.currentDir
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: pickerWindow.s(11)
                            elide: Text.ElideMiddle
                        }

                        DeleteButton {
                            size: pickerWindow.s(28)
                            cornerRadius: pickerWindow.s(8)
                            iconFontSize: pickerWindow.s(12)
                            buttonIcon: "✕"
                            onClicked: StickerPickerController.close()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: ThemeBackend.surface0
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: pickerScope.errorText !== ""
                        text: pickerScope.errorText
                        color: ThemeBackend.red
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: pickerWindow.s(11)
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: pickerScope.errorText === "" && pickerScope.entries.length === 0
                        text: I18n.t("overlay.floatingimage.empty")
                        color: ThemeBackend.subtext0
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: pickerWindow.s(11)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    GridView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: pickerScope.entries.length > 0
                        clip: true
                        cellWidth: pickerWindow.s(108)
                        cellHeight: pickerWindow.s(108)
                        model: pickerScope.entries

                        delegate: Item {
                            id: cell
                            required property var modelData
                            width: pickerWindow.s(108)
                            height: pickerWindow.s(108)

                            readonly property string fullPath: pickerScope.currentDir + "/" + modelData.name

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: pickerWindow.s(4)
                                radius: pickerWindow.s(8)
                                color: cellMa.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0
                                border.color: ThemeBackend.surface1
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: pickerWindow.s(6)
                                    spacing: pickerWindow.s(4)

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        Text {
                                            anchors.centerIn: parent
                                            visible: cell.modelData.dir
                                            text: "folder"
                                            color: ThemeBackend.yellow
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: pickerWindow.s(36)
                                        }

                                        AnimatedImage {
                                            anchors.fill: parent
                                            visible: !cell.modelData.dir
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            playing: visible
                                            source: cell.modelData.dir ? "" : ("file://" + cell.fullPath)
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: cell.modelData.name
                                        color: ThemeBackend.text
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: pickerWindow.s(9)
                                        elide: Text.ElideMiddle
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                MouseArea {
                                    id: cellMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (cell.modelData.dir) {
                                            pickerScope.currentDir = cell.fullPath;
                                        } else {
                                            Config.setSetting("overlayFloatingImage", Object.assign({}, Config.getSetting("overlayFloatingImage", {}) || {}, { "path": cell.fullPath }));
                                            StickerPickerController.close();
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
        target: "stickerPicker"
        function open(): void { StickerPickerController.open(); }
        function close(): void { StickerPickerController.close(); }
    }
}

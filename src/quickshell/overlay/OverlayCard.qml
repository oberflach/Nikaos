import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../reusables"
import "../"

// A draggable tool card inside the widget overlay. The body it shows is
// picked from cardId; positions are reported back so they can be persisted.
Rectangle {
    id: card

    required property string modelData
    required property int index

    property string cardId: modelData
    property var scaleFn: (v) => v
    property real defaultX: 0
    property real defaultY: 0
    property real maxX: 1920
    property real maxY: 1080

    property bool pinned: false
    property bool overlayOpen: true

    // Whether this card should currently be shown at all (overlay is open,
    // or it's pinned). Driven from outside instead of the Repeater's model
    // membership, so the same instance persists across open/close instead
    // of being destroyed and recreated -- which used to reset its position
    // to a fresh index-based default and could leave a stale frame of its
    // old background visible for a moment.
    property bool shouldShow: true

    // Manual size from dragging the corner handle. -1 means "not resized
    // yet, use the natural/default size".
    property real customWidth: -1
    property real customHeight: -1
    readonly property real minCardWidth: s(160)
    readonly property real minCardHeight: s(90)

    signal resized(real w, real h)

    // The floating-image card is meant to be a bare desktop sticker once
    // pinned and the overlay itself is closed: no frame, no controls, just
    // the picture -- so it gets its own fully click-through, chromeless
    // rendering instead of the usual card look.
    // Must also require `pinned`: since the Repeater now keeps every
    // toggled-on card instantiated at all times (see Overlay.qml), a
    // floating-image card that's merely toggled on but NOT pinned would
    // otherwise flip into sticker mode every single time the overlay
    // closes -- which also swaps which AnimatedImage instance holds the
    // real source (see floatingImageBody), causing pointless reloads/
    // failures to load on every open/close cycle.
    readonly property bool isFloatingSticker: card.cardId === "floatingImage" && card.pinned && !card.overlayOpen

    signal closeRequested()
    signal moved(real x, real y)
    signal overlayCloseRequested()

    // Local: the recorder buttons close the overlay first and only start the
    // capture once its cards have faded out (180 ms), so they never end up
    // half-transparent in the frozen frame.
    function captureAfterClose(cmd) {
        card.overlayCloseRequested();
        captureDelay.cmd = cmd;
        captureDelay.restart();
    }
    Timer {
        id: captureDelay
        property var cmd: []
        interval: 350
        onTriggered: Quickshell.execDetached(captureDelay.cmd)
    }
    signal pinToggled()

    function s(val) { return card.scaleFn(val); }

    readonly property var cardMeta: ({
        "recorder":  { "icon": "screen_record", "title": I18n.t("overlay.cards.recorder") },
        "volume":    { "icon": "volume_up", "title": I18n.t("overlay.cards.volume") },
        "resources": { "icon": "browse_activity", "title": I18n.t("overlay.cards.resources") },
        "crosshair": { "icon": "point_scan", "title": I18n.t("overlay.cards.crosshair") },
        "notes":     { "icon": "sticky_note_2", "title": I18n.t("overlay.cards.notes") },
        "apps": { "icon": "apps", "title": I18n.t("overlay.cards.apps") },
        "transparency": { "icon": "opacity", "title": I18n.t("overlay.cards.transparency") },
        "floatingImage": { "icon": "imagesmode", "title": I18n.t("overlay.cards.floatingImage") },
        "gaming": { "icon": "sports_esports", "title": I18n.t("overlay.cards.gaming", "Game mode") }
    })
    readonly property var meta: cardMeta[cardId] || { "icon": "widgets", "title": cardId }


    width: card.customWidth > 0 ? card.customWidth : s(300)
    implicitHeight: card.customHeight > 0 ? card.customHeight : ((card.chromeVisible ? header.height : 0) + bodyLoader.implicitHeight + (card.isFloatingSticker ? 0 : s(20)))
    height: implicitHeight
    radius: card.isFloatingSticker ? 0 : ThemeBackend.clampedBorderRadius
    color: card.isFloatingSticker ? "transparent" : Qt.alpha(ThemeBackend.base, 0.97)
    border.color: ThemeBackend.surface1
    border.width: card.isFloatingSticker ? 0 : 1

    // Target opacity combines "should this be visible at all" with the
    // floating sticker's slight transparency. Recomputed live so toggling
    // either just fades in place -- no destroy/recreate involved.
    readonly property real targetOpacity: (!card.shouldShow || card.hiddenForFullscreen) ? 0 : (card.isFloatingSticker ? 0.85 : 1)
    enabled: card.shouldShow && !card.hiddenForFullscreen

    // The pinned floating image steps aside while an app is really
    // fullscreen (not merely maximized), unless the user chose to keep it.
    readonly property string floatImagePath: (Config.getSetting("overlayFloatingImage", {}) || {}).path || ""
    property bool keepInFullscreen: Boolean((Config.getSetting("overlayFloatingImage", {}) || {}).showInFullscreen)
    readonly property bool hiddenForFullscreen: card.isFloatingSticker
        && ((CurrentFocus.isFullscreenActive && !card.keepInFullscreen) || GameMode.hideSticker)

    scale: 0.95
    opacity: 0
    Component.onCompleted: {
        let saved = Config.getSetting("overlay", {}).positions || {};
        let p = saved[card.cardId];
        card.x = (p && p.x !== undefined) ? p.x : card.defaultX;
        card.y = (p && p.y !== undefined) ? p.y : card.defaultY;
        if (card.cardId === "floatingImage") {
            // Its editing and sticker bodies have different natural
            // (implicit) heights -- one has a button row, the other
            // doesn't -- so leaving the size implicit made the card visibly
            // resize (and the picture re-center) every time the overlay
            // opened or closed. Fix it right away instead of leaving that
            // to whenever the user first drags the resize handle.
            card.customWidth = (p && p.w) ? p.w : s(300);
            card.customHeight = (p && p.h) ? p.h : s(220);
        } else {
            if (p && p.w) card.customWidth = p.w;
            if (p && p.h) card.customHeight = p.h;
        }
        card.scale = 1;
        card.opacity = card.targetOpacity;
    }
    onTargetOpacityChanged: card.opacity = card.targetOpacity
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
    Behavior on opacity { NumberAnimation { duration: 180 } }

    // Pinning/unpinning only makes sense while the menu is open (that's
    // where the pin button lives), so the header -- and the space it takes
    // up -- only exists while the overlay is open. Once closed, whatever
    // is left over is only there because it's pinned, and it's shown
    // header-less: no hover reveal, no leftover background strip where the
    // header used to be, nothing to click.
    readonly property bool chromeVisible: card.overlayOpen

    // --- Header / drag handle ---
    // Height stays constant so hiding it never resizes/moves the card --
    // it just slides down over the top of the body and fades out, instead
    // of the body sliding up to fill the freed space.
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: card.s(34)
        // chromeVisible only flips on open/close now (not on hover), so
        // there's no reveal animation to protect -- just fully unrender it
        // the instant the overlay closes. That's what actually gets rid of
        // it: opacity alone would still leave the card's own background
        // painted where the header used to be.
        visible: card.chromeVisible
        enabled: card.chromeVisible
        z: 5

        // Only needed when the header draws on top of the picture instead
        // of pushing it down (see card.bodyFillsCard) -- keeps the title/
        // pin/close legible regardless of what's in the image underneath.
        Rectangle {
            anchors.fill: parent
            visible: card.bodyFillsCard
            color: Qt.alpha(ThemeBackend.crust, 0.65)
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: card
            // Allow dragging up to 30% of the card off the left/bottom/right
            // edges so it can be flushed right against the screen border
            // (e.g. a sticker half-hanging off the corner). Top stays fully
            // on-screen since that's where the card picker bar lives.
            drag.minimumX: -card.width * 0.3
            drag.minimumY: 0
            drag.maximumX: card.maxX - card.width * 0.7
            drag.maximumY: card.maxY - card.height * 0.7
            onReleased: card.moved(card.x, card.y)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: card.s(12)
            anchors.rightMargin: card.s(6)
            spacing: card.s(8)

            Text {
                text: card.meta.icon
                color: ThemeBackend.subtext0
                font.family: "Material Symbols Rounded"
                font.pixelSize: card.s(16)
            }
            Text {
                Layout.fillWidth: true
                text: card.meta.title
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(12)
                font.bold: true
                elide: Text.ElideRight
            }
            // Floating image actions, same size as the pin button.
            IconButton {
                visible: card.cardId === "floatingImage" && card.floatImagePath !== ""
                size: card.s(24)
                cornerRadius: card.s(7)
                iconFontSize: card.s(13)
                accentColor: ThemeBackend.surface1
                textColor: ThemeBackend.subtext0
                buttonIcon: "󰏫"
                onClicked: StickerPickerController.open()
            }
            IconButton {
                visible: card.cardId === "floatingImage" && card.floatImagePath !== ""
                size: card.s(24)
                cornerRadius: card.s(7)
                iconFontSize: card.s(13)
                accentColor: card.keepInFullscreen ? ThemeBackend.mauve : ThemeBackend.surface1
                textColor: card.keepInFullscreen ? ThemeBackend.crust : ThemeBackend.subtext0
                action_highlight: card.keepInFullscreen
                buttonIcon: "󰊓"
                onClicked: {
                    card.keepInFullscreen = !card.keepInFullscreen;
                    Config.setSetting("overlayFloatingImage", Object.assign({}, Config.getSetting("overlayFloatingImage", {}) || {}, { "showInFullscreen": card.keepInFullscreen }));
                }
            }
            IconButton {
                visible: card.cardId === "floatingImage" && card.floatImagePath !== ""
                size: card.s(24)
                cornerRadius: card.s(7)
                iconFontSize: card.s(13)
                accentColor: ThemeBackend.surface1
                textColor: ThemeBackend.red
                buttonIcon: "󰆴"
                onClicked: Config.setSetting("overlayFloatingImage", Object.assign({}, Config.getSetting("overlayFloatingImage", {}) || {}, { "path": "" }))
            }
            IconButton {
                size: card.s(24)
                cornerRadius: card.s(7)
                iconFontSize: card.s(13)
                accentColor: card.pinned ? ThemeBackend.mauve : ThemeBackend.surface1
                textColor: card.pinned ? ThemeBackend.crust : ThemeBackend.subtext0
                action_highlight: card.pinned
                buttonIcon: "󰐃"
                onClicked: card.pinToggled()
            }

            DeleteButton {
                size: card.s(24)
                cornerRadius: card.s(7)
                iconFontSize: card.s(11)
                buttonIcon: "✕"
                onClicked: card.closeRequested()
            }
        }
    }

    Rectangle {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.s(10)
        anchors.rightMargin: card.s(10)
        height: 1
        color: ThemeBackend.surface0
        visible: card.chromeVisible && !card.bodyFillsCard
    }

    // --- Body ---
    // The floating-image card always fills the whole card edge-to-edge in
    // both modes (its header/edit controls draw as overlays on top of it
    // instead of pushing it down) -- that's what makes the picture render
    // at the exact same size and position in both, instead of shrinking to
    // make room for a header/button row that only exists while editing.
    readonly property bool bodyFillsCard: card.cardId === "floatingImage"

    Loader {
        id: bodyLoader
        // When the header is collapsed (overlay closed) it shouldn't
        // reserve any space -- the body starts right at the card's top.
        anchors.top: card.bodyFillsCard ? parent.top : (card.chromeVisible ? header.bottom : parent.top)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: (card.isFloatingSticker || card.bodyFillsCard) ? 0 : card.s(10)
        anchors.topMargin: (card.isFloatingSticker || card.bodyFillsCard || !card.chromeVisible) ? 0 : card.s(6)
        anchors.bottomMargin: (card.isFloatingSticker || card.bodyFillsCard) ? 0 : card.s(10)
        sourceComponent: {
            if (card.cardId === "recorder") return recorderBody;
            if (card.cardId === "volume") return volumeBody;
            if (card.cardId === "resources") return resourcesBody;
            if (card.cardId === "crosshair") return crosshairBody;
            if (card.cardId === "notes") return notesBody;
            if (card.cardId === "apps") return appManagerBody;
            if (card.cardId === "transparency") return transparencyBody;
            if (card.cardId === "floatingImage") return floatingImageBody;
            if (card.cardId === "gaming") return gamingBody;
            return null;
        }
    }

    // --- Resize handle (bottom-right corner) ---
    // Every card can be resized this way; the floating-image card in
    // particular ties its picture's rendered size directly to this instead
    // of a separate zoom control.
    Item {
        id: resizeHandle
        visible: card.chromeVisible
        width: card.s(20)
        height: card.s(20)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 10

        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: card.s(3)
            text: "⤡"
            color: resizeMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0
            font.pixelSize: card.s(13)
        }

        MouseArea {
            id: resizeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor

            property real startW: 0
            property real startH: 0
            property point pressPoint: Qt.point(0, 0)

            onPressed: (mouse) => {
                startW = card.width;
                startH = card.height;
                pressPoint = resizeMa.mapToItem(card.parent, mouse.x, mouse.y);
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return;
                let cur = resizeMa.mapToItem(card.parent, mouse.x, mouse.y);
                card.customWidth = Math.max(card.minCardWidth, startW + (cur.x - pressPoint.x));
                card.customHeight = Math.max(card.minCardHeight, startH + (cur.y - pressPoint.y));
            }
            onReleased: card.resized(card.width, card.height)
        }
    }

    // ---------------- Recorder ----------------
    // Four quick actions (region/fullscreen shot or record) plus a shortcut
    // to the recordings folder -- matching end-4's Recorder, using
    // serpantinum's own `serpantinum screenshot` CLI (same one Print/
    // SUPER+Print already use) instead of touching the script directly.
    Component {
        id: recorderBody

        ColumnLayout {
            id: recorderCol
            spacing: card.s(12)

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: card.s(10)

                RecorderActionButton {
                    icon: "screenshot_region"
                    label: I18n.t("overlay.recorder.shot_region")
                    onClicked: {
                        card.captureAfterClose(["serpantinum", "screenshot"]);
                    }
                }
                RecorderActionButton {
                    icon: "photo_camera"
                    label: I18n.t("overlay.recorder.shot_full")
                    onClicked: {
                        card.captureAfterClose(["serpantinum", "screenshot", "--full"]);
                    }
                }
                RecorderActionButton {
                    icon: "screen_record"
                    label: I18n.t("overlay.recorder.rec_region")
                    onClicked: {
                        card.captureAfterClose(["serpantinum", "screenshot", "--record"]);
                    }
                }
                RecorderActionButton {
                    icon: "capture"
                    label: I18n.t("overlay.recorder.rec_full")
                    onClicked: {
                        card.captureAfterClose(["serpantinum", "screenshot", "--full", "--record"]);
                    }
                }
            }

            ClickButton {
                Layout.alignment: Qt.AlignHCenter
                implicitHeight: card.s(30)
                buttonText: I18n.t("overlay.recorder.open_folder")
                textColor: ThemeBackend.subtext0
                onClicked: Quickshell.execDetached(["bash", "-c", "f=\"${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs\"; [ -f \"$f\" ] && . \"$f\"; d=\"${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings\"; mkdir -p \"$d\" && xdg-open \"$d\""])
            }

            component RecorderActionButton: Rectangle {
                id: actionBtn
                required property string icon
                required property string label
                signal clicked()

                implicitWidth: card.s(58)
                implicitHeight: card.s(58)
                radius: width / 2
                color: actionMouse.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: actionBtn.icon
                    color: ThemeBackend.text
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: card.s(24)
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: actionBtn.clicked()
                }

                ToolTip.visible: actionMouse.containsMouse
                ToolTip.text: actionBtn.label
                ToolTip.delay: 400
            }
        }
    }

    // ---------------- Volume ----------------
    Component {
        id: volumeBody

        ColumnLayout {
            spacing: card.s(12)

            readonly property var sink: Audio.defaultSink
            readonly property var source: Audio.defaultSource

            // Output
            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(8)

                ClickButton {
                    implicitWidth: card.s(28)
                    implicitHeight: card.s(28)
                    cornerRadius: card.s(8)
                    buttonIcon: (volCol.sink && volCol.sink.audio && volCol.sink.audio.muted) ? "󰝟" : "󰕾"
                    textColor: (volCol.sink && volCol.sink.audio && volCol.sink.audio.muted) ? ThemeBackend.red : ThemeBackend.text
                    onClicked: if (volCol.sink) Audio.toggleMute(volCol.sink)
                }

                Draggable {
                    Layout.fillWidth: true
                    implicitHeight: card.s(20)
                    from: 0
                    to: 100
                    value: (volCol.sink && volCol.sink.audio) ? Math.round(volCol.sink.audio.volume * 100) : 0
                    accentColor: ThemeBackend.blue
                    backgroundColor: ThemeBackend.surface0
                    onMoved: (val) => { if (volCol.sink) Audio.setVolume(volCol.sink, val); }
                }

                Text {
                    text: ((volCol.sink && volCol.sink.audio) ? Math.round(volCol.sink.audio.volume * 100) : 0) + "%"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(11)
                    Layout.preferredWidth: card.s(36)
                    horizontalAlignment: Text.AlignRight
                }
            }

            // Output device picker
            Dropdown {
                Layout.fillWidth: true
                implicitHeight: card.s(28)
                fontPixelSize: card.s(10)
                cornerRadius: card.s(8)
                options: Audio.outputs.map(n => Audio.getNodeName(n))
                currentIndex: volCol.sink ? Audio.outputs.indexOf(volCol.sink) : -1
                onSelected: (index) => Audio.setDefaultOutput(Audio.outputs[index])
            }

            // Mic
            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(8)

                ClickButton {
                    implicitWidth: card.s(28)
                    implicitHeight: card.s(28)
                    cornerRadius: card.s(8)
                    buttonIcon: (volCol.source && volCol.source.audio && volCol.source.audio.muted) ? "󰍭" : "󰍬"
                    textColor: (volCol.source && volCol.source.audio && volCol.source.audio.muted) ? ThemeBackend.red : ThemeBackend.text
                    onClicked: if (volCol.source) Audio.toggleMute(volCol.source)
                }

                Draggable {
                    Layout.fillWidth: true
                    implicitHeight: card.s(20)
                    from: 0
                    to: 100
                    value: (volCol.source && volCol.source.audio) ? Math.round(volCol.source.audio.volume * 100) : 0
                    accentColor: ThemeBackend.mauve
                    backgroundColor: ThemeBackend.surface0
                    onMoved: (val) => { if (volCol.source) Audio.setVolume(volCol.source, val); }
                }

                Text {
                    text: ((volCol.source && volCol.source.audio) ? Math.round(volCol.source.audio.volume * 100) : 0) + "%"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(11)
                    Layout.preferredWidth: card.s(36)
                    horizontalAlignment: Text.AlignRight
                }
            }

            // Input device picker
            Dropdown {
                Layout.fillWidth: true
                implicitHeight: card.s(28)
                fontPixelSize: card.s(10)
                cornerRadius: card.s(8)
                options: Audio.inputs.map(n => Audio.getNodeName(n))
                currentIndex: volCol.source ? Audio.inputs.indexOf(volCol.source) : -1
                onSelected: (index) => Audio.setDefaultInput(Audio.inputs[index])
            }

            // Per-app mixer
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: card.s(4)
                spacing: card.s(8)
                visible: Audio.apps.length > 0

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: ThemeBackend.surface0
                }

                Text {
                    text: I18n.t("overlay.volume.apps")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(10)
                    font.bold: true
                }

                Repeater {
                    model: Audio.apps

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: card.s(8)

                        Text {
                            Layout.preferredWidth: card.s(80)
                            text: Audio.getNodeAppName(modelData)
                            color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: card.s(10)
                            elide: Text.ElideRight
                        }

                        Draggable {
                            Layout.fillWidth: true
                            implicitHeight: card.s(16)
                            from: 0
                            to: 100
                            value: modelData.audio ? Math.round(modelData.audio.volume * 100) : 0
                            accentColor: ThemeBackend.green
                            backgroundColor: ThemeBackend.surface0
                            onMoved: (val) => Audio.setVolume(modelData, val)
                        }

                        ClickButton {
                            implicitWidth: card.s(22)
                            implicitHeight: card.s(22)
                            cornerRadius: card.s(6)
                            buttonIcon: (modelData.audio && modelData.audio.muted) ? "󰝟" : "󰕾"
                            iconFontSize: card.s(10)
                            textColor: (modelData.audio && modelData.audio.muted) ? ThemeBackend.red : ThemeBackend.subtext0
                            onClicked: Audio.toggleMute(modelData)
                        }
                    }
                }
            }

            id: volCol
        }
    }

    // ---------------- Resources ----------------
    // Tabbed CPU/RAM/TEMP/GPU with a rolling history line graph, mirroring
    // end-4's Resources widget. SysData only exposes the current snapshot,
    // so the history is kept here (60 samples, one per SysData tick).
    Component {
        id: resourcesBody

        ColumnLayout {
            id: resCol
            spacing: card.s(10)

            property int tabIndex: 0
            readonly property var tabs: [
                { "label": "CPU",  "value": SysData.cpu,         "suffix": "%", "color": ThemeBackend.blue },
                { "label": "RAM",  "value": SysData.ramPercent,  "suffix": "%", "color": ThemeBackend.mauve },
                { "label": "TEMP", "value": SysData.temp,        "suffix": "°", "color": ThemeBackend.peach },
                { "label": "GPU",  "value": resCol.gpu,          "suffix": "%", "color": ThemeBackend.red },
                { "label": "SWAP", "value": SysData.swapPercent, "suffix": "%", "color": ThemeBackend.green }
            ]
            readonly property var currentTab: tabs[tabIndex]

            property var cpuHistory: []
            property var ramHistory: []
            property var tempHistory: []
            property var gpuHistory: []
            property var swapHistory: []
            readonly property int maxSamples: 40

            function pushHistory(arr, val) {
                let next = arr.slice();
                next.push(val);
                if (next.length > resCol.maxSamples) next.shift();
                return next;
            }

            // SysData has no GPU reading; amdgpu exposes the load in sysfs.
            property int gpu: 0
            Process {
                id: gpuProc
                command: ["bash", "-c", "cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let v = parseInt(this.text.trim());
                        resCol.gpu = isNaN(v) ? 0 : v;
                    }
                }
            }

            Component.onCompleted: SysData.subscribe()
            Component.onDestruction: SysData.unsubscribe()

            // Sample on a fixed tick rather than *Changed signals: a value
            // sitting still for a few polls would otherwise never grow the
            // history and the graph would stay empty.
            Timer {
                interval: 2000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: {
                    resCol.cpuHistory = resCol.pushHistory(resCol.cpuHistory, SysData.cpu);
                    resCol.ramHistory = resCol.pushHistory(resCol.ramHistory, SysData.ramPercent);
                    resCol.tempHistory = resCol.pushHistory(resCol.tempHistory, SysData.temp);
                    resCol.gpuHistory = resCol.pushHistory(resCol.gpuHistory, resCol.gpu);
                    gpuProc.running = true;
                    resCol.swapHistory = resCol.pushHistory(resCol.swapHistory, SysData.swapPercent);
                }
            }

            readonly property var currentHistory: [cpuHistory, ramHistory, tempHistory, gpuHistory, swapHistory][tabIndex]

            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(6)

                Repeater {
                    model: resCol.tabs

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: resCol.tabIndex === index
                        Layout.fillWidth: true
                        implicitHeight: card.s(26)
                        radius: ThemeBackend.clampedBorderRadius
                        color: sel ? ThemeBackend.surface2 : ThemeBackend.surface0
                        border.color: sel ? ThemeBackend.text : "transparent"
                        border.width: sel ? card.s(1.5) : 0

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: sel ? ThemeBackend.text : ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: card.s(10)
                            font.bold: sel
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: resCol.tabIndex = index
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: card.s(90)
                spacing: card.s(10)

                ColumnLayout {
                    Layout.preferredWidth: card.s(56)
                    Layout.fillHeight: true
                    spacing: 0

                    Text {
                        text: resCol.currentTab.value + resCol.currentTab.suffix
                        color: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: card.s(20)
                        font.bold: true
                    }
                    Text {
                        text: resCol.currentTab.label
                        color: ThemeBackend.subtext0
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: card.s(9)
                    }
                    Item { Layout.fillHeight: true }
                }

                Rectangle {
                    id: graphBg
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ThemeBackend.clampedBorderRadius
                    color: ThemeBackend.surface0
                    clip: true

                    Canvas {
                        id: graphCanvas
                        anchors.fill: parent
                        anchors.margins: card.s(6)

                        readonly property var history: resCol.currentHistory
                        onHistoryChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            let ctx = getContext("2d");
                            ctx.reset();
                            let hist = graphCanvas.history;
                            if (!hist || hist.length < 2) return;

                            let w = width;
                            let h = height;
                            let stepX = w / (resCol.maxSamples - 1);
                            let startIdx = resCol.maxSamples - hist.length;

                            ctx.beginPath();
                            for (let i = 0; i < hist.length; i++) {
                                let x = (startIdx + i) * stepX;
                                let y = h - (Math.max(0, Math.min(100, hist[i])) / 100) * h;
                                if (i === 0) ctx.moveTo(x, y);
                                else ctx.lineTo(x, y);
                            }
                            ctx.strokeStyle = resCol.currentTab.color;
                            ctx.lineWidth = 2;
                            ctx.lineJoin = "round";
                            ctx.stroke();

                            ctx.lineTo((startIdx + hist.length - 1) * stepX, h);
                            ctx.lineTo(startIdx * stepX, h);
                            ctx.closePath();
                            ctx.fillStyle = Qt.alpha(resCol.currentTab.color, 0.18);
                            ctx.fill();
                        }
                    }
                }
            }
        }
    }

    // ---------------- Crosshair settings ----------------
    Component {
        id: crosshairBody

        ColumnLayout {
            id: chCol
            spacing: card.s(10)

            property var chSettings: Config.getSetting("crosshair", {
                "enabled": false, "style": "cross", "size": 18, "thickness": 2, "color": "#a6e3a1", "gap": 4
            })

            function save(key, value) {
                let next = JSON.parse(JSON.stringify(chCol.chSettings));
                next[key] = value;
                chCol.chSettings = next;
                Config.setSetting("crosshair", next);
            }

            Toggle {
                Layout.fillWidth: true
                checked: chCol.chSettings.enabled === true
                buttonText: I18n.t("overlay.crosshair.enable")
                onToggled: (val) => chCol.save("enabled", val)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(6)

                Repeater {
                    model: [
                        { "id": "cross", "icon": "✛" },
                        { "id": "dot",   "icon": "•" },
                        { "id": "circle","icon": "◎" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: chCol.chSettings.style === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: card.s(30)
                        radius: ThemeBackend.clampedBorderRadius
                        color: sel ? ThemeBackend.surface2 : ThemeBackend.surface0
                        border.color: sel ? ThemeBackend.text : "transparent"
                        border.width: sel ? card.s(1.5) : 0

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: sel ? ThemeBackend.text : ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: card.s(14)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: chCol.save("style", modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(8)

                Text {
                    text: I18n.t("overlay.crosshair.size")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(11)
                    Layout.preferredWidth: card.s(60)
                }

                Draggable {
                    Layout.fillWidth: true
                    implicitHeight: card.s(20)
                    from: 6
                    to: 60
                    stepSize: 1
                    value: chCol.chSettings.size || 18
                    accentColor: ThemeBackend.green
                    backgroundColor: ThemeBackend.surface0
                    onMoved: (val) => chCol.save("size", Math.round(val))
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(6)

                Repeater {
                    model: [ThemeBackend.green, ThemeBackend.red, ThemeBackend.yellow, ThemeBackend.blue, ThemeBackend.text]

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: String(chCol.chSettings.color).toLowerCase() === String(modelData).toLowerCase()
                        Layout.fillWidth: true
                        implicitHeight: card.s(24)
                        radius: ThemeBackend.clampedBorderRadius
                        color: modelData
                        border.color: sel ? ThemeBackend.text : "transparent"
                        border.width: sel ? card.s(2) : 0

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: chCol.save("color", String(modelData))
                        }
                    }
                }
            }
        }
    }

    // ---------------- Notes ----------------
    // Freeform sticky note, autosaved. Lines starting with "- " are pulled
    // out below as one-click copy chips (handy for shopping/crafting lists),
    // mirroring end-4's Notes widget without needing its overlay-positioned
    // copy buttons.
    Component {
        id: notesBody

        ColumnLayout {
            id: notesCol
            spacing: card.s(8)

            readonly property var bulletLines: {
                let lines = String(noteArea.text).split("\n");
                let out = [];
                for (let i = 0; i < lines.length; i++) {
                    let m = lines[i].match(/^\s*-\s+(.*\S)\s*$/);
                    if (m) out.push(m[1]);
                }
                return out;
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: card.s(140)
                radius: card.s(8)
                color: ThemeBackend.surface0
                border.color: ThemeBackend.surface1
                border.width: 1

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: card.s(6)
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    TextArea {
                        id: noteArea
                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        color: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: card.s(11)
                        placeholderText: I18n.t("overlay.notes.placeholder")
                        placeholderTextColor: ThemeBackend.subtext0
                        background: null

                        Component.onCompleted: text = Config.getSetting("overlayNotes", "")
                        onTextChanged: saveDebounce.restart()
                    }
                }
            }

            Timer {
                id: saveDebounce
                interval: 500
                onTriggered: Config.setSetting("overlayNotes", noteArea.text)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: card.s(4)
                visible: notesCol.bulletLines.length > 0

                Repeater {
                    model: notesCol.bulletLines

                    delegate: RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: card.s(6)

                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: card.s(10)
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: copyBtn
                            implicitWidth: card.s(20)
                            implicitHeight: card.s(20)
                            radius: card.s(6)
                            color: copyMa.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1

                            Text {
                                anchors.centerIn: parent
                                text: copiedTimer.running ? "check" : "content_copy"
                                color: copiedTimer.running ? ThemeBackend.green : ThemeBackend.subtext0
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: card.s(12)
                            }

                            Timer { id: copiedTimer; interval: 700 }

                            MouseArea {
                                id: copyMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.clipboardText = modelData;
                                    copiedTimer.restart();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // ---------------- Running applications ----------------
    // What is running, and a way to end it.
    //
    // Windows come from hyprctl rather than ToplevelManager because it reports
    // the pid the kill needs and groups cleanly by class. Tray items are merged
    // in on top, keyed by pid so nothing is listed twice: a window list alone
    // misses Steam and friends once they minimise to the tray with no mapped
    // window, which is the case where ending them matters most.
    Component {
        id: appManagerBody

        ColumnLayout {
            id: appsCol
            spacing: card.s(6)

            ListModel { id: appsModel }

            Process {
                id: appScanner
                running: false
                command: ["bash", "-c",
                    "hyprctl clients -j | jq -c '[.[] | select(.class != \"\") | {name: .class, title: .title, pid: .pid}] | group_by(.name) | map(.[0])'"]
                stdout: StdioCollector {
                    onStreamFinished: appsCol.rebuild(this.text)
                }
            }

            Process {
                id: appKiller
                running: false
                property int targetPid: 0
                property string targetName: ""
                // Tray items do not always carry a pid -- Steam is the common case --
                // so fall back to matching the executable name. -x keeps that to an
                // exact match rather than anything whose command line mentions it.
                //
                // TERM rather than KILL throughout: apps that ask before quitting get
                // to, which is what keeps a browser from losing its tabs.
                command: ["bash", "-c",
                    targetPid > 0
                        ? "pkill -TERM -P " + targetPid + " 2>/dev/null; kill -TERM " + targetPid + " 2>/dev/null; true"
                        : "pkill -TERM -x " + JSON.stringify(targetName.toLowerCase()) + " 2>/dev/null; true"]
                onExited: appsCol.refresh()
            }

            function refresh() {
                appScanner.running = false;
                appScanner.running = true;
            }

            function rebuild(raw) {
                let windows = [];
                try { windows = JSON.parse(raw || "[]") || []; } catch (e) { windows = []; }

                let seen = ({});
                let merged = [];
                for (let i = 0; i < windows.length; i++) {
                    let w = windows[i];
                    if (!w || !w.pid) continue;
                    seen[w.pid] = true;
                    merged.push({ name: String(w.name), detail: String(w.title || ""), pid: w.pid, background: false });
                }

                let tray = (typeof SystemTray !== "undefined" && SystemTray.items) ? SystemTray.items.values : [];
                for (let i = 0; i < tray.length; i++) {
                    let t = tray[i];
                    if (!t) continue;
                    let pid = (t.pid !== undefined && t.pid !== null) ? t.pid : 0;
                    if (pid && seen[pid]) continue;
                    merged.push({
                        name: String(t.title || t.id || "?"),
                        detail: I18n.t("overlay.apps.background"),
                        pid: pid,
                        background: true
                    });
                }

                merged.sort((a, b) => String(a.name).localeCompare(String(b.name)));
                appsModel.clear();
                for (let i = 0; i < merged.length; i++) appsModel.append(merged[i]);
            }

            // Only poll while the card is actually open.
            Timer {
                interval: 2000
                repeat: true
                running: appsCol.visible
                onTriggered: appsCol.refresh()
            }
            Component.onCompleted: refresh()

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: card.s(190)
                clip: true
                spacing: card.s(4)
                model: appsModel
                reuseItems: true

                delegate: Rectangle {
                    width: ListView.view ? ListView.view.width : 0
                    height: card.s(36)
                    radius: card.s(8)
                    color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: card.s(10)
                        anchors.rightMargin: card.s(6)
                        spacing: card.s(8)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: model.name
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(11)
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: model.detail
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(9)
                                font.italic: model.background
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: card.s(26)
                            Layout.preferredHeight: card.s(22)
                            radius: card.s(6)
                            color: killArea.containsMouse
                                ? Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.85)
                                : Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.25)

                            Text {
                                anchors.centerIn: parent
                                text: "\u2715"
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(11)
                            }

                            MouseArea {
                                id: killArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: model.pid > 0 || model.name !== ""
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    appKiller.targetPid = model.pid;
                                    appKiller.targetName = model.name;
                                    appKiller.running = false;
                                    appKiller.running = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------- Per-window transparency ----------------
    // Hyprland's own opacity settings are global; this drives ONE window at a
    // time through hl.window_rule matched on class + title, which is the only
    // combination that both works and separates two windows of the same app.
    //
    // Three other routes were tried against the live compositor and do NOT
    // work here, so please do not "simplify" back to them:
    //   - `hyprctl setprop`: answers "unknown request" for every property
    //     under the Lua (non-legacy) config.
    //   - `match = { address = ... }`: hl.window_rule accepts the table but
    //     rejects it on apply with "unknown match property 'address'".
    //   - `hl.dsp.window.set_prop` dispatched at a window: returns success and
    //     changes nothing on screen.
    // Valid match keys are class, title, initial_class, initial_title, tag,
    // workspace, fullscreen, xwayland and focus.
    //
    // Rules live in a Lua global keyed by window address, so moving a slider
    // again disables that window's previous rule instead of stacking a new one.
    // Session-scoped by design: `hyprctl reload` clears them all, which doubles
    // as the escape hatch if anything ever gets stuck.
    //
    // Because the match is on the title, a window that retitles itself (a new
    // browser tab, a different file) stops matching. The periodic rescan spots
    // that and re-applies, so the setting survives the rename.
    //
    // Worth knowing: the compositor composites each window as one finished
    // image, so this fades the text along with the background. Only an app
    // that implements its own transparency (kitty's background_opacity, for
    // instance) can keep its text solid.
    Component {
        id: transparencyBody

        ColumnLayout {
            id: trCol
            spacing: card.s(6)

            // address -> alpha, so a refresh does not snap every slider back
            // to 100% while the scan result is being merged in. savedByClass
            // is persistent and lets a newly-created window inherit the last
            // opacity selected for its application after a session restart.
            property var applied: ({})
            property var savedByClass: ({})
            property var restoreQueue: []

            ListModel { id: windowsModel }

            Process {
                id: winScanner
                running: false
                // Every mapped window, NOT grouped by class: two terminals are
                // two rows here, which is the whole point of the card.
                command: ["bash", "-c",
                    "hyprctl clients -j | jq -c '[.[] | select(.class != \"\") | {address, name: .class, title: .title, pid}]'"]
                stdout: StdioCollector {
                    onStreamFinished: trCol.rebuild(this.text)
                }
            }

            Process {
                id: alphaApplier
                running: false
                property string lua: ""
                command: ["hyprctl", "eval", lua]
            }

            // Kitty, Vesktop and Code can make only their own backgrounds translucent.
            // Sending them through Hyprland would fade the already-rendered text
            // and images, so the Super+G slider uses this native route instead.
            Process {
                id: nativeAlphaApplier
                running: false
                command: []
            }

            Process {
                id: nativeAlphaResetter
                running: false
                command: [
                    Caching.serpantinumDir + "/scripts/window-transparency.sh",
                    "reset-all"
                ]
            }

            // Live rules above vanish on `hyprctl reload`; this keeps a copy in
            // ~/.config/hypr/config/transparency.lua that Hyprland loads itself.
            // Debounced so dragging a slider writes the file once.
            Timer {
                id: rulesWriteTimer
                interval: 500
                onTriggered: {
                    rulesWriter.command = ["bash", "-c",
                        "\"$1\" \"$2\" \"$4\" && grep -h 'no_blur = false' \"$3\" | while IFS= read -r l; do hyprctl eval \"$l\" >/dev/null; done", "_",
                        Caching.serpantinumDir + "/scripts/window-transparency-rules.sh",
                        JSON.stringify(trCol.savedByClass),
                        (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hypr/config/transparency.lua",
                        trCol.blurOn ? "on" : "off"
                    ];
                    rulesWriter.running = false;
                    rulesWriter.running = true;
                }
            }

            Process {
                id: rulesWriter
                running: false
            }

            // Local: blur switch. On blurs only windows saved as transparent
            // (plus the shell layers); off blurs nothing. The rules file is
            // rewritten and Hyprland reloads it, so opaque windows never run
            // the blur pass.
            property bool blurOn: Config.getSetting("windowBlur", true) !== false

            function setBlur(on) {
                trCol.blurOn = on;
                Config.setSetting("windowBlur", on);
                blurApplier.command = ["bash", "-c", "\"$1\" \"$2\" \"$3\" && hyprctl reload config-only", "_",
                    Caching.serpantinumDir + "/scripts/window-transparency-rules.sh",
                    JSON.stringify(trCol.savedByClass), on ? "on" : "off"];
                blurApplier.running = false;
                blurApplier.running = true;
            }

            Process {
                id: blurApplier
                running: false
                onExited: Qt.callLater(trCol.loadSaved)
            }


            function nativeTransparencyApp(cls) {
                let app = String(cls || "").toLowerCase();
                if (app === "kitty") return "kitty";
                if (app === "vesktop") return "vesktop";
                return "";
            }

            function classKey(cls) {
                return String(cls || "").trim().toLowerCase();
            }

            function loadSaved() {
                let raw = Config.getSetting("windowTransparency", {}) || {};
                let clean = {};
                for (let key in raw) {
                    let pct = Math.round(Number(raw[key]));
                    if (key !== "" && isFinite(pct) && pct >= 30 && pct < 100)
                        clean[String(key).toLowerCase()] = pct;
                }
                trCol.savedByClass = clean;
            }

            function savedAlpha(cls) {
                let pct = Number(trCol.savedByClass[trCol.classKey(cls)]);
                return (isFinite(pct) && pct >= 30 && pct < 100) ? Math.round(pct) : 100;
            }

            function rememberAlpha(cls, pct) {
                let key = trCol.classKey(cls);
                if (key === "") return;

                let next = {};
                for (let oldKey in trCol.savedByClass)
                    next[oldKey] = trCol.savedByClass[oldKey];
                if (pct < 100) next[key] = pct;
                else delete next[key];

                trCol.savedByClass = next;
                Config.setSetting("windowTransparency", next);
                rulesWriteTimer.restart();
            }

            function queueSavedAlpha(address, cls, title, pct, pid) {
                // Mark it before queueing so the 2.5-second client scan cannot
                // enqueue the same window again while earlier jobs are applied.
                trCol.applied[address] = { alpha: pct, title: title, cls: cls, pid: pid };
                let next = trCol.restoreQueue.slice();
                next.push({ address: address, cls: cls, title: title, alpha: pct, pid: pid });
                trCol.restoreQueue = next;
            }

            // address only identifies the row and the stored rule; what the
            // rule actually matches on is the class and title, since those are
            // the keys hl.window_rule honours.
            function applyAlpha(address, cls, title, value, pid, remember) {
                let pct = Math.round(value);
                let v = pct / 100;
                trCol.applied[address] = { alpha: pct, title: title, cls: cls, pid: pid };
                if (remember !== false) trCol.rememberAlpha(cls, pct);

                let nativeApp = trCol.nativeTransparencyApp(cls);
                if (nativeApp !== "") {
                    // A window may already have received a compositor-opacity
                    // rule before its app-specific backend was added (or from
                    // an older shell session). Drop that rule first; otherwise
                    // it still fades text and images on top of the native
                    // background-only transparency.
                    alphaApplier.lua =
                        '_G.serp_alpha = _G.serp_alpha or {}; ' +
                        'local a = "' + address + '"; ' +
                        'local r = _G.serp_alpha[a]; ' +
                        'if r then pcall(function() r:set_enabled(false) end) end; ' +
                        '_G.serp_alpha[a] = nil; return true';
                    alphaApplier.running = false;
                    alphaApplier.running = true;

                    nativeAlphaApplier.command = [
                        Caching.serpantinumDir + "/scripts/window-transparency.sh",
                        nativeApp, String(pct), String(pid || "")
                    ];
                    nativeAlphaApplier.running = false;
                    nativeAlphaApplier.running = true;
                    return;
                }

                // JSON.stringify gives a double-quoted, escaped literal; the
                // escapes JSON emits are all valid Lua ones, which matters for
                // the quotes and backslashes that turn up in window titles.
                let match = 'class = ' + JSON.stringify(cls) + ', title = ' + JSON.stringify(title) + ', fullscreen = false';

                // Below 1 we install a rule; at exactly 1 we only drop the old
                // one, so "100%" means untouched rather than a rule that
                // happens to be a no-op.
                alphaApplier.lua =
                    '_G.serp_alpha = _G.serp_alpha or {}; ' +
                    'local a = "' + address + '"; ' +
                    'local r = _G.serp_alpha[a]; ' +
                    'if r then pcall(function() r:set_enabled(false) end) end; ' +
                    '_G.serp_alpha[a] = nil; ' +
                    (v < 1
                        ? '_G.serp_alpha[a] = hl.window_rule({ match = { ' + match + ' }, opacity = ' + v + ' }); return true'
                        : 'return true');
                alphaApplier.running = false;
                alphaApplier.running = true;
            }

            // Drops our own rules, then reloads the config. The reload is the
            // part that makes this trustworthy: a rule created without keeping
            // its handle cannot be disabled afterwards, and re-parsing the
            // config is the only way to guarantee nothing is left applying an
            // opacity. `config-only` keeps it from re-probing the monitors.
            //
            // So "100%" here really means 100%, rather than "100% minus
            // whatever else happens to be in effect".
            function resetAll() {
                alphaApplier.lua =
                    'if _G.serp_alpha then ' +
                    'for _, r in pairs(_G.serp_alpha) do pcall(function() r:set_enabled(false) end) end ' +
                    'end; _G.serp_alpha = {}; return true';
                alphaApplier.running = false;
                alphaApplier.running = true;
                hardReset.running = false;
                hardReset.running = true;
                nativeAlphaResetter.running = false;
                nativeAlphaResetter.running = true;
                trCol.applied = ({});
                trCol.savedByClass = ({});
                trCol.restoreQueue = [];
                Config.setSetting("windowTransparency", {});
                for (let i = 0; i < windowsModel.count; i++) windowsModel.setProperty(i, "alpha", 100);
            }

            Process {
                id: hardReset
                running: false
                // Empty transparency.lua first, or the reload would load the old
                // persistent rules right back.
                command: ["bash", "-c", "\"$1\" '{}'; hyprctl reload config-only", "_",
                    Caching.serpantinumDir + "/scripts/window-transparency-rules.sh"]
            }

            function refresh() {
                winScanner.running = false;
                winScanner.running = true;
            }

            function rebuild(raw) {
                let wins = [];
                try { wins = JSON.parse(raw || "[]") || []; } catch (e) { wins = []; }

                // Rebuilding in place rather than clear()+append(): clearing
                // destroys the row delegates, and a slider being dragged at
                // that moment would lose the grab mid-gesture.
                let rows = [];
                for (let i = 0; i < wins.length; i++) {
                    let w = wins[i];
                    if (!w || !w.address) continue;
                    let a = String(w.address);
                    let cls = String(w.name || "?");
                    let title = String(w.title || "");
                    let prev = trCol.applied[a];
                    let saved = trCol.savedAlpha(cls);

                    // A saved class value is applied to every new instance of
                    // that application, including windows created after login.
                    if (prev === undefined && saved < 100) {
                        trCol.queueSavedAlpha(a, cls, title, saved, w.pid);
                        prev = trCol.applied[a];
                    }

                    // A window that renamed itself no longer matches its own
                    // rule, so reinstall it against the new title.
                    if (prev !== undefined && prev.alpha < 100 && prev.title !== title) {
                        trCol.applyAlpha(a, cls, title, prev.alpha, w.pid, false);
                    }

                    rows.push({
                        address: a,
                        name: cls,
                        detail: title,
                        pid: w.pid || "",
                        alpha: (prev !== undefined) ? prev.alpha : 100
                    });
                }
                rows.sort((x, y) => String(x.name).localeCompare(String(y.name)));

                let same = rows.length === windowsModel.count;
                if (same) {
                    for (let i = 0; i < rows.length; i++) {
                        if (windowsModel.get(i).address !== rows[i].address) { same = false; break; }
                    }
                }
                if (same) return;

                windowsModel.clear();
                for (let i = 0; i < rows.length; i++) windowsModel.append(rows[i]);
            }

            // Keep watching even while the card is closed so applications
            // launched later in the session receive their saved opacity.
            Timer {
                interval: 2500
                repeat: true
                running: true
                onTriggered: trCol.refresh()
            }

            // Restore one window at a time. Reusing a running Process for a
            // whole batch would otherwise cancel all but the last command.
            Timer {
                interval: 300
                repeat: true
                running: trCol.restoreQueue.length > 0
                onTriggered: {
                    let next = trCol.restoreQueue.slice();
                    let job = next.shift();
                    trCol.restoreQueue = next;
                    if (job)
                        trCol.applyAlpha(job.address, job.cls, job.title, job.alpha, job.pid, false);
                }
            }

            Component.onCompleted: {
                // Purge handles left by older versions of this card before
                // rebuilding the saved rules. Those rules match class/title,
                // not just the address used as their map key, so an entry for
                // a closed Code window could still fade a newly opened one.
                alphaApplier.lua =
                    'if _G.serp_alpha then ' +
                    'for _, r in pairs(_G.serp_alpha) do pcall(function() r:set_enabled(false) end) end ' +
                    'end; _G.serp_alpha = {}; return true';
                alphaApplier.running = false;
                alphaApplier.running = true;
                loadSaved();
                refresh();
            }

            Toggle {
                Layout.fillWidth: true
                checked: trCol.blurOn
                buttonText: I18n.t("overlay.transparency.blur", "Blur")
                onToggled: (val) => trCol.setBlur(val)
            }

            Text {
                Layout.fillWidth: true
                text: I18n.t("overlay.transparency.hint")
                color: ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(9)
                wrapMode: Text.WordWrap
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: card.s(190)
                clip: true
                spacing: card.s(4)
                model: windowsModel
                reuseItems: true

                delegate: Rectangle {
                    width: ListView.view ? ListView.view.width : 0
                    height: card.s(52)
                    radius: card.s(8)
                    color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: card.s(10)
                        anchors.rightMargin: card.s(10)
                        anchors.topMargin: card.s(5)
                        anchors.bottomMargin: card.s(5)
                        spacing: card.s(2)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: card.s(6)

                            Text {
                                Layout.fillWidth: true
                                text: model.name + (model.detail !== "" ? " \u2014 " + model.detail : "")
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(10)
                                elide: Text.ElideRight
                            }
                            Text {
                                text: model.alpha + "%"
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(9)
                            }
                        }

                        Draggable {
                            Layout.fillWidth: true
                            implicitHeight: card.s(16)
                            // Stops at 30%: below that a window is hard enough
                            // to pick out that you cannot find its slider again.
                            from: 30
                            to: 100
                            stepSize: 1
                            value: model.alpha
                            accentColor: ThemeBackend.blue
                            backgroundColor: ThemeBackend.surface0
                            onMoved: (val) => {
                                let v = Math.round(val);
                                windowsModel.setProperty(model.index, "alpha", v);
                                trCol.applyAlpha(model.address, model.name, model.detail, v, model.pid);
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: card.s(26)
                radius: card.s(8)
                color: resetArea.containsMouse
                    ? Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.18)
                    : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08)

                Text {
                    anchors.centerIn: parent
                    text: I18n.t("overlay.transparency.reset")
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(10)
                }

                MouseArea {
                    id: resetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: trCol.resetAll()
                }
            }
        }
    }

    // ---------------- Game mode (local) ----------------
    // Apps that switch it on while open, the optimisations applied while it
    // is active, and the ones kept on all the time. GameMode.qml applies them.
    Component {
        id: gamingBody

        ColumnLayout {
            id: gmCol
            spacing: card.s(8)

            property int tab: 0
            readonly property var optionLabels: ({
                "unload": I18n.t("overlay.gaming.opt.unload", "Unload wallpaper and widgets"),
                "unloadFloating": I18n.t("overlay.gaming.opt.unloadFloating", "Unload the sliding panel"),
                "pauseViz": I18n.t("overlay.gaming.opt.pauseViz", "Pause the music visualiser"),
                "hideSticker": I18n.t("overlay.gaming.opt.hideSticker", "Hide the floating image"),
                "opaque": I18n.t("overlay.gaming.opt.opaque", "Opaque windows"),
                "noBlur": I18n.t("overlay.gaming.opt.noBlur", "No blur"),
                "noAnim": I18n.t("overlay.gaming.opt.noAnim", "No animations"),
                "scanout": I18n.t("overlay.gaming.opt.scanout", "Direct scanout (fullscreen)"),
                "vrr": I18n.t("overlay.gaming.opt.vrr", "VRR (fullscreen)"),
                "commands": I18n.t("overlay.gaming.opt.commands", "Custom commands"),
                "perfProfile": I18n.t("overlay.gaming.opt.perfProfile", "Performance power profile")
            })

            Toggle {
                Layout.fillWidth: true
                id: gameManual
                checked: GameMode.manual
                buttonText: I18n.t("overlay.gaming.manual", "Turn on now")
                onToggled: (val) => {
                    GameMode.setManual(val);
                    gameManual.checked = Qt.binding(() => GameMode.manual);
                }
            }

            Text {
                Layout.fillWidth: true
                text: GameMode.active
                    ? (I18n.t("overlay.gaming.active", "Active") + (GameMode.runningGames.length > 0 ? " · " + GameMode.runningGames.join(", ") : ""))
                    : I18n.t("overlay.gaming.inactive", "Inactive")
                color: GameMode.active ? ThemeBackend.green : ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(10)
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(4)

                Repeater {
                    model: [I18n.t("overlay.gaming.tab.apps", "Games"),
                            I18n.t("overlay.gaming.tab.game", "In game"),
                            I18n.t("overlay.gaming.tab.always", "Always")]

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: card.s(26)
                        radius: ThemeBackend.clampedBorderRadius
                        color: gmCol.tab === index ? ThemeBackend.surface2 : (tabMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: gmCol.tab === index ? ThemeBackend.text : ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: card.s(10)
                            font.bold: gmCol.tab === index
                        }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gmCol.tab = index
                        }
                    }
                }
            }

            // Games: the listed apps, then the open windows to add.
            ColumnLayout {
                visible: gmCol.tab === 0
                Layout.fillWidth: true
                spacing: card.s(6)

                Text {
                    Layout.fillWidth: true
                    text: GameMode.apps.length > 0
                        ? I18n.t("overlay.gaming.apps_hint", "Game mode turns on while one of these is open:")
                        : I18n.t("overlay.gaming.apps_empty", "No game yet: add an open window below.")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(9)
                    wrapMode: Text.WordWrap
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: card.s(4)
                    Repeater {
                        model: GameMode.apps
                        delegate: Rectangle {
                            id: gameChip
                            required property var modelData
                            implicitWidth: gameChipText.implicitWidth + card.s(16)
                            implicitHeight: card.s(24)
                            radius: height / 2
                            color: gameChipMouse.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1
                            Text {
                                id: gameChipText
                                anchors.centerIn: parent
                                text: "✕ " + gameChip.modelData
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(10)
                            }
                            MouseArea {
                                id: gameChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GameMode.removeApp(gameChip.modelData)
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("overlay.gaming.add", "Open windows:")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(9)
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: card.s(4)
                    Repeater {
                        model: GameMode.openClasses.filter(c => GameMode.apps.indexOf(c) === -1)
                        delegate: Rectangle {
                            id: gameAddChip
                            required property var modelData
                            implicitWidth: gameAddChipText.implicitWidth + card.s(16)
                            implicitHeight: card.s(24)
                            radius: height / 2
                            color: gameAddChipMouse.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1
                            Text {
                                id: gameAddChipText
                                anchors.centerIn: parent
                                text: "+ " + gameAddChip.modelData
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: card.s(10)
                            }
                            MouseArea {
                                id: gameAddChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GameMode.addApp(gameAddChip.modelData)
                            }
                        }
                    }
                }
            }

            // In game / Always: one switch per optimisation, a separate list
            // per tab. A click breaks the Toggle's checked binding, so it is
            // bound back to the stored value right after.
            Repeater {
                model: gmCol.tab === 1 ? GameMode.optionKeys : []
                delegate: Toggle {
                    id: gameOpt
                    required property var modelData
                    Layout.fillWidth: true
                    checked: GameMode.gameOptions[modelData] === true
                    buttonText: gmCol.optionLabels[modelData] || modelData
                    onToggled: (val) => {
                        GameMode.setOption("game", modelData, val);
                        gameOpt.checked = Qt.binding(() => GameMode.gameOptions[gameOpt.modelData] === true);
                    }
                }
            }
            // Commands run by the "Custom commands" option (In game tab).
            Repeater {
                model: gmCol.tab === 1 ? [
                    { "key": "enter", "label": I18n.t("overlay.gaming.enter_cmd", "Command when game mode starts") },
                    { "key": "exit", "label": I18n.t("overlay.gaming.exit_cmd", "Command when game mode stops") }
                ] : []
                delegate: Input {
                    required property var modelData
                    Layout.fillWidth: true
                    placeholderText: modelData.label
                    text: modelData.key === "exit" ? GameMode.exitCommand : GameMode.enterCommand
                    baseColor: ThemeBackend.surface0
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                    cornerRadius: ThemeBackend.borderRadius
                    horizontalPadding: card.s(10)
                    verticalPadding: card.s(4)
                    fontPixelSize: card.s(10)
                    onAccepted: (finalText) => GameMode.setCommand(modelData.key, finalText)
                }
            }

            Repeater {
                model: gmCol.tab === 2 ? GameMode.optionKeys.slice() : []
                delegate: Toggle {
                    id: alwaysOpt
                    required property var modelData
                    Layout.fillWidth: true
                    checked: GameMode.alwaysOptions[modelData] === true
                    buttonText: gmCol.optionLabels[modelData] || modelData
                    onToggled: (val) => {
                        GameMode.setOption("always", modelData, val);
                        alwaysOpt.checked = Qt.binding(() => GameMode.alwaysOptions[alwaysOpt.modelData] === true);
                    }
                }
            }
        }
    }

    // ---------------- Floating image ----------------
    // A small pinned picture (supports GIFs) you resize by dragging the
    // card's own corner handle, matching end-4's FloatingImage widget.
    // Loads a local file path rather than downloading a URL to keep this
    // simple.
    //
    // The image is a SINGLE instance that always fills the entire card,
    // in both editing and sticker mode. Editing controls draw as overlays
    // on top of it (see card.bodyFillsCard / the header's scrim) instead
    // of taking their own layout space -- that used to make the picture
    // visibly resize and re-center every time the overlay opened or
    // closed, since the editing body (with its button row) and the
    // sticker body (without one) had different amounts of room left over
    // for the image.
    Component {
        id: floatingImageBody

        Item {
            id: imgRoot

            property var settings: Config.getSetting("overlayFloatingImage", { "path": "" })
            readonly property string imagePath: settings.path || ""
            onImagePathChanged: imgRetryTimer.attempts = 0

            // The picture itself, full-bleed, present in both modes.
            Loader {
                id: floatImgLoader
                anchors.fill: parent
                // Local: unloaded while hidden (game mode, fullscreen) so a
                // GIF stops decoding and repainting.
                active: imgRoot.imagePath !== "" && !card.hiddenForFullscreen
                sourceComponent: AnimatedImage {
                    source: "file://" + imgRoot.imagePath
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    playing: true
                }
            }

            // Some GIFs just stall in Loading forever instead of ever
            // reaching Ready or Error. Poll instead: still not ready after
            // a beat means recreate the image entirely (toggling `active`,
            // not reassigning `.source` -- that would permanently break its
            // declarative binding to imagePath).
            Timer {
                id: imgRetryTimer
                interval: 700
                repeat: true
                running: floatImgLoader.active && floatImgLoader.item
                    && floatImgLoader.item.status !== Image.Ready && attempts < 5
                property int attempts: 0
                onTriggered: {
                    attempts++;
                    floatImgLoader.active = false;
                    floatImgLoader.active = true;
                }
            }

            Text {
                anchors.centerIn: parent
                visible: floatImgLoader.item && floatImgLoader.item.status !== Image.Ready && imgRetryTimer.attempts >= 5
                text: I18n.t("overlay.floatingimage.error")
                color: ThemeBackend.red
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(10)
            }

            // Nothing picked yet: the only way in is the sticker browser --
            // no manual path typing. Only relevant while editing.
            ColumnLayout {
                anchors.centerIn: parent
                anchors.margins: card.s(12)
                width: parent.width - card.s(24)
                spacing: card.s(8)
                visible: imgRoot.imagePath === "" && !card.isFloatingSticker

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("overlay.floatingimage.hint")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(10)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                ClickButton {
                    Layout.fillWidth: true
                    implicitHeight: card.s(30)
                    cornerRadius: card.s(8)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    buttonIcon: "folder_open"
                    buttonText: I18n.t("overlay.floatingimage.choose")
                    textFontSize: card.s(11)
                    onClicked: StickerPickerController.open()
                }
            }

        }
    }
}

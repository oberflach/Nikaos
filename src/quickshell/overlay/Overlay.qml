import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../reusables"
import "../"

// Widget overlay (SUPER + G): a dimmed full-screen canvas holding small
// draggable tool cards (recorder, volume, resources, crosshair settings).
// The crosshair itself lives in CrosshairLayer so it survives this closing.
Scope {
    id: overlayScope

    property bool isOpen: false

    // Persisted: which cards are shown, where they sit, and which stay
    // visible even after the overlay itself closes (pinned).
    property var overlaySettings: Config.getSetting("overlay", {
        "cards": ["recorder", "volume"],
        "positions": {},
        "pinned": []
    })

    Connections {
        target: Config
        function onSettingsLoaded() {
            overlayScope.overlaySettings = Config.getSetting("overlay", {
                "cards": ["recorder", "volume"],
                "positions": {},
                "pinned": []
            });
        }
    }

    readonly property var openCards: overlaySettings.cards || []
    readonly property var pinnedCards: (overlaySettings.pinned || []).filter(id => overlayScope.openCards.indexOf(id) !== -1)

    function isPinned(id) {
        return overlayScope.pinnedCards.indexOf(id) !== -1;
    }

    function togglePin(id) {
        let next = JSON.parse(JSON.stringify(overlayScope.overlaySettings));
        if (!next.pinned) next.pinned = [];
        let idx = next.pinned.indexOf(id);
        if (idx === -1) next.pinned.push(id);
        else next.pinned.splice(idx, 1);
        overlayScope.saveSettings(next);
    }

    function saveSettings(next) {
        overlayScope.overlaySettings = next;
        Config.setSetting("overlay", next);
    }

    function isCardOpen(id) {
        return overlayScope.openCards.indexOf(id) !== -1;
    }

    function toggleCard(id) {
        let next = JSON.parse(JSON.stringify(overlayScope.overlaySettings));
        if (!next.cards) next.cards = [];
        let idx = next.cards.indexOf(id);
        if (idx === -1) next.cards.push(id);
        else next.cards.splice(idx, 1);
        overlayScope.saveSettings(next);
    }

    function cardPosition(id, fallbackX, fallbackY) {
        let pos = overlayScope.overlaySettings.positions || {};
        if (pos[id] && pos[id].x !== undefined) return pos[id];
        return { "x": fallbackX, "y": fallbackY };
    }

    function saveCardPosition(id, x, y) {
        let next = JSON.parse(JSON.stringify(overlayScope.overlaySettings));
        if (!next.positions) next.positions = {};
        if (!next.positions[id]) next.positions[id] = {};
        next.positions[id].x = Math.round(x);
        next.positions[id].y = Math.round(y);
        overlayScope.saveSettings(next);
    }

    function saveCardSize(id, w, h) {
        let next = JSON.parse(JSON.stringify(overlayScope.overlaySettings));
        if (!next.positions) next.positions = {};
        if (!next.positions[id]) next.positions[id] = {};
        next.positions[id].w = Math.round(w);
        next.positions[id].h = Math.round(h);
        overlayScope.saveSettings(next);
    }

    CrosshairLayer {}

    LazyLoader {
        active: overlayScope.isOpen || overlayScope.pinnedCards.length > 0

        PanelWindow {
            id: overlayWindow
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            visible: true

            WlrLayershell.namespace: "qs-widget-overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: overlayScope.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

            screen: Quickshell.cursorScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function s(val) { return Scaler.s(val); }

            // When only pinned cards remain (overlay closed), restrict the
            // click-accepting area to just those cards so the rest of the
            // screen stays fully click-through. When fully open, the whole
            // window is interactive (item covers everything).
            mask: Region {
                item: overlayScope.isOpen ? fullArea : null
                regions: overlayScope.isOpen ? [] : overlayWindow.cardsMaskItems.map(it => regionComponent.createObject(overlayWindow, { "item": it }))
            }
            property Component regionComponent: Component { Region {} }
            readonly property var cardsMaskItems: {
                let arr = [];
                for (let i = 0; i < cardsRepeater.count; i++) {
                    let it = cardsRepeater.itemAt(i);
                    // Skip cards that are hidden (not pinned, overlay closed)
                    // and the pinned floating-image sticker, which is meant
                    // to be fully click-through once the overlay is closed.
                    if (it && it.shouldShow && !it.isFloatingSticker) arr.push(it);
                }
                return arr;
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                visible: overlayScope.isOpen
                color: Qt.alpha(ThemeBackend.crust, 0.55)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: overlayScope.isOpen = false
                }
            }

            Item {
                id: fullArea
                anchors.fill: parent
                focus: overlayScope.isOpen
                Keys.onEscapePressed: overlayScope.isOpen = false

                // --- Card picker ---
                Rectangle {
                    id: picker
                    visible: overlayScope.isOpen
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: overlayWindow.s(46)
                    width: pickerRow.implicitWidth + overlayWindow.s(20)
                    height: overlayWindow.s(52)
                    radius: ThemeBackend.clampedBorderRadius
                    color: Qt.alpha(ThemeBackend.base, 0.96)
                    border.color: ThemeBackend.surface1
                    border.width: 1

                    scale: 0.94
                    Component.onCompleted: scale = 1
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                    RowLayout {
                        id: pickerRow
                        anchors.centerIn: parent
                        spacing: overlayWindow.s(8)

                        Repeater {
                            model: [
                                { "id": "recorder",  "icon": "screen_record", "label": I18n.t("overlay.cards.recorder") },
                                { "id": "volume",    "icon": "volume_up", "label": I18n.t("overlay.cards.volume") },
                                { "id": "resources", "icon": "browse_activity", "label": I18n.t("overlay.cards.resources") },
                                { "id": "crosshair", "icon": "point_scan", "label": I18n.t("overlay.cards.crosshair") },
                                { "id": "notes",     "icon": "sticky_note_2", "label": I18n.t("overlay.cards.notes") },
                                { "id": "apps", "icon": "apps", "label": I18n.t("overlay.cards.apps") },
                                { "id": "transparency", "icon": "opacity", "label": I18n.t("overlay.cards.transparency") },
                                { "id": "floatingImage", "icon": "imagesmode", "label": I18n.t("overlay.cards.floatingImage") },
                                { "id": "gaming", "icon": "sports_esports", "label": I18n.t("overlay.cards.gaming", "Game mode") },
                                { "id": "vpn", "icon": "vpn_lock", "label": "VPN" }
                            ].filter(c => c.id !== "vpn" || Vpn.configured)

                            delegate: Rectangle {
                                required property var modelData
                                // vpn isn't a draggable card like the others -- it's a
                                // straight on/off toggle, so it reflects Vpn.connected
                                // instead of going through the open-cards list.
                                readonly property bool active: modelData.id === "vpn" ? Vpn.connected : overlayScope.isCardOpen(modelData.id)

                                implicitWidth: chipRow.implicitWidth + overlayWindow.s(18)
                                implicitHeight: overlayWindow.s(34)
                                radius: ThemeBackend.clampedBorderRadius
                                color: active ? ThemeBackend.surface2 : (chipMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
                                border.color: active ? ThemeBackend.text : "transparent"
                                border.width: active ? overlayWindow.s(1.5) : 0
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: overlayWindow.s(6)

                                    Text {
                                        text: modelData.icon
                                        color: active ? ThemeBackend.text : ThemeBackend.subtext0
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: overlayWindow.s(16)
                                    }
                                    Text {
                                        text: modelData.label
                                        color: active ? ThemeBackend.text : ThemeBackend.subtext0
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: overlayWindow.s(12)
                                        font.bold: active
                                    }
                                }

                                MouseArea {
                                    id: chipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.id === "vpn" ? Vpn.toggle() : overlayScope.toggleCard(modelData.id)
                                }
                            }
                        }
                    }
                }

                // --- Cards ---
                // The model is the stable "which cards are toggled on" list,
                // NOT the open/closed-dependent visibleCards -- that list's
                // composition (and each card's index within it) used to
                // change every time the overlay opened/closed, which made
                // the Repeater destroy and recreate pinned cards (losing
                // their position/animation state and flashing their old
                // background for a frame). Each delegate now just hides
                // itself via shouldShow instead of being torn down.
                Repeater {
                    id: cardsRepeater
                    model: overlayScope.openCards

                    delegate: OverlayCard {
                        scaleFn: overlayWindow.s
                        // Lay cards out in a row, wrapping to a second line rather
                        // than marching off the right edge: past the sixth card the
                        // old formula put them beyond the screen, where they opened
                        // invisibly.
                        readonly property int perRow: Math.max(1, Math.floor((overlayWindow.width - overlayWindow.s(60)) / overlayWindow.s(330)))
                        defaultX: overlayWindow.s(60) + ((index % perRow) * overlayWindow.s(330))
                        defaultY: overlayWindow.s(170) + (Math.floor(index / perRow) * overlayWindow.s(260))
                        maxX: overlayWindow.width
                        maxY: overlayWindow.height
                        pinned: overlayScope.isPinned(cardId)
                        overlayOpen: overlayScope.isOpen
                        shouldShow: overlayScope.isOpen || overlayScope.isPinned(cardId)
                        onCloseRequested: overlayScope.toggleCard(cardId)
                        onMoved: (px, py) => overlayScope.saveCardPosition(cardId, px, py)
                        onResized: (w, h) => overlayScope.saveCardSize(cardId, w, h)
                        onOverlayCloseRequested: overlayScope.isOpen = false
                        onPinToggled: overlayScope.togglePin(cardId)
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "overlay"
        function toggle(): void { overlayScope.isOpen = !overlayScope.isOpen; }
        function open(): void { overlayScope.isOpen = true; }
        function close(): void { overlayScope.isOpen = false; }
        // Local: open or close one card, e.g. "gaming".
        function toggleCard(id: string): void { overlayScope.toggleCard(id); }
    }

    GlobalShortcut {
        name: "overlayToggle"
        description: "Toggle the widget overlay"
        onPressed: overlayScope.isOpen = !overlayScope.isOpen
    }
}

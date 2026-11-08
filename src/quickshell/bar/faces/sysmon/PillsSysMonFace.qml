// Pre-2.2.4 look: rounded pills filled by a wave, kept as the "pills"
// sysmon style. One file for both bar orientations; the side bar shows
// square icon-only pills.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../../reusables"
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    property string orientation: (activeTarget && activeTarget.orientation !== undefined) ? activeTarget.orientation : "horizontal"
    readonly property bool isVertical: orientation === "vertical"

    readonly property var activeTarget: widget || module
    readonly property bool isCompact: activeTarget ? activeTarget.isCompact : false
    readonly property var barWindow: activeTarget ? activeTarget.barWindow : null

    property int configRevision: 0

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() { root.configRevision++; }
        function onRawSettingsChanged() { root.configRevision++; }
    }

    property string circleStyle: {
        if (widget && widget !== root && widget.sysmonStyle !== undefined) return widget.sysmonStyle;
        if (module && module.sysmonStyle !== undefined) return module.sysmonStyle;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (bs.sysmonStyle) return bs.sysmonStyle;
            if (bs.sysmon && bs.sysmon.style) return bs.sysmon.style;
        }
        return "wave";
    }

    readonly property bool useSineWave: circleStyle !== "circle"

    property var activeStats: {
        if (widget && widget !== root && widget.sysmonStats !== undefined) return widget.sysmonStats;
        if (module && module.sysmonStats !== undefined) return module.sysmonStats;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (Array.isArray(bs.sysmonStats)) return bs.sysmonStats;
            if (bs.sysmon && Array.isArray(bs.sysmon.stats)) return bs.sysmon.stats;
            if (bs.sysmonShowCpu !== undefined || bs.sysmonShowRam !== undefined || bs.sysmonShowTemp !== undefined || bs.sysmonShowDisk !== undefined) {
                let stats = [];
                if (bs.sysmonShowCpu !== false) stats.push("cpu");
                if (bs.sysmonShowRam !== false) stats.push("ram");
                if (bs.sysmonShowTemp !== false) stats.push("temp");
                if (bs.sysmonShowDisk === true) stats.push("disk");
                return stats;
            }
        }
        return ["cpu", "ram", "temp"];
    }

    property bool showLayout: (!barWindow || (root.activeTarget && root.activeTarget.isPreview)) ? true : false
    property int circleSize: barWindow ? barWindow.cs(isCompact ? 22 : 28) : (isCompact ? 22 : 28)

    property bool isSysVisible: (!activeTarget || activeTarget.moduleActive) && showLayout
    property color basePrimary: (ThemeBackend.primary !== undefined && ThemeBackend.primary !== "") ? ThemeBackend.primary : ThemeBackend.mauve

    property bool isSubscribed: false

    function updateSubscription() {
        if (isSysVisible && !isSubscribed) {
            isSubscribed = true;
            SysData.subscribe();
        } else if (!isSysVisible && isSubscribed) {
            isSubscribed = false;
            SysData.unsubscribe();
        }
    }

    Component.onCompleted: updateSubscription()
    Component.onDestruction: {
        if (isSubscribed) {
            isSubscribed = false;
            SysData.unsubscribe();
        }
    }
    onIsSysVisibleChanged: updateSubscription()

    readonly property real layoutLength: isVertical ? sysLayout.implicitHeight : sysLayout.implicitWidth
    property real targetLength: ((!activeTarget || activeTarget.moduleActive) && layoutLength > 0) ? (layoutLength + (barWindow ? barWindow.cs(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    property bool isFaceVisible: showLayout && targetLength > 0

    function syncImplicitSize() {
        let cross = module ? module.thickness : (parent ? (isVertical ? parent.width : parent.height) : 0);
        implicitWidth = isVertical ? cross : targetLength;
        implicitHeight = isVertical ? targetLength : cross;
    }

    onTargetLengthChanged: syncImplicitSize()
    onIsVerticalChanged: syncImplicitSize()
    onModuleChanged: syncImplicitSize()
    onParentChanged: syncImplicitSize()

    Timer {
        running: true
        interval: 0
        onTriggered: root.syncImplicitSize()
    }

    Timer {
        running: (!activeTarget || activeTarget.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady && !root.showLayout
        interval: 100
        onTriggered: root.showLayout = true
    }

    transform: Translate {
        x: (root.isVertical || root.showLayout) ? 0 : (barWindow ? barWindow.cs(60) : 60)
        y: (!root.isVertical || root.showLayout) ? 0 : (barWindow ? barWindow.cs(60) : 60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    property real globalWavePhase: 0.0
    NumberAnimation on globalWavePhase {
        from: 0
        to: Math.PI * 2
        duration: 1800
        loops: Animation.Infinite
        running: root.isSysVisible
    }

    component SysMonPill: Rectangle {
        id: pillRoot
        property real value: 0
        property string textVal: ""
        property string icon: ""
        property color accentColor: ThemeBackend.mauve
        property bool initAnimTrigger: false

        property real animValue: value
        Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

        property real fillRatio: Math.max(0.0, Math.min(1.0, isNaN(animValue) ? 0.0 : animValue))
        property real fillY: height * (1.0 - fillRatio)
        property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? (barWindow ? barWindow.cs(3.5) : 3.5) * Math.sin(fillRatio * Math.PI) : 0
        property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(root.globalWavePhase) - Math.cos(root.globalWavePhase))

        height: sysLayout.pillHeight
        width: sysLayout.pillWidth
        radius: Math.min(Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.cs(2) : 2)), height / 2)
        color: Qt.alpha(root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        border.color: Qt.alpha(root.isCompact ? ThemeBackend.surface2 : ThemeBackend.surface1, (barWindow && barWindow.barOpacity !== undefined) ? barWindow.barOpacity : 1.0)
        border.width: 1
        clip: true

        Timer {
            running: (!root.activeTarget || root.activeTarget.moduleActive) && root.showLayout && !initAnimTrigger
            interval: 150
            onTriggered: initAnimTrigger = true
        }

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            y: initAnimTrigger ? 0 : (barWindow ? barWindow.cs(15) : 15)
            Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

        Canvas {
            id: pillCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            renderStrategy: Canvas.Cooperative

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (pillRoot.fillRatio <= 0) return;

                ctx.save();
                var r = pillRoot.radius;
                ctx.beginPath();
                ctx.moveTo(r, 0);
                ctx.lineTo(width - r, 0);
                ctx.quadraticCurveTo(width, 0, width, r);
                ctx.lineTo(width, height - r);
                ctx.quadraticCurveTo(width, height, width - r, height);
                ctx.lineTo(r, height);
                ctx.quadraticCurveTo(0, height, 0, height - r);
                ctx.lineTo(0, r);
                ctx.quadraticCurveTo(0, 0, r, 0);
                ctx.closePath();
                ctx.clip();

                ctx.beginPath();
                ctx.moveTo(0, pillRoot.fillY);
                if (pillRoot.waveAmp > 0) {
                    var cp1y = pillRoot.fillY + Math.sin(root.globalWavePhase) * pillRoot.waveAmp;
                    var cp2y = pillRoot.fillY + Math.cos(root.globalWavePhase + Math.PI) * pillRoot.waveAmp;
                    ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, pillRoot.fillY);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                } else {
                    ctx.lineTo(width, pillRoot.fillY);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                }
                ctx.closePath();

                var grad = ctx.createLinearGradient(0, 0, 0, height);
                grad.addColorStop(0, Qt.lighter(pillRoot.accentColor, 1.25).toString());
                grad.addColorStop(1, pillRoot.accentColor.toString());
                ctx.fillStyle = grad;
                ctx.globalAlpha = 0.95;
                ctx.fill();
                ctx.restore();
            }

            Connections {
                target: root
                enabled: root.isSysVisible && pillRoot.waveAmp > 0
                function onGlobalWavePhaseChanged() { pillCanvas.requestPaint(); }
            }

            Connections {
                target: pillRoot
                enabled: root.isSysVisible
                function onFillRatioChanged() { pillCanvas.requestPaint(); }
                function onAccentColorChanged() { pillCanvas.requestPaint(); }
            }
        }

        Row {
            id: baseContentRow
            anchors.centerIn: parent
            spacing: barWindow ? barWindow.cs(root.isCompact ? 3 : 4) : (root.isCompact ? 3 : 4)

            Text {
                text: icon
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.cs(root.isCompact ? 13.5 : 14.5) : (root.isCompact ? 13.5 : 14.5)
                color: root.isCompact ? ThemeBackend.text : ThemeBackend.subtext0
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: textVal
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.cs(root.isCompact ? 12 : 13) : (root.isCompact ? 12 : 13)
                font.bold: true
                color: ThemeBackend.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            id: waveClipBox
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height, Math.max(0, (parent.height * pillRoot.fillRatio) - pillRoot.waveCenterOffset))
            clip: true
            visible: pillRoot.fillRatio > 0

            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: pillRoot.height

                Row {
                    anchors.centerIn: parent
                    spacing: barWindow ? barWindow.cs(root.isCompact ? 3 : 4) : (root.isCompact ? 3 : 4)

                    Text {
                        text: icon
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: barWindow ? barWindow.cs(root.isCompact ? 13.5 : 14.5) : (root.isCompact ? 13.5 : 14.5)
                        color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.75)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: textVal
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: barWindow ? barWindow.cs(root.isCompact ? 12 : 13) : (root.isCompact ? 12 : 13)
                        font.bold: true
                        color: ThemeBackend.crust
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    AxisFlow {
        id: sysLayout
        vertical: root.isVertical
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.cs(root.isCompact ? 5 : 6) : (root.isCompact ? 5 : 6)
        property int pillHeight: barWindow ? barWindow.cs(root.isCompact ? 28 : 30) : (root.isCompact ? 28 : 30)
        property int pillWidth: root.isVertical ? pillHeight : (barWindow ? barWindow.cs(root.isCompact ? 48 : 52) : (root.isCompact ? 48 : 52))

        // Local: one pill per stat, in the order chosen in the settings
        // (drag chips under Bar > System monitor).
        Repeater {
            model: root.activeStats
            delegate: SysMonPill {
                required property string modelData
                readonly property string stat: modelData
                readonly property real raw: {
                    if (stat === "gpu") return SysData.gpuPercent;
                    if (stat === "cpu") return SysData.cpu;
                    if (stat === "ram") return SysData.ramPercent;
                    if (stat === "temp") return SysData.temp;
                    if (stat === "disk") return SysData.diskPercent;
                    return 0;
                }
                value: isNaN(raw) ? 0 : Math.max(0, Math.min(1, raw / 100.0))
                textVal: root.isVertical ? "" : (isNaN(raw) ? 0 : Math.round(raw)) + (stat === "temp" ? "°" : "%")
                icon: {
                    if (stat === "gpu") return String.fromCodePoint(0xF08AE);
                    if (stat === "cpu") return "\uF2DB";
                    if (stat === "ram") return "\uEFC5";
                    if (stat === "temp") return "\uF2C9";
                    if (stat === "disk") return "󰋊";
                    return "";
                }
                accentColor: ThemeBackend.iconShade(stat)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: !(root.activeTarget && root.activeTarget.isPreview)
        onClicked: {
            FloatingController.showSystemUsage(root.barWindow ? root.barWindow.screen : null);
        }
    }
}

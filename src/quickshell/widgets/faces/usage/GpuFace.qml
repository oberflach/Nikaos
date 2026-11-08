import QtQuick
import Quickshell
import "../../../reusables"
import "../../../"

UsageFaceBase {
    id: root

    property real rawGpu: isNaN(SysData.gpuPercent) ? 0.0 : SysData.gpuPercent / 100.0
    property real gpuUsage: rawGpu
    Behavior on gpuUsage { enabled: root.visible; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    SystemUsageCard {
        shadeLight: root.shadeLight
        anchors.fill: parent
        blurred: true
        bgOpacity: ThemeBackend.elementOpacity
        value: root.gpuUsage
        colorBase: Qt.alpha(ThemeBackend.surface0, root.backgroundOpacity)
        colorFill: Qt.lighter(ThemeBackend.red, 1.25)
        icon: String.fromCodePoint(0xF08AE)
        title: I18n.t("quickactions.systemusage.gpu", "GPU")
        valueText: Math.round(root.gpuUsage * 100) + "%"
        isLive: root.visible
        compact: root.compactMode
        scaleFunc: Scaler.s
    }
}

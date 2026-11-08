import QtQuick
import Quickshell
import "../../../reusables"
import "../../../"

UsageFaceBase {
    id: root

    property real rawTemp: isNaN(SysData.temp) ? 0.0 : SysData.temp
    property real tempC: rawTemp
    Behavior on tempC { enabled: root.visible; NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }

    SystemUsageCard {
        shadeLight: root.shadeLight
        anchors.fill: parent
        blurred: true
        bgOpacity: ThemeBackend.elementOpacity
        value: Math.max(0.0, Math.min(1.0, root.tempC / 100.0))
        colorBase: Qt.alpha(ThemeBackend.surface0, root.backgroundOpacity)
        colorFill: ThemeBackend.mauve
        icon: String.fromCodePoint(0xF050F)
        title: I18n.t("quickactions.systemusage.temp")
        valueText: Math.round(root.tempC) + "°"
        isLive: root.visible
        compact: root.compactMode
        scaleFunc: Scaler.s
    }
}

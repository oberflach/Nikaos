import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Local: per-icon shades of the wallpaper accent for the bar modules.
SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    readonly property var iconShadeMeta: ({
        "cpu": { "icon": "", "name": I18n.t("guide.theme.iconshades.names.cpu", "CPU") },
        "ram": { "icon": "", "name": I18n.t("guide.theme.iconshades.names.ram", "RAM") },
        "temp": { "icon": "", "name": I18n.t("guide.theme.iconshades.names.temp", "Temperature") },
        "disk": { "icon": "󰋊", "name": I18n.t("guide.theme.iconshades.names.disk", "Storage") },
        "gpu": { "icon": "󰢮", "name": I18n.t("guide.theme.iconshades.names.gpu", "GPU") },
        "wifi": { "icon": "󰖩", "name": I18n.t("guide.theme.iconshades.names.wifi", "Wi-Fi") },
        "bt": { "icon": "󰂯", "name": I18n.t("guide.theme.iconshades.names.bt", "Bluetooth") },
        "vol": { "icon": "󰕾", "name": I18n.t("guide.theme.iconshades.names.vol", "Volume") },
        "bat": { "icon": "󰁹", "name": I18n.t("guide.theme.iconshades.names.bat", "Battery") }
    })

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "icon_shades"
        icon: "󰏘"
        title: I18n.t("guide.theme.iconshades.title", "Icon shades")
        description: I18n.t("guide.theme.iconshades.desc", "Hue and brightness offset of each bar icon from the wallpaper colour")
        searchKeywords: "icon shade hue tint colour color nuance bar modules wifi bluetooth volume battery cpu ram"

        ClickButton {
            implicitHeight: section.rootObj.s(30)
            buttonText: I18n.t("guide.theme.iconshades.reset", "Reset")
            buttonIcon: "󰑐"
            accentColor: ThemeBackend.surface0
            textColor: ThemeBackend.text
            cornerRadius: ThemeBackend.borderRadius
            horizontalPadding: section.rootObj.s(12)
            iconFontSize: section.rootObj.s(14)
            textFontSize: section.rootObj.s(11)
            onTriggered: ThemeBackend.resetIconShades()
        }
    }

    Repeater {
        model: ThemeBackend.iconShadeIds

        delegate: SettingsRow {
            id: shadeRow
            required property var modelData
            readonly property var info: section.iconShadeMeta[modelData] || ({ "icon": "", "name": modelData })
            readonly property var params: ThemeBackend.iconShadeParams(modelData)
            readonly property color swatch: ThemeBackend.iconShade(modelData)
            Layout.fillWidth: true
            rootObj: section.tab.rootObj
            icon: info.icon
            title: info.name
            description: I18n.t("guide.theme.iconshades.hue", "Hue") + " " + Math.round(params.h * 360) + "° · "
                + I18n.t("guide.theme.iconshades.light", "Brightness") + " " + Math.round(params.l * 100) + "%"

            RowLayout {
                spacing: section.rootObj.s(6)

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: section.rootObj.s(26)
                    implicitHeight: section.rootObj.s(18)
                    radius: section.rootObj.s(6)
                    color: shadeRow.swatch
                    border.width: 1
                    border.color: Qt.alpha(ThemeBackend.surface2, 0.6)
                }
                Text {
                    text: "T"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: section.rootObj.s(10)
                    Layout.alignment: Qt.AlignVCenter
                }
                Draggable {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: section.rootObj.s(6)
                    implicitWidth: section.rootObj.s(120)
                    implicitHeight: section.rootObj.s(16)
                    from: -0.5
                    to: 0.5
                    stepSize: 0.01
                    defaultValue: (ThemeBackend.iconShadeDefaults[shadeRow.modelData] || {}).h || 0
                    showValueBubble: true
                    valueFormatter: function(v) { return (v >= 0 ? "+" : "") + Math.round(v * 360) + "°" }
                    value: shadeRow.params.h
                    backgroundColor: ThemeBackend.surface0
                    accentColor: shadeRow.swatch
                    handleColor: ThemeBackend.text
                    handleBorderColor: ThemeBackend.mantle
                    onMoved: function(val) {
                        ThemeBackend.previewIconShade(shadeRow.modelData, val, shadeRow.params.l);
                    }
                    onDragFinished: ThemeBackend.commitIconShade(shadeRow.modelData)
                }
                Text {
                    text: "L"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: section.rootObj.s(10)
                    Layout.alignment: Qt.AlignVCenter
                }
                Draggable {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: section.rootObj.s(6)
                    implicitWidth: section.rootObj.s(120)
                    implicitHeight: section.rootObj.s(16)
                    from: -0.5
                    to: 0.5
                    stepSize: 0.01
                    defaultValue: (ThemeBackend.iconShadeDefaults[shadeRow.modelData] || {}).l || 0
                    showValueBubble: true
                    valueFormatter: function(v) { return (v >= 0 ? "+" : "") + Math.round(v * 100) + "%" }
                    value: shadeRow.params.l
                    backgroundColor: ThemeBackend.surface0
                    accentColor: shadeRow.swatch
                    handleColor: ThemeBackend.text
                    handleBorderColor: ThemeBackend.mantle
                    onMoved: function(val) {
                        ThemeBackend.previewIconShade(shadeRow.modelData, shadeRow.params.h, val);
                    }
                    onDragFinished: ThemeBackend.commitIconShade(shadeRow.modelData)
                }
            }
        }
    }
}

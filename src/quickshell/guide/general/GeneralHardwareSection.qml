import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Machine-specific features, off by default so other hardware is left alone:
// convertible tablet mode, battery conservation (Lenovo ideapad_acpi) and
// the VPN connection toggled from the Super+G overlay.
SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    readonly property var hw: Config.getSetting("hardware", {}) || {}
    property bool conservationAvailable: false

    function setHw(key, value) {
        let next = Object.assign({}, Config.getSetting("hardware", {}) || {});
        next[key] = value;
        Config.setSetting("hardware", next);
    }

    Process {
        running: section.tab.visible
        command: ["bash", Caching.serpantinumDir + "/scripts/conservation_mode.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: section.conservationAvailable = this.text.trim() !== "-1"
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "hardware_tablet"
        icon: "󰓶"
        title: I18n.t("guide.general.hardware.tablet.title", "Tablet mode")
        description: I18n.t("guide.general.hardware.tablet.desc", "For convertibles: watch the hinge, rotate the screen and show the on-screen keyboard in tablet mode")
        searchKeywords: "tablet convertible hinge rotate touch keyboard wvkbd tablette"

        Toggle {
            id: tabletToggle
            checked: section.hw.tabletMode === true
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                section.setHw("tabletMode", c);
                tabletToggle.checked = Qt.binding(() => section.hw.tabletMode === true);
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "hardware_conservation"
        icon: "󰂅"
        title: I18n.t("guide.general.hardware.conservation.title", "Battery conservation")
        description: section.conservationAvailable
            ? I18n.t("guide.general.hardware.conservation.desc", "Replace the night light quick action with the battery charge limit switch")
            : I18n.t("guide.general.hardware.conservation.unavailable", "Not supported on this laptop (needs the ideapad_acpi driver)")
        searchKeywords: "battery conservation charge limit lenovo ideapad batterie"

        Toggle {
            id: consToggle
            enabled: section.conservationAvailable
            checked: section.hw.conservation === true
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                section.setHw("conservation", c);
                consToggle.checked = Qt.binding(() => section.hw.conservation === true);
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "hardware_vpn"
        icon: "󰖂"
        title: I18n.t("guide.general.hardware.vpn.title", "VPN connection")
        description: I18n.t("guide.general.hardware.vpn.desc", "NetworkManager connection toggled from the Super+G overlay (empty: hidden). Press Enter to save")
        searchKeywords: "vpn wireguard wg0 networkmanager nmcli"

        Input {
            Layout.preferredWidth: section.rootObj.s(160)
            placeholderText: "wg0"
            text: section.hw.vpnConnection || ""
            baseColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            textColor: ThemeBackend.text
            subTextColor: ThemeBackend.subtext0
            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
            cornerRadius: ThemeBackend.borderRadius
            horizontalPadding: section.rootObj.s(10)
            verticalPadding: section.rootObj.s(5)
            fontPixelSize: section.rootObj.s(12)
            onAccepted: (finalText) => section.setHw("vpnConnection", String(finalText || "").trim())
        }
    }
}

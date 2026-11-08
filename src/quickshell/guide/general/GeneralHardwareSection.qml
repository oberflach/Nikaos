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

    // One-click setups (scripts/integrations.sh): kitty, vesktop, conservation.
    readonly property string integrationsScript: Caching.serpantinumDir + "/scripts/integrations.sh"
    property var integration: ({ "kitty": "", "vesktop": "", "conservation": "" })

    function refreshIntegrations() {
        integrationProbe.running = false;
        integrationProbe.running = true;
    }

    Process {
        id: integrationProbe
        running: section.tab.visible
        command: ["bash", "-c", "for i in kitty vesktop conservation; do printf '%s %s\\n' \"$i\" \"$(bash \"$1\" status \"$i\")\"; done", "_", section.integrationsScript]
        stdout: StdioCollector {
            onStreamFinished: {
                let next = {};
                this.text.split("\n").forEach(l => { let p = l.trim().split(" "); if (p.length === 2) next[p[0]] = p[1]; });
                section.integration = next;
            }
        }
    }

    Process {
        id: integrationSetup
        running: false
        onExited: section.refreshIntegrations()
    }

    function setupIntegration(name) {
        integrationSetup.command = ["bash", section.integrationsScript, "setup", name];
        integrationSetup.running = false;
        integrationSetup.running = true;
    }

    component SetupButton: ClickButton {
        property string target: ""
        readonly property string state: section.integration[target] || ""
        visible: state === "missing"
        implicitHeight: section.rootObj.s(30)
        buttonText: I18n.t("guide.general.hardware.setup", "Set up")
        buttonIcon: "󰒓"
        accentColor: ThemeBackend.mauve
        textColor: ThemeBackend.crust
        cornerRadius: ThemeBackend.borderRadius
        horizontalPadding: section.rootObj.s(12)
        iconFontSize: section.rootObj.s(14)
        textFontSize: section.rootObj.s(11)
        onTriggered: section.setupIntegration(target)
    }

    component SetupState: Text {
        property string target: ""
        readonly property string state: section.integration[target] || ""
        visible: state === "ok" || state === "unavailable"
        text: state === "ok" ? I18n.t("guide.general.hardware.ready", "Ready") : I18n.t("guide.general.hardware.not_installed", "Not installed")
        color: state === "ok" ? ThemeBackend.green : ThemeBackend.subtext0
        font.family: ThemeBackend.fontFamily
        font.pixelSize: section.rootObj.s(11)
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

        SetupButton { target: "conservation" }

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

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "hardware_kitty"
        icon: "󰄛"
        title: I18n.t("guide.general.hardware.kitty.title", "Kitty transparency")
        description: I18n.t("guide.general.hardware.kitty.desc", "Let the Super+G transparency card change Kitty's background without fading its text")
        searchKeywords: "kitty terminal transparency opacity super+g"

        SetupState { target: "kitty" }
        SetupButton { target: "kitty" }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "hardware_vesktop"
        icon: "󰙯"
        title: I18n.t("guide.general.hardware.vesktop.title", "Vesktop transparency")
        description: I18n.t("guide.general.hardware.vesktop.desc", "Add the Quick CSS the Super+G transparency card drives for Vesktop (Discord)")
        searchKeywords: "vesktop discord transparency css super+g"

        SetupState { target: "vesktop" }
        SetupButton { target: "vesktop" }
    }
}

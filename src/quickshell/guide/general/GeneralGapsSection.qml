import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Local: Hyprland window gaps, read from and written back to settings.lua.
SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    readonly property string hyprSettingsPath: (Quickshell.env("HOME") ?? "") + "/.config/hypr/config/settings.lua"
    property int hyprGapsIn: 0
    property int hyprGapsOut: 0
    property bool hyprGapsLoaded: false

    visible: hyprGapsLoaded

    // Debounced so stepping through values hits Hyprland once. Applied live
    // through hyprctl eval, not a reload, so the Super+G per-window opacity
    // rules survive. A manual change also ends the SUPER+U borderless mode
    // (gaps_toggle.sh).
    Timer {
        id: hyprGapsApplyTimer
        interval: 300
        onTriggered: Quickshell.execDetached(["bash", "-c",
            "sed -i -E \"s/^(\\s*gaps_in\\s*=\\s*)[0-9]+/\\1$1/; s/^(\\s*gaps_out\\s*=\\s*)[0-9]+/\\1$2/\" \"$3\" && rm -f \"${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum/gaps_saved\" && hyprctl eval \"hl.config({ general = { gaps_in = $1, gaps_out = $2 } })\"",
            "_", String(section.hyprGapsIn), String(section.hyprGapsOut), section.hyprSettingsPath])
    }

    Process {
        id: hyprGapsReader
        running: section.tab.visible
        command: ["bash", "-c", "grep -oE '^\\s*gaps_(in|out)\\s*=\\s*[0-9]+' \"$1\"", "_", section.hyprSettingsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let mIn = this.text.match(/gaps_in\s*=\s*(\d+)/);
                let mOut = this.text.match(/gaps_out\s*=\s*(\d+)/);
                if (mIn) section.hyprGapsIn = parseInt(mIn[1]);
                if (mOut) section.hyprGapsOut = parseInt(mOut[1]);
                section.hyprGapsLoaded = Boolean(mIn && mOut);
            }
        }
    }

    // Hyprland gaps live in its own config, not in settings.json:
    // read them when the tab opens, write them back shortly after a change.
    SettingsRow {
        rootObj: section.tab.rootObj
        visible: section.hyprGapsLoaded
        icon: "󰕰"
        title: I18n.t("guide.general.gaps_in.title") || "Gap between windows"
        description: I18n.t("guide.general.gaps_in.desc") || "Space around each tiled window (the gap between two windows is twice this value)"

        Draggable {
            Layout.rightMargin: section.rootObj.s(8)
            implicitWidth: section.rootObj.s(180)
            implicitHeight: section.rootObj.s(18)
            from: 0
            to: 40
            stepSize: 1
            defaultValue: 5
            showValueBubble: true
            valueFormatter: function(v) { return Math.round(v) + " px" }
            value: section.hyprGapsIn
            backgroundColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            handleColor: ThemeBackend.text
            handleBorderColor: ThemeBackend.mantle
            onMoved: function(val) {
                let rounded = Math.round(val);
                if (section.hyprGapsIn !== rounded) {
                    section.hyprGapsIn = rounded;
                    if (section.hyprGapsLoaded) hyprGapsApplyTimer.restart();
                }
            }
            onDragFinished: {
                if (section.hyprGapsLoaded) {
                    hyprGapsApplyTimer.stop();
                    hyprGapsApplyTimer.triggered();
                }
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        visible: section.hyprGapsLoaded
        icon: "󰹞"
        title: I18n.t("guide.general.gaps_out.title") || "Gap to screen edges"
        description: I18n.t("guide.general.gaps_out.desc") || "Space between windows and the screen edges"

        Draggable {
            Layout.rightMargin: section.rootObj.s(8)
            implicitWidth: section.rootObj.s(180)
            implicitHeight: section.rootObj.s(18)
            from: 0
            to: 40
            stepSize: 1
            defaultValue: 20
            showValueBubble: true
            valueFormatter: function(v) { return Math.round(v) + " px" }
            value: section.hyprGapsOut
            backgroundColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            handleColor: ThemeBackend.text
            handleBorderColor: ThemeBackend.mantle
            onMoved: function(val) {
                let rounded = Math.round(val);
                if (section.hyprGapsOut !== rounded) {
                    section.hyprGapsOut = rounded;
                    if (section.hyprGapsLoaded) hyprGapsApplyTimer.restart();
                }
            }
            onDragFinished: {
                if (section.hyprGapsLoaded) {
                    hyprGapsApplyTimer.stop();
                    hyprGapsApplyTimer.triggered();
                }
            }
        }
    }
}

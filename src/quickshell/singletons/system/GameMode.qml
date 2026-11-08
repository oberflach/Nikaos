pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../"

// Local: game mode, set up from the "Game mode" card of the Super+G overlay.
// It is active while one of the listed game apps has a window open, or when
// switched on by hand. Each optimisation can apply only while it is active
// ("game" options) or all the time ("always" options); the effective set
// drives Shell.qml (unloading), the generated Hyprland rules and a few
// one-shot actions (custom commands, power profile).
Item {
    id: root

    // Optimisations, in the order the card lists them.
    readonly property var optionKeys: ["unload", "unloadFloating", "hideSticker", "pauseViz", "opaque", "noBlur", "noAnim", "scanout", "vrr", "commands", "perfProfile"]
    readonly property var defaultGameOptions: ({
        "unload": true, "unloadFloating": false, "hideSticker": true, "pauseViz": true, "opaque": true, "noBlur": true, "noAnim": true,
        "scanout": true, "vrr": true, "commands": false, "perfProfile": false
    })

    // Older settings stored a plain boolean (the manual switch).
    readonly property var settings: {
        let raw = Config.getSetting("gameMode", {});
        if (raw === true || raw === false) return { "manual": raw };
        return (raw && typeof raw === "object") ? raw : {};
    }
    readonly property bool manual: root.settings.manual === true
    readonly property var apps: Array.isArray(root.settings.apps) ? root.settings.apps : []
    readonly property var gameOptions: Object.assign({}, root.defaultGameOptions, root.settings.game || {})
    readonly property var alwaysOptions: root.settings.always || ({})

    // Lower-cased classes of the open windows.
    property var openClasses: []
    readonly property var runningGames: root.apps.filter(a => root.openClasses.indexOf(String(a).toLowerCase()) !== -1)
    readonly property bool active: root.manual || root.runningGames.length > 0

    function enabled(key) {
        return root.alwaysOptions[key] === true || (root.active && root.gameOptions[key] === true);
    }
    readonly property var effective: {
        let out = {};
        for (let i = 0; i < root.optionKeys.length; i++) out[root.optionKeys[i]] = root.enabled(root.optionKeys[i]);
        return out;
    }
    readonly property bool unload: root.effective.unload === true
    readonly property bool hideSticker: root.effective.hideSticker === true
    readonly property bool unloadFloating: root.effective.unloadFloating === true
    readonly property bool pauseViz: root.effective.pauseViz === true

    // Hyprland part, as the comma list window-transparency-rules.sh takes.
    readonly property string hyprFlags: ["opaque", "noBlur", "noAnim", "scanout", "vrr"]
        .filter(k => root.effective[k]).join(",")

    function save(next) {
        Config.setSetting("gameMode", next);
    }
    function copySettings() {
        return JSON.parse(JSON.stringify(root.settings));
    }
    function setManual(on) {
        let next = root.copySettings();
        next.manual = on;
        root.save(next);
    }
    function addApp(cls) {
        let key = String(cls || "").toLowerCase();
        if (key === "" || root.apps.indexOf(key) !== -1) return;
        let next = root.copySettings();
        next.apps = root.apps.concat([key]);
        root.save(next);
    }
    function removeApp(cls) {
        let next = root.copySettings();
        next.apps = root.apps.filter(a => a !== cls);
        root.save(next);
    }
    readonly property string enterCommand: String(root.settings.enterCommand || "").trim()
    readonly property string exitCommand: String(root.settings.exitCommand || "").trim()
    function setCommand(which, text) {
        let next = root.copySettings();
        next[which === "exit" ? "exitCommand" : "enterCommand"] = String(text || "");
        root.save(next);
    }

    function setOption(group, key, on) {
        let next = root.copySettings();
        let base = group === "always" ? Object.assign({}, root.alwaysOptions) : Object.assign({}, root.gameOptions);
        base[key] = on;
        next[group] = base;
        root.save(next);
    }

    IpcHandler {
        target: "gamemode"
        function toggle(): void { root.setManual(!root.manual); }
        function on(): void { root.setManual(true); }
        function off(): void { root.setManual(false); }
        function status(): string { return root.active ? "on " + root.hyprFlags : "off"; }
    }

    // --- Open windows ---------------------------------------------------
    Process {
        id: classScanner
        command: ["bash", "-c", "hyprctl clients -j | jq -r '.[].class' | tr 'A-Z' 'a-z' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = this.text.split("\n").filter(l => l !== "");
                if (JSON.stringify(list) !== JSON.stringify(root.openClasses)) root.openClasses = list;
            }
        }
    }
    Timer {
        id: scanDebounce
        interval: 400
        onTriggered: { classScanner.running = false; classScanner.running = true; }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow") scanDebounce.restart();
        }
    }
    Component.onCompleted: scanDebounce.restart()

    // --- Applying ---------------------------------------------------------
    property string _appliedFlags: "-"
    property bool _wasCommands: false
    property bool _wasPerf: false

    onHyprFlagsChanged: applyDebounce.restart()
    onEffectiveChanged: applyDebounce.restart()

    Timer {
        id: applyDebounce
        interval: 300
        onTriggered: root.apply()
    }

    readonly property string flagsFile: Caching.stateDir + "/game_flags"

    // What the last session applied, so a shell reload does not reload
    // Hyprland when nothing changed.
    property bool _ready: false
    FileView {
        path: root.flagsFile
        onLoaded: { root._appliedFlags = text().trim(); root._ready = true; applyDebounce.restart(); }
        onLoadFailed: { root._ready = true; applyDebounce.restart(); }
    }

    function apply() {
        if (!root._ready) return;
        if (root.hyprFlags !== root._appliedFlags) {
            let wasOpaque = root._appliedFlags.split(",").indexOf("opaque") !== -1;
            let isOpaque = root.effective.opaque === true;
            root._appliedFlags = root.hyprFlags;
            let scripts = Caching.serpantinumDir + "/scripts";
            // The rules script reads the flags file when the overlay card
            // rewrites the rules later on (slider, blur switch).
            let cmd = "printf '%s' \"$1\" > \"$2\" && \"$3/window-transparency-rules.sh\" && hyprctl reload config-only";
            if (isOpaque && !wasOpaque) cmd += " && \"$3/window-transparency.sh\" reset-all";
            if (!isOpaque && wasOpaque) {
                // Kitty and Vesktop draw their own transparency: put the saved values back.
                cmd += " && jq -r '.windowTransparency // {} | to_entries[] | select(.key == \"kitty\" or .key == \"vesktop\") | \"\\(.key) \\(.value)\"' \"$4\""
                    + " | while read -r app pct; do \"$3/window-transparency.sh\" \"$app\" \"$pct\"; done";
            }
            hyprApplier.command = ["bash", "-c", cmd, "_", root.hyprFlags, root.flagsFile, scripts, Config.settingsJsonPath];
            hyprApplier.running = false;
            hyprApplier.running = true;
        }

        // Custom commands: one when the option turns on, one when it turns off.
        let cmds = root.effective.commands === true;
        if (cmds !== root._wasCommands) {
            let c = cmds ? root.enterCommand : root.exitCommand;
            if (c !== "") Quickshell.execDetached(["bash", "-c", c]);
        }
        root._wasCommands = cmds;

        let perf = root.effective.perfProfile === true;
        if (perf !== root._wasPerf) {
            let state = Caching.stateDir + "/game_prev_profile";
            if (perf) {
                Quickshell.execDetached(["bash", "-c", "powerprofilesctl get > \"$1\" && powerprofilesctl set performance", "_", state]);
            } else {
                Quickshell.execDetached(["bash", "-c", "powerprofilesctl set \"$(cat \"$1\" 2>/dev/null || echo balanced)\"", "_", state]);
            }
        }
        root._wasPerf = perf;
    }

    Process {
        id: hyprApplier
        running: false
    }
}

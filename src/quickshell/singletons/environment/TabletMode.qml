pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Tracks the convertible's hinge/tablet-mode switch (SW_TABLET_MODE),
// read directly from its input device since systemd-logind doesn't
// expose it on this system. See watchers/tabletmode.sh for the detection
// logic and why it needs the user in the `input` group.
//
// On this Yoga model the switch isn't a pure hinge-angle mechanism --
// yoga-usage-mode derives it from the gravity sensor (LENOVO_GSENSOR_DATA),
// so shaking the laptop or moving it quickly can flip it briefly even
// while it's physically still in laptop position. pendingValue is only
// committed to isTabletMode once it's held for debounceMs, so those blips
// never reach the rest of the shell (bar visibility, virtual keyboard,
// screen rotation).
Item {
    id: root

    // Settings > General > Hardware: convertible support is off by default,
    // so non-convertible machines never run the switch watcher.
    readonly property bool enabled: (Config.getSetting("hardware", {}) || {}).tabletMode === true
    // Phones and tablets have no hinge: stay in tablet mode (on-screen
    // keyboard, touch buttons) without watching a switch.
    readonly property bool always: enabled && (Config.getSetting("hardware", {}) || {}).alwaysTablet === true
    onEnabledChanged: if (!enabled) { root.pendingValue = false; root.hingeTablet = false; }

    property bool hingeTablet: false
    readonly property bool isTabletMode: always || hingeTablet
    property bool pendingValue: false
    property int debounceMs: 400

    Process {
        id: watcher
        running: root.enabled && !root.always
        command: ["bash", Caching.qsDir + "/watchers/tabletmode.sh", "watch"]
        stdout: SplitParser {
            onRead: data => {
                let line = data.trim();
                if (!line) return;
                let parts = line.split(/\s+/);
                if (parts.length >= 2 && parts[0] === "tabletmode") {
                    root.pendingValue = parts[1] === "1";
                    debounceTimer.restart();
                }
            }
        }
    }

    Timer {
        id: debounceTimer
        interval: root.debounceMs
        onTriggered: root.hingeTablet = root.pendingValue
    }
}

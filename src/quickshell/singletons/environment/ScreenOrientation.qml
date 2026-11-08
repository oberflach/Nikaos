pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Auto-rotates the built-in panel in tablet mode, following the Yoga's
// accelerometer via iio-sensor-proxy's `monitor-sensor` CLI (no need for a
// custom D-Bus client -- it already prints orientation changes as plain
// lines). Mapping from accelerometer orientation to Hyprland transform
// follows the convention used by most sway/hyprland auto-rotate scripts;
// if it comes out mirrored on this hardware, swap left-up/right-up below.
Item {
    id: root

    property string orientation: "normal"
    readonly property var transformMap: ({
        "normal": 0,
        "right-up": 3,
        "bottom-up": 2,
        "left-up": 1
    })

    function apply() {
        if (!TabletMode.enabled) return;
        let t = TabletMode.isTabletMode ? (root.transformMap[root.orientation] ?? 0) : 0;
        Quickshell.execDetached(["bash", Caching.qsDir + "/watchers/apply_orientation.sh", String(t)]);
    }

    onOrientationChanged: apply()

    // Without this, a screen left rotated by a previous crash/session
    // would stay rotated in PC mode until the next orientation or
    // tablet-mode change happened to fire.
    Component.onCompleted: apply()

    Connections {
        target: TabletMode
        function onIsTabletModeChanged() { root.apply(); }
    }

    Process {
        running: TabletMode.enabled
        command: ["monitor-sensor", "--accel"]
        stdout: SplitParser {
            onRead: data => {
                let m = data.match(/orientation(?:\s*changed)?:\s*([a-z-]+)/i);
                if (m) root.orientation = m[1];
            }
        }
    }
}

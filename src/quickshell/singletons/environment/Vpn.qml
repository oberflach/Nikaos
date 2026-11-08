pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Tracks one NetworkManager connection (Settings > General > Hardware >
// VPN connection, e.g. a WireGuard "wg0") via `nmcli monitor` instead of
// polling. Empty name: no VPN button in the Super+G overlay and no monitor.
// LC_ALL=C forces English state names so "disconnected" can't be mistaken
// for "connected" via substring matching in another locale.
Item {
    id: root

    readonly property string connectionName: String((Config.getSetting("hardware", {}) || {}).vpnConnection || "").trim()
    readonly property bool configured: connectionName !== ""

    property bool connected: false
    property bool pending: false

    onConnectionNameChanged: {
        root.connected = false;
        root.pending = false;
        if (root.configured) stateProbe.running = true;
    }

    function toggle() {
        if (!root.configured || root.pending) return;
        root.pending = true;
        Quickshell.execDetached(["nmcli", "connection", root.connected ? "down" : "up", root.connectionName]);
    }

    // Current state once; nmcli monitor only reports changes.
    Process {
        id: stateProbe
        running: root.configured
        command: ["bash", "-c", "LC_ALL=C nmcli -t -f NAME connection show --active"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.connected = this.text.split("\n").map(l => l.trim()).indexOf(root.connectionName) !== -1;
            }
        }
    }

    Process {
        running: root.configured
        command: ["bash", "-c", "LC_ALL=C exec nmcli monitor"]
        stdout: SplitParser {
            onRead: data => {
                let prefix = root.connectionName + ":";
                if (!data.startsWith(prefix)) return;
                let state = data.substring(prefix.length).trim();
                if (state === "connected") {
                    root.connected = true;
                    root.pending = false;
                } else if (state === "disconnected" || state === "unavailable" || state === "device removed") {
                    root.connected = false;
                    root.pending = false;
                }
            }
        }
    }
}

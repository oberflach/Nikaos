pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// On-screen keyboard (wvkbd), tablet mode only. --auto shows/hides it
// based on text-input focus (needs a compositor with zwp_input_method_v2,
// which Hyprland has); the toggle() below is a manual fallback for apps
// that don't report focus through that protocol. The process itself is
// only alive while TabletMode.isTabletMode is true, so it never shows up
// on its own in laptop mode. No --non-exclusive: it reserves screen
// space like the bar does, so windows resize up instead of hiding behind
// it when it's shown.
Item {
    id: root

    // Kept separate from a direct binding to TabletMode.isTabletMode so
    // the crash-recovery and theme-change handling below can toggle the
    // process without permanently detaching it from tablet-mode tracking.
    property bool shouldRun: TabletMode.isTabletMode

    function toggle() {
        Quickshell.execDetached(["pkill", "-SIGRTMIN", "-f", "wvkbd-mobintl"]);
    }

    function hex(c) {
        return String(c).replace("#", "");
    }

    // wvkbd reads its colors once at launch -- it has no way to recolor a
    // running instance. This tracks the theme colors actually in use so a
    // live theme change (or a running restart_timer restart from a crash)
    // always relaunches with whatever ThemeBackend currently has, instead
    // of whatever it had when this shell instance first started.
    property string bgHex: hex(ThemeBackend.crust)
    property string fgHex: hex(ThemeBackend.surface1)
    property string fgSpHex: hex(ThemeBackend.surface0)
    property string pressHex: hex(ThemeBackend.blue)
    property string pressSpHex: hex(ThemeBackend.mauve)
    property string textHex: hex(ThemeBackend.text)

    property string themeSignature: [bgHex, fgHex, fgSpHex, pressHex, pressSpHex, textHex].join(",")

    Connections {
        target: TabletMode
        function onIsTabletModeChanged() {
            root.shouldRun = TabletMode.isTabletMode;
        }
    }

    onThemeSignatureChanged: {
        if (vkbdProcess.running) {
            root.shouldRun = false;
            restartTimer.start();
        }
    }

    // wvkbd 0.20 has a crash in its --auto input-method handling that a
    // fast focus change (e.g. pressing Tab) can trigger. Rather than
    // leaving the keyboard dead until the shell restarts, respawn it
    // automatically while still in tablet mode.
    Process {
        id: vkbdProcess
        running: root.shouldRun
        command: [
            "wvkbd-mobintl", "--auto", "--hidden",
            "-L", "230", "-H", "300", "-R", "22",
            "--fn", "Adwaita Mono 13",
            "--bg", root.bgHex, "--fg", root.fgHex, "--fg-sp", root.fgSpHex,
            "--press", root.pressHex, "--press-sp", root.pressSpHex,
            "--text", root.textHex, "--text-sp", root.textHex,
            "--text-press", root.bgHex, "--text-press-sp", root.bgHex
        ]
        onExited: {
            if (TabletMode.isTabletMode) {
                root.shouldRun = false;
                restartTimer.start();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 300
        onTriggered: root.shouldRun = TabletMode.isTabletMode
    }
}

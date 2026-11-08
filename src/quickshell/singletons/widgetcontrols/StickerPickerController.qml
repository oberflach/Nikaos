pragma Singleton
import QtQuick
import Quickshell
import "../../"

// Cross-file open/close state for the sticker (image/GIF) browser window
// used by the overlay's floating-image card, following the same pattern
// as the other widgetcontrols singletons (OsdController, etc.).
Item {
    id: controller

    property bool isOpen: false
    property string startDir: Quickshell.env("HOME") + "/Images/Stickers"

    function open(dir) {
        if (dir) controller.startDir = dir;
        controller.isOpen = true;
    }

    function close() {
        controller.isOpen = false;
    }
}

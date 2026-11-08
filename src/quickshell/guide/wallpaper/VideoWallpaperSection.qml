import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Video wallpapers play from copies sized to the screen and capped in frame
// rate (scripts/wallpaper/transcode.py), which costs far less GPU than
// decoding 4K files. Settings: wallpaperTranscode { enabled, fps }.
SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    readonly property var transcode: Config.getSetting("wallpaperTranscode", { "enabled": true, "fps": 30 }) || {}

    function setTranscode(key, value) {
        let next = Object.assign({ "enabled": true, "fps": 30 }, Config.getSetting("wallpaperTranscode", {}) || {});
        next[key] = value;
        Config.setSetting("wallpaperTranscode", next);
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "wallpaper_transcode"
        icon: "󰕧"
        title: I18n.t("guide.wallpaper.transcode.title", "Light video wallpapers")
        description: I18n.t("guide.wallpaper.transcode.desc", "Play videos from copies sized to the screen, built in the background (saves GPU)")
        searchKeywords: "video wallpaper transcode light gpu performance copy"

        Toggle {
            id: transcodeToggle
            checked: section.transcode.enabled !== false
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                section.setTranscode("enabled", c);
                transcodeToggle.checked = Qt.binding(() => section.transcode.enabled !== false);
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        visible: section.transcode.enabled !== false
        settingId: "wallpaper_transcode_fps"
        icon: "󰔟"
        title: I18n.t("guide.wallpaper.transcode_fps.title", "Video wallpaper frame rate")
        description: I18n.t("guide.wallpaper.transcode_fps.desc", "Highest frame rate of the light copies")
        searchKeywords: "video wallpaper fps frame rate"

        NumberSelector {
            implicitWidth: section.rootObj.s(160)
            implicitHeight: section.rootObj.s(32)
            from: 15
            to: 60
            stepSize: 5
            decimals: 0
            suffix: " fps"
            value: Number(section.transcode.fps) || 30
            baseColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            buttonColor: ThemeBackend.surface1
            buttonTextColor: ThemeBackend.text
            textColor: ThemeBackend.text
            subTextColor: ThemeBackend.subtext0
            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
            cornerRadius: ThemeBackend.borderRadius
            fontPixelSize: section.rootObj.s(11)
            onValueChanged: {
                let v = Math.round(value);
                if (v >= 15 && v !== (Number(section.transcode.fps) || 30)) section.setTranscode("fps", v);
            }
        }
    }
}

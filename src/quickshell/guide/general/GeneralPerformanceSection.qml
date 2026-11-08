import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Lighter shell for weak GPUs (on by default on Nikaos Linux, the Android app).
// Settings key: performance { reducedMotion, staticWallpapers }. Blur lives in
// Settings > Theme.
SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    readonly property var perf: Config.getSetting("performance", {}) || {}

    function setPerf(key, value) {
        let next = Object.assign({}, Config.getSetting("performance", {}) || {});
        next[key] = value;
        Config.setSetting("performance", next);
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "performance_motion"
        icon: "󰕍"
        title: I18n.t("guide.general.performance.motion.title", "Reduced motion")
        description: I18n.t("guide.general.performance.motion.desc", "Short fades between wallpapers and colours applied at once")
        searchKeywords: "animation motion reduce performance light fast"

        Toggle {
            id: motionToggle
            checked: section.perf.reducedMotion === true
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                section.setPerf("reducedMotion", c);
                motionToggle.checked = Qt.binding(() => section.perf.reducedMotion === true);
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "performance_static"
        icon: "󰋩"
        title: I18n.t("guide.general.performance.static.title", "Static wallpapers")
        description: I18n.t("guide.general.performance.static.desc", "Video wallpapers show their preview image and GIFs stay still")
        searchKeywords: "video gif wallpaper static still performance light"

        Toggle {
            id: staticToggle
            checked: section.perf.staticWallpapers === true
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                section.setPerf("staticWallpapers", c);
                staticToggle.checked = Qt.binding(() => section.perf.staticWallpapers === true);
            }
        }
    }
}

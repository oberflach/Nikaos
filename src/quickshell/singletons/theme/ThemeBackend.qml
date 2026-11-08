pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property string fontFamily: "Adwaita Mono"
    property int borderRadius: 8
    property int clampedBorderRadius: {
        const r = borderRadius;
        return Math.floor(
            r <= 24
                ? r
                : 24 + Math.pow(r - 24, 0.55)
        );
    }

    property real elementOpacity: 1.0
    property bool blurBackground: false
    property string blurStyle: "blur"
    readonly property real liquidGlassOpacity: 0.1
    readonly property bool glassActive: blurBackground && elementOpacity < 0.999
    readonly property bool liquidGlass: blurBackground && blurStyle === "liquid"

    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color _text: "#cdd6f4"
    property color _subtext0: "#a6adc8"
    property color _subtext1: "#bac2de"
    readonly property color text: liquidGlass ? "#ffffff" : _text
    readonly property color subtext0: liquidGlass ? "#ffffff" : _subtext0
    readonly property color subtext1: liquidGlass ? "#ffffff" : _subtext1
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"
    property color blue: "#89b4fa"
    readonly property color primary: blue
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color green: "#a6e3a1"
    property color red: "#f38ba8"
    property color mauve: "#cba6f7"
    property color pink: "#f5c2e7"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"
    property color teal: "#94e2d5"

    property string configPath: Quickshell.env("QS_COLORS_JSON") ?? "~/.local/state/serpantinum/qs_colors.json"
    property string matugenConfigPath: (typeof Caching !== "undefined" && Caching.stateDir ? Caching.stateDir : ((Quickshell.env("HOME") ?? "") + "/.local/state/serpantinum")) + "/qs_matugen_colors.json"

    property bool _readInProgress: false
    property var matugenColors: null
    property var _colorQueue: []
    property int colorsPerFrame: 3

    property var availableFontPaths: ({})
    property var bundledNames: []
    property string activeFontPath: ""

    FontLoader {
        id: iconFontLoader
        source: (typeof Caching !== "undefined" && Caching.serpantinumDir && Caching.serpantinumDir !== "")
            ? ("file://" + Caching.serpantinumDir + "/assets/fonts/SymbolsNerdFontMono-Regular.ttf")
            : ""
    }

    readonly property string iconFont: (iconFontLoader.status === FontLoader.Ready && iconFontLoader.name !== "")
        ? iconFontLoader.name
        : (root.fontFamily !== "" ? root.fontFamily : "sans-serif")
    readonly property bool iconFontReady: iconFontLoader.status === FontLoader.Ready

    onFontFamilyChanged: {
        root.updateActiveFontLoader();
    }

    // A sibling of `base`: hue nudged by hueShift (0..1 turns, e.g. 0.04 ~ 14
    // degrees) and lightness by lightShift. Used to give bar modules distinct
    // shades of the same wallpaper colour.
    function shade(base, hueShift, lightShift) {
        let c = Qt.color(base);
        let h = c.hslHue < 0 ? 0 : c.hslHue;
        h = ((h + (hueShift || 0)) % 1 + 1) % 1;
        let l = Math.max(0, Math.min(1, c.hslLightness + (lightShift || 0)));
        return Qt.hsla(h, c.hslSaturation, l, c.a);
    }

    // Per-icon shades for the bar modules. Defaults below; the Theme tab
    // stores overrides under settings.iconShades as {id: {h, l}} and keeps
    // the value being dragged in iconShadeLive until the slider is released.
    // To shade a new module: add an id here and in iconShadeIds, then use
    // ThemeBackend.iconShade("<id>") for its colour.
    readonly property var iconShadeIds: ["cpu", "ram", "temp", "disk", "gpu", "wifi", "bt", "vol", "bat"]
    readonly property var iconShadeDefaults: ({
        "cpu":  { "h": -0.06, "l": 0 },
        "ram":  { "h": -0.03, "l": -0.08 },
        "temp": { "h": 0.03,  "l": 0 },
        "disk": { "h": 0.06,  "l": -0.08 },
        "gpu":  { "h": 0.10,  "l": -0.04 },
        "wifi": { "h": 0,     "l": 0 },
        "bt":   { "h": -0.04, "l": -0.14 },
        "vol":  { "h": 0.04,  "l": -0.07 },
        "bat":  { "h": 0.08,  "l": 0 }
    })
    readonly property var iconShadeOverrides: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.iconShades) ? Config.rawSettings.iconShades : ({})
    property var iconShadeLive: ({})

    function iconShadeParams(id) {
        let d = root.iconShadeDefaults[id] || { "h": 0, "l": 0 };
        let o = root.iconShadeLive[id] || root.iconShadeOverrides[id] || {};
        return { "h": o.h !== undefined ? o.h : d.h, "l": o.l !== undefined ? o.l : d.l };
    }

    function iconShade(id) {
        let p = root.iconShadeParams(id);
        return root.shade(root.mauve, p.h, p.l);
    }

    function previewIconShade(id, h, l) {
        let next = Object.assign({}, root.iconShadeLive);
        next[id] = { "h": h, "l": l };
        root.iconShadeLive = next;
    }

    function commitIconShade(id) {
        let p = root.iconShadeParams(id);
        let next = Object.assign({}, root.iconShadeOverrides);
        next[id] = { "h": Math.round(p.h * 1000) / 1000, "l": Math.round(p.l * 1000) / 1000 };
        Config.setSetting("iconShades", next);
        let live = Object.assign({}, root.iconShadeLive);
        delete live[id];
        root.iconShadeLive = live;
    }

    function resetIconShades() {
        root.iconShadeLive = ({});
        Config.setSetting("iconShades", {});
    }

    function isMatugenTheme() {
        if (typeof Matugen !== "undefined" && typeof Matugen.isMatugenTheme === "function") {
            return Matugen.isMatugenTheme();
        }
        let themeConfig = Config.getSetting("theme", { "matugen": true, "activePreset": "Matugen" });
        if (themeConfig.matugen !== undefined) {
            return themeConfig.matugen === true;
        }
        return themeConfig.theme === "matugen"
            || themeConfig.name === "matugen"
            || themeConfig.currentTheme === "matugen"
            || themeConfig.current === "matugen"
            || themeConfig.activePreset === "Matugen"
            || themeConfig.activePreset === undefined;
    }

    function updateActiveFontLoader() {
        if (!root.fontFamily || root.fontFamily === "") return;
        let key = root.fontFamily.toLowerCase();
        let path = root.availableFontPaths ? root.availableFontPaths[key] : "";

        if (path && root.activeFontPath !== path) {
            root.activeFontPath = path;
        }
    }

    FontLoader {
        id: staticFontLoader
        source: (root.activeFontPath && root.activeFontPath !== "") ? ("file://" + root.activeFontPath) : ""
        onStatusChanged: {
            if (status === FontLoader.Ready) {
                let cur = root.fontFamily;
                root.fontFamily = "";
                root.fontFamily = cur;
            }
        }
    }

    Process {
        id: fontFetcher
        property bool forceRescan: false

        command: {
            let sys = Caching.serpantinumDir ? (Caching.serpantinumDir + "/assets/fonts") : "";
            let usr = Caching.stateDir ? (Caching.stateDir + "/fonts") : (Caching.home + "/.local/state/serpantinum/fonts");
            let cacheFile = Caching.stateDir ? (Caching.stateDir + "/fonts_cache.txt") : (Caching.home + "/.local/state/serpantinum/fonts_cache.txt");
            let force = forceRescan ? "true" : "false";

            let cmd = "CACHE=\"" + cacheFile + "\"; ";
            cmd += "if [ \"" + force + "\" = \"true\" ] || [ ! -f \"$CACHE\" ]; then ";
            cmd += "mkdir -p \"$(dirname \"$CACHE\")\"; ";
            cmd += "find ";
            if (sys !== "") cmd += "\"" + sys + "\" ";
            cmd += "\"" + usr + "\" -type f \\( -iname \"*.ttf\" -o -iname \"*.otf\" -o -iname \"*.ttc\" \\) -print0 2>/dev/null | sort -z | ";
            cmd += "xargs -0 -r fc-scan -f '%{family[0]}\\t%{style[0]}\\t%{file}\\n' 2>/dev/null | ";
            cmd += "awk -F'\\t' '{ fam=$1; stl=$2; f=$3; if (fam==\"\") { n=split(f,a,\"/\"); fam=a[n]; sub(/\\.[^.]*$/,\"\",fam) } if (stl!=\"\" && stl!=\"Regular\") print fam \" \" stl \"|\" f; else print fam \"|\" f }' ";
            cmd += "> \"$CACHE.tmp\" || true; mv \"$CACHE.tmp\" \"$CACHE\"; ";
            cmd += "fi; ";
            cmd += "cat \"$CACHE\" || true";

            return ["bash", "-c", cmd];
        }
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                fontFetcher.forceRescan = false;

                let lines = this.text.trim().split('\n');
                let newPaths = {};
                let names = [];
                let seen = new Set();

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line === "") continue;

                    let idx = line.indexOf('|');
                    if (idx !== -1) {
                        let fName = line.substring(0, idx).trim();
                        if (fName.toLowerCase().indexOf("symbols nerd font") !== -1) continue;

                        let fPath = line.substring(idx + 1).trim();
                        let key = fName.toLowerCase();

                        newPaths[key] = fPath;

                        if (!seen.has(key)) {
                            seen.add(key);
                            names.push(fName);
                        }
                    }
                }

                root.availableFontPaths = newPaths;
                root.bundledNames = names;
                root.updateActiveFontLoader();
                if (staticFontLoader.status === FontLoader.Ready) {
                    let cur = root.fontFamily;
                    root.fontFamily = "";
                    root.fontFamily = cur;
                }
            }
        }
    }

    function scanFonts() {
        fontFetcher.running = false;
        fontFetcher.forceRescan = true;
        fontFetcher.running = true;
    }

    function reloadColors() {
        if (root._readInProgress) return;
        root._readInProgress = true;
        root.updateColors();
    }

    IpcHandler {
        target: "theme"

        function reloadColors() {
            root.reloadColors();
        }

        // Local: the colour currently applied, e.g. "blue" -> "#8fcef3".
        function getColor(name: string): string {
            let v = root[name];
            return v === undefined ? "" : v.toString();
        }
    }

    IpcHandler {
        target: "fonts"
        function rescan() {
            root.scanFonts();
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.updateColors();
        }
        function onRawSettingsChanged() {
            root.syncElementOpacity();
        }
    }

    Connections {
        target: typeof Matugen !== "undefined" ? Matugen : null
        function onGenerationFinished(success) {
            root._readInProgress = false;
            if (success) {
                themeWatcher.reload();
                // Local: no matugenColorsWatcher.reload() here. Matugen copies
                // qs_colors.json to qs_matugen_colors.json in a detached process,
                // so reading it now could return the previous wallpaper's palette
                // and replace the new one held for the transition. The watcher
                // reloads by itself once the copy lands.
            }
        }
    }

    function applyMatugenColors(): bool {
        if (root.matugenColors) {
            root.applyColorObject(root.matugenColors);
            return true;
        }
        return false;
    }

    function faded(c) {
        return Qt.alpha(c, root.elementOpacity);
    }

    function syncElementOpacity() {
        const themeConfig = Config.getSetting("theme", {});
        const pct = themeConfig.elementOpacity !== undefined ? Number(themeConfig.elementOpacity) : 100;
        root.blurBackground = themeConfig.blurBackground !== undefined ? Boolean(themeConfig.blurBackground) : false;
        root.blurStyle = themeConfig.blurStyle === "liquid" ? "liquid" : "blur";
        root.elementOpacity = root.liquidGlass ? root.liquidGlassOpacity : (isNaN(pct) ? 1.0 : Math.max(0, Math.min(1.0, pct / 100.0)));
    }

    function updateColors() {
        let themeConfig = Config.getSetting("theme", {});

        if (themeConfig.fontFamily !== undefined) {
            root.fontFamily = themeConfig.fontFamily;
        }
        if (themeConfig.borderRadius !== undefined) {
            root.borderRadius = themeConfig.borderRadius;
        }
        root.syncElementOpacity();

        let customColors = themeConfig.colors || themeConfig.palette || (themeConfig.base !== undefined ? themeConfig : null);

        if (root.isMatugenTheme()) {
            root.applyMatugenColors();
            let wp = themeConfig.wallpaper || Config.getSetting("wallpaper", "");
            if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                Matugen.generate(wp, themeConfig.mode, themeConfig.schemeType);
            }
            root._readInProgress = false;
        } else {
            root._readInProgress = false;
            if (customColors) {
                root.applyColorObject(customColors);
                if (typeof Matugen !== "undefined" && typeof Matugen.generateFromStatic === "function") {
                    Matugen.generateFromStatic(customColors, themeConfig.mode);
                }
            } else {
                themeWatcher.reload();
            }
        }
    }

    // --- Colour morph synced with wallpaper transitions ---
    // While a new wallpaper loads, the next palette is held back; when its
    // transition starts the colours blend from old to new over the same
    // duration. A palette arriving during a transition blends over what is
    // left of it. Updates are stepped (~20/s) to keep the bindings cheap.
    property var _stashedColors: null
    readonly property bool hasStashedColors: _stashedColors !== null
    property double _transitionStartMs: 0
    property int _transitionDuration: 0
    property var _morphFrom: ({})
    property var _morphTo: ({})
    property real morphProgress: 0
    property int _morphStep: -1
    property int _morphSteps: 1
    // Keyed by the writable slot: text and subtexts live in _text/_subtext*
    // (the public ones are read-only and follow liquid glass).
    readonly property var _morphNeutrals: ["base", "mantle", "crust", "surface0", "surface1", "surface2",
                                           "overlay0", "overlay1", "overlay2", "_text", "_subtext0", "_subtext1"]

    Connections {
        target: typeof Wallpaper !== "undefined" ? Wallpaper : null
        function onTransitionStarted(duration) {
            root._transitionStartMs = Date.now();
            root._transitionDuration = duration;
            if (root._stashedColors) {
                let c = root._stashedColors;
                root._stashedColors = null;
                stashTimeout.stop();
                root._startMorph(c, duration);
            }
        }
    }

    // Never keep a palette back for long if no transition follows.
    Timer {
        id: stashTimeout
        interval: 3000
        onTriggered: {
            if (root._stashedColors) {
                let c = root._stashedColors;
                root._stashedColors = null;
                root._applyColorsNow(c);
            }
        }
    }

    NumberAnimation {
        id: morphAnim
        target: root
        property: "morphProgress"
        from: 0
        to: 1
        easing.type: Easing.InOutQuad
    }

    onMorphProgressChanged: {
        let step = Math.round(root.morphProgress * root._morphSteps);
        if (step === root._morphStep) return;
        root._morphStep = step;
        let t = step / root._morphSteps;
        for (let name in root._morphTo) {
            let a = root._morphFrom[name], b = root._morphTo[name];
            if (root._morphNeutrals.indexOf(name) !== -1) {
                // Greys and text are barely noticed mid-way: switch them once,
                // halfway, instead of re-evaluating every binding on each step.
                if (t >= 0.5 && root[name].toString() !== b.toString()) root[name] = b;
                continue;
            }
            root[name] = Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
        }
    }

    function _resolveColors(c) {
        let resolveHex = function(val) {
            if (!val) return "";
            if (typeof val === "string") return val;
            if (typeof val === "object") {
                if (val.hex) return val.hex;
                if (val.color) return val.color;
                if (val.default && val.default.hex) return val.default.hex;
            }
            return val.toString();
        };
        let names = ["base", "mantle", "crust", "surface0", "surface1", "surface2",
                     "overlay0", "overlay1", "overlay2", "text", "subtext0", "subtext1",
                     "blue", "sapphire", "peach", "green", "red", "mauve", "pink",
                     "yellow", "maroon", "teal"];
        let out = {};
        for (let i = 0; i < names.length; i++) {
            let hexColor = resolveHex(c[names[i]]);
            if (!hexColor) continue;
            let slot = (names[i] === "text" || names[i] === "subtext0" || names[i] === "subtext1") ? "_" + names[i] : names[i];
            out[slot] = Qt.color(hexColor);
        }
        return out;
    }

    function _startMorph(c, duration) {
        morphAnim.stop();
        root._colorQueue = [];
        colorStepTimer.stop();
        let target = root._resolveColors(c);
        let from = {}, to = {};
        for (let name in target) {
            if (root[name].toString() !== target[name].toString()) {
                from[name] = Qt.color(root[name]);
                to[name] = target[name];
            }
        }
        root._morphFrom = from;
        root._morphTo = to;
        if (Object.keys(to).length === 0) return;
        let d = Math.max(150, duration);
        root._morphSteps = Math.max(1, Math.round(d / 100));
        root._morphStep = -1;
        morphAnim.duration = d;
        root.morphProgress = 0;
        morphAnim.restart();
    }

    function applyColorObject(c) {
        if (!c) return;
        if (typeof Wallpaper !== "undefined" && Wallpaper.reducedMotion) {
            root._applyColorsNow(c);
            if (Wallpaper.transitionPending) Wallpaper.colorsReady();
            return;
        }
        if (typeof Wallpaper !== "undefined" && Wallpaper.transitionPending) {
            root._stashedColors = c;
            stashTimeout.restart();
            Wallpaper.colorsReady();
            return;
        }
        let remaining = root._transitionDuration - (Date.now() - root._transitionStartMs);
        if (remaining > 150) {
            root._startMorph(c, remaining);
            return;
        }
        root._applyColorsNow(c);
    }

    function _applyColorsNow(c) {
        if (!c) return;
        morphAnim.stop();

        let resolveHex = function(val) {
            if (!val) return "";
            if (typeof val === "string") return val;
            if (typeof val === "object") {
                if (val.hex) return val.hex;
                if (val.color) return val.color;
                if (val.default && val.default.hex) return val.default.hex;
            }
            return val.toString();
        };

        let names = ["base", "mantle", "crust", "surface0", "surface1", "surface2",
                     "overlay0", "overlay1", "overlay2", "text", "subtext0", "subtext1",
                     "blue", "sapphire", "peach", "green", "red", "mauve", "pink",
                     "yellow", "maroon", "teal"];

        let queue = [];
        for (let i = 0; i < names.length; i++) {
            let hexColor = resolveHex(c[names[i]]);
            if (!hexColor) continue;
            let nextColor = Qt.color(hexColor);
            let slot = (names[i] === "text" || names[i] === "subtext0" || names[i] === "subtext1") ? "_" + names[i] : names[i];
            if (root[slot].toString() !== nextColor.toString()) {
                queue.push({ name: slot, value: nextColor });
            }
        }

        root._colorQueue = queue;
        if (queue.length > 0) {
            root._flushColorQueue();
            if (root._colorQueue.length > 0) colorStepTimer.restart();
        }
    }

    function _flushColorQueue() {
        let n = Math.min(root.colorsPerFrame, root._colorQueue.length);
        for (let i = 0; i < n; i++) {
            let item = root._colorQueue[i];
            root[item.name] = item.value;
        }
        root._colorQueue = root._colorQueue.slice(n);
    }

    FrameAnimation {
        id: colorStepTimer
        onTriggered: {
            root._flushColorQueue();
            if (root._colorQueue.length === 0) stop();
        }
    }

    FileView {
        id: matugenColorsWatcher
        path: root.matugenConfigPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        root.matugenColors = target;
                        if (root.isMatugenTheme()) {
                            root.applyColorObject(target);
                        }
                    }
                } catch(e) {}
            }
        }
    }

    FileView {
        id: themeWatcher
        path: root.configPath.startsWith("~") ? (Quickshell.env("HOME") ?? "") + root.configPath.slice(1) : root.configPath
        watchChanges: false

        onLoaded: {
            root._readInProgress = false;
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        if (root.isMatugenTheme()) {
                            root.matugenColors = target;
                        }
                        root.applyColorObject(target);
                    }
                } catch(e) {}
            }
        }
    }

    Component.onCompleted: {
        root._readInProgress = true;
        root.updateColors();
        root.updateActiveFontLoader();
    }
}

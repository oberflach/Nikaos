import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtMultimedia
import "../"

ShellRoot {
    id: globalRoot

    Variants {
        id: root
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                screen: modelData

                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background

                focusable: false
                exclusionMode: ExclusionMode.Ignore
                color: "#0a0a0f"

                anchors { top: true; bottom: true; left: true; right: true }

                readonly property string wpCacheDir: Caching.getCacheDir("wallpaper")
                readonly property string wpStatePath: wpCacheDir + "/current_" + barWindow.screen.name
                readonly property string wpCopyDir: wpCacheDir + "/copy_" + barWindow.screen.name
                readonly property string wpSnapshotPath: wpCacheDir + "/current_wallpaper.png"
                readonly property string wpMonitorSnapshotPath: wpCacheDir + "/current_wallpaper_" + barWindow.screen.name + ".png"

                property string currentWallpaperPath: ""
                property string originalFileName: ""
                property int activeLayer: 0
                property string pathA: ""
                property bool isVideoA: false
                property string pathB: ""
                property bool isVideoB: false
                property bool playbackPaused: false
                property bool snapReadyA: false
                property bool snapReadyB: false
                property int snapRevA: 0
                property int snapRevB: 0
                readonly property string layerSnapshotPathA: wpCacheDir + "/layer_" + barWindow.screen.name + "_a.png"
                readonly property string layerSnapshotPathB: wpCacheDir + "/layer_" + barWindow.screen.name + "_b.png"

                property int activeDuration: 1000
                property var pendingChange: null
                property bool capturingFrame: false
                property bool frozenActive: false
                readonly property bool transitionBusy: transitionAnim.running || videoWarmUpTimer.running || capturingFrame
                property real transitionProgress: 1.0
                property bool isPreloading: false
                property int activeTransitionType: 0
                property bool wipeIsVertical: false
                property int swipeDirection: 0
                property real transitionOriginX: 0.5
                property real transitionOriginY: 0.5
                property real transitionSeed: 0.0
                property bool isInitialLoad: true

                // Sticky: once a video layer has been built we keep the Loader alive
                // and only blank the player's source, because destroying the player
                // is what strands its decode buffers.
                property bool everVideoA: false
                property bool everVideoB: false
                onIsVideoAChanged: if (isVideoA) everVideoA = true
                onIsVideoBChanged: if (isVideoB) everVideoB = true

                Component.onCompleted: {
                    restorePoller.running = true;
                    Wallpaper.registerEngine(barWindow.screen ? barWindow.screen.name : "", barWindow);
                }

                Component.onDestruction: Wallpaper.unregisterEngine(barWindow.screen ? barWindow.screen.name : "", barWindow)

                onCurrentWallpaperPathChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpaperPaths);
                        map[barWindow.screen.name] = currentWallpaperPath;
                        Wallpaper.screenWallpaperPaths = map;
                    }
                }

                onOriginalFileNameChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpapers);
                        map[barWindow.screen.name] = originalFileName;
                        Wallpaper.screenWallpapers = map;
                    }
                }

                Connections {
                    target: Wallpaper

                    function onWallpaperChanged(screenName, path, transition) {
                        if (screenName === "all" || screenName === barWindow.screen.name)
                            barWindow.changeWallpaper(path, transition);
                    }

                    function onPlaybackChanged(screenName, state) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            if (state === "pause") {
                                barWindow.playbackPaused = true;
                                barWindow.stopA();
                                barWindow.stopB();
                            } else if (state === "play") {
                                barWindow.playbackPaused = false;
                                if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                                if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                            }
                        }
                    }

                    function onWallpaperCleared(screenName) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            barWindow.currentWallpaperPath = "";
                            barWindow.pathA = "";
                            barWindow.pathB = "";
                            barWindow.isVideoA = false;
                            barWindow.isVideoB = false;
                            barWindow.originalFileName = "";
                            barWindow.stopA();
                            barWindow.stopB();
                            Quickshell.execDetached(["bash", "-c", "rm -f '" + barWindow.wpStatePath + "' '" + barWindow.wpStatePath + "_name'"]);
                        }
                    }
                }

                Process {
                    id: restorePoller
                    running: false
                    command: [
                        "bash", "-c",
                        "F1='" + barWindow.wpStatePath + "'; F2='" + barWindow.wpStatePath + "_name'; [ -f \"$F1\" ] && cat \"$F1\" || true; echo '---SPLIT---'; [ -f \"$F2\" ] && cat \"$F2\" || true"
                    ]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let parts = this.text.split("---SPLIT---");
                            let savedPath = parts[0] ? parts[0].trim() : "";
                            let savedName = parts[1] ? parts[1].trim() : "";
                            if (savedPath !== "") {
                                barWindow.originalFileName = savedName;
                                barWindow._loadNew(savedPath, false);
                                if (barWindow.isVideo(savedPath)) {
                                    videoSnapshotProcess.targetPath = savedPath;
                                    videoSnapshotProcess.running = false;
                                    videoSnapshotProcess.running = true;
                                }
                                if (savedName !== "") {
                                    let histFile = barWindow.wpCacheDir + "/history.txt";
                                    Quickshell.execDetached(["bash", "-c",
                                        "HIST='" + histFile + "'; if [ -f \"$HIST\" ]; then if [ \"$(head -n 1 \"$HIST\" 2>/dev/null)\" != '" + savedName + "' ]; then grep -v -F -x '" + savedName + "' \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\n' '" + savedName + "' | cat - \"$HIST.tmp\" > \"$HIST\"; rm -f \"$HIST.tmp\"; fi; else printf '%s\n' '" + savedName + "' > \"$HIST\"; fi"
                                    ]);
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: videoWarmUpTimer
                    interval: 250
                    repeat: false
                    onTriggered: barWindow.triggerTransition()
                }

                Process {
                    id: layerSnapshotA
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null",
                        "_",
                        targetPath,
                        barWindow.layerSnapshotPathA
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0) {
                            barWindow.snapReadyA = true;
                            barWindow.snapRevA++;
                        }
                    }
                }

                Process {
                    id: layerSnapshotB
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null",
                        "_",
                        targetPath,
                        barWindow.layerSnapshotPathB
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0) {
                            barWindow.snapReadyB = true;
                            barWindow.snapRevB++;
                        }
                    }
                }

                Process {
                    id: videoSnapshotProcess
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null; cp -f \"$2\" \"$3\" 2>/dev/null || true",
                        "_",
                        targetPath,
                        barWindow.wpSnapshotPath,
                        barWindow.wpMonitorSnapshotPath
                    ]
                    // Set when the picker / slideshow index already has a poster for
                    // this video: the theme comes from that poster, so the frame
                    // grabbed here only feeds the lock screen snapshots.
                    property bool themeFromPoster: false
                    onExited: exitCode => {
                        if (themeFromPoster) return;
                        if (exitCode === 0 && typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(barWindow.wpSnapshotPath);
                        }
                    }
                }

                function snapshotLayer(slot, path) {
                    let proc = slot === 0 ? layerSnapshotA : layerSnapshotB;
                    if (slot === 0) barWindow.snapReadyA = false;
                    else barWindow.snapReadyB = false;
                    proc.targetPath = path;
                    proc.running = false;
                    proc.running = true;
                }

                function isVideo(p) {
                    let lp = p.toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") ||
                           lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                // Only what the MediaPlayer reads is redirected to the cached copy;
                // currentWallpaperPath and the saved state keep the original, so the
                // picker, the history and Matugen never see a cache path.
                function playbackPath(p) {
                    let mapped = globalRoot.transcodedMap[p];
                    return mapped ? mapped : p;
                }

                function isSupportedMedia(p) {
                    if (!p) return false;
                    let lp = p.toLowerCase();
                    return lp.endsWith(".jpg") || lp.endsWith(".jpeg") || lp.endsWith(".png") ||
                           lp.endsWith(".webp") || lp.endsWith(".gif") || lp.endsWith(".bmp") ||
                           lp.endsWith(".avif") || barWindow.isVideo(p);
                }

                function playA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.play === "function") {
                        videoLoaderA.item.play();
                    }
                }

                function stopA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.stop === "function") {
                        videoLoaderA.item.stop();
                    }
                }

                function playB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.play === "function") {
                        videoLoaderB.item.play();
                    }
                }

                function stopB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.stop === "function") {
                        videoLoaderB.item.stop();
                    }
                }

                // The transition waits (up to themeWaitTimer) for a running
                // Matugen pass, so the new palette and the new wallpaper start
                // together; ThemeBackend then morphs the colours over the same
                // duration.
                property bool pendingTrigger: false

                function triggerTransition() {
                    videoWarmUpTimer.stop();
                    let paletteComing = typeof Matugen !== "undefined"
                        && (Matugen.isRunning || Date.now() - Matugen.lastRequestMs < 1500);
                    if (paletteComing && !ThemeBackend.hasStashedColors) {
                        barWindow.pendingTrigger = true;
                        themeWaitTimer.restart();
                        return;
                    }
                    barWindow.startTransition();
                }

                function startTransition() {
                    barWindow.pendingTrigger = false;
                    themeWaitTimer.stop();
                    barWindow.isPreloading = false;
                    Wallpaper.transitionPending = false;
                    Wallpaper.transitionStarted(barWindow.activeDuration);
                    transitionAnim.restart();
                }

                Timer {
                    id: themeWaitTimer
                    interval: 1200
                    repeat: false
                    onTriggered: if (barWindow.pendingTrigger) barWindow.startTransition()
                }

                Connections {
                    target: Wallpaper
                    function onColorsReady() {
                        if (barWindow.pendingTrigger) barWindow.startTransition();
                    }
                }

                // Same palette as before: no colours to wait for once Matugen is done.
                Connections {
                    target: typeof Matugen !== "undefined" ? Matugen : null
                    function onGenerationFinished(success) {
                        if (barWindow.pendingTrigger && !Matugen.isRunning) finishedGrace.restart();
                    }
                }

                Timer {
                    id: finishedGrace
                    interval: 150
                    onTriggered: if (barWindow.pendingTrigger) barWindow.startTransition()
                }

                function clearOutgoingLayer() {
                    if (barWindow.activeLayer === 0) {
                        barWindow.stopB();
                        barWindow.pathB = "";
                        barWindow.isVideoB = false;
                    } else {
                        barWindow.stopA();
                        barWindow.pathA = "";
                        barWindow.isVideoA = false;
                    }
                }

                function completeTransition() {
                    barWindow.clearOutgoingLayer();
                    barWindow.frozenActive = false;
                }

                function applyFrozenFrame() {
                    captureWait.stop();
                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.capturingFrame = false;
                    barWindow.frozenActive = true;
                    let next = barWindow.pendingChange;
                    barWindow.pendingChange = null;
                    if (!next) return;
                    barWindow.changeWallpaper(next.path, next.ttype);
                    barWindow.clearOutgoingLayer();
                }

                function interruptWith(path, ttype) {
                    if (typeof DesktopMenuController !== "undefined" && DesktopMenuController.isMenuShuffle) {
                        let isTargetScreen = !DesktopMenuController.screen || !DesktopMenuController.screen.name || (barWindow.screen && DesktopMenuController.screen.name === barWindow.screen.name);
                        if (isTargetScreen) {
                            ttype = { type: 2, originX: DesktopMenuController.menuOriginX, originY: DesktopMenuController.menuOriginY };
                        }
                    }
                    barWindow.pendingChange = { path: path, ttype: ttype };
                    if (barWindow.capturingFrame) return;
                    barWindow.capturingFrame = true;
                    frozenFrame.scheduleUpdate();
                    captureWait.frames = 0;
                    captureWait.restart();
                }

                function _loadNew(path, force) {
                    if (!path) return;
                    if (!force && path === barWindow.currentWallpaperPath) return;

                    let cleanPath = String(path).trim();
                    let vid = barWindow.isVideo(cleanPath);
                    // Static wallpapers (performance setting): a video shows its
                    // poster instead of playing.
                    let staticPoster = (vid && Wallpaper.staticWallpapers) ? (globalRoot.slideshowIndexMap[cleanPath] || "") : "";
                    if (staticPoster !== "") vid = false;
                    if (vid) barWindow.snapshotLayer(barWindow.activeLayer === 1 ? 0 : 1, cleanPath);
                    let playPath = staticPoster !== "" ? staticPoster : (vid ? barWindow.playbackPath(cleanPath) : cleanPath);

                    let slash = cleanPath.lastIndexOf("/");
                    let filename = cleanPath.substring(slash + 1);
                    if (!filename.startsWith("wallpaper.")) {
                        barWindow.originalFileName = filename;
                    }

                    if (barWindow.isInitialLoad) {
                        barWindow.isInitialLoad = false;
                        barWindow.transitionProgress = 1.0;
                        barWindow.isPreloading = false;
                        if (barWindow.activeLayer === 1) {
                            barWindow.isVideoA = vid;
                            barWindow.pathA = playPath;
                            barWindow.activeLayer = 0;
                            if (vid) barWindow.playA();
                        } else {
                            barWindow.isVideoB = vid;
                            barWindow.pathB = playPath;
                            barWindow.activeLayer = 1;
                            if (vid) barWindow.playB();
                        }
                        barWindow.currentWallpaperPath = cleanPath;
                        return;
                    }

                    Wallpaper.transitionPending = true;
                    let wasInterrupted = transitionAnim.running;
                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.transitionProgress = 0.0;
                    barWindow.isPreloading = true;

                    if (barWindow.activeLayer === 1) {
                        // An interrupted transition can leave layer A already holding a live
                        // video (from the fade-in that never finished). Overwriting pathA in
                        // place would just swap the MediaPlayer's source, which the ffmpeg
                        // backend never fully releases -> force-destroy it first so the Loader
                        // rebuilds a fresh MediaPlayer instead of leaking the old one.
                        if (wasInterrupted) barWindow.stopA();
                        barWindow.isVideoA = vid;
                        barWindow.pathA = playPath;
                        barWindow.activeLayer = 0;
                        if (vid) {
                            barWindow.playA();
                            videoWarmUpTimer.restart();
                        } else {
                            Qt.callLater(barWindow.triggerTransition);
                        }
                    } else {
                        if (wasInterrupted) barWindow.stopB();
                        barWindow.isVideoB = vid;
                        barWindow.pathB = playPath;
                        barWindow.activeLayer = 1;
                        if (vid) {
                            barWindow.playB();
                            videoWarmUpTimer.restart();
                        } else {
                            Qt.callLater(barWindow.triggerTransition);
                        }
                    }

                    barWindow.currentWallpaperPath = cleanPath;
                }

                function changeWallpaper(path, ttype) {
                    if (!path) return;
                    if (barWindow.transitionBusy) {
                        barWindow.interruptWith(path, ttype);
                        return;
                    }

                    barWindow.isInitialLoad = false;

                    let fromMenu = false;
                    let customOriginX = -1;
                    let customOriginY = -1;
                    let chosenType = -1;

                    if (typeof ttype === "object" && ttype !== null) {
                        if (ttype.type !== undefined) chosenType = Number(ttype.type);
                        if (ttype.originX !== undefined) customOriginX = Number(ttype.originX);
                        if (ttype.originY !== undefined) customOriginY = Number(ttype.originY);
                        fromMenu = true;
                    } else if (typeof ttype === "string" && ttype.indexOf("circle") !== -1) {
                        chosenType = 2;
                        let parts = ttype.split(":");
                        if (parts.length >= 3) {
                            customOriginX = parseFloat(parts[1]);
                            customOriginY = parseFloat(parts[2]);
                        }
                        fromMenu = true;
                    } else if (typeof ttype === "number" && ttype >= 0) {
                        chosenType = ttype;
                    }

                    if (typeof DesktopMenuController !== "undefined" && DesktopMenuController.isMenuShuffle) {
                        let isTargetScreen = !DesktopMenuController.screen || !DesktopMenuController.screen.name || (barWindow.screen && DesktopMenuController.screen.name === barWindow.screen.name);
                        if (isTargetScreen) {
                            fromMenu = true;
                            chosenType = 2;
                            customOriginX = DesktopMenuController.menuOriginX;
                            customOriginY = DesktopMenuController.menuOriginY;
                        }
                    }

                    let fx = Wallpaper.resolveTransition(chosenType);
                    barWindow.activeTransitionType = fx.type;
                    barWindow.activeDuration = fx.duration;
                    barWindow.wipeIsVertical = fx.vertical;
                    barWindow.swipeDirection = fx.direction;
                    barWindow.transitionSeed = Math.random() * 100.0;

                    if (fromMenu && customOriginX >= 0 && customOriginY >= 0) {
                        barWindow.transitionOriginX = customOriginX;
                        barWindow.transitionOriginY = customOriginY;
                    } else if (fx.centered) {
                        barWindow.transitionOriginX = 0.5;
                        barWindow.transitionOriginY = 0.5;
                    } else {
                        barWindow.transitionOriginX = 0.15 + Math.random() * 0.70;
                        barWindow.transitionOriginY = 0.15 + Math.random() * 0.70;
                    }

                    if (typeof DesktopMenuController !== "undefined") {
                        DesktopMenuController.isMenuShuffle = false;
                    }

                    let cleanPath = String(path).trim();
                    let slash = cleanPath.lastIndexOf("/");
                    let origName = cleanPath.substring(slash + 1);
                    let dot = cleanPath.lastIndexOf(".");
                    let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    let histFile = wpCacheDir + "/history.txt";
                    let vid = barWindow.isVideo(cleanPath);
                    let snapshotPath = barWindow.wpSnapshotPath;
                    let monSnapshotPath = barWindow.wpMonitorSnapshotPath;
                    Quickshell.execDetached(["bash", "-c",
                        "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\" && printf '%s' \"$4\" > \"${3}_name\" && cp -f \"$2\" \"$5\"" +
                        " && if [ \"$9\" != 1 ]; then cp -f \"$2\" \"$6\" && cp -f \"$2\" \"$7\"; fi" +
                        " && ( HIST=\"$8\"; if [ -f \"$HIST\" ]; then grep -v -F -x -- \"$4\" \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\\n' \"$4\" | cat - \"$HIST.tmp\" > \"$HIST\"; rm -f \"$HIST.tmp\"; else printf '%s\\n' \"$4\" > \"$HIST\"; fi )",
                        "_", wpCopyDir, cleanPath, wpStatePath, origName, dest, snapshotPath, monSnapshotPath, histFile, vid ? "1" : "0"
                    ]);

                    if (vid) {
                        // Theme from the same poster the picker shows, not from the
                        // frame at 1s, which can be an intro or a fade and gave a
                        // second, unrelated palette a moment after the first one.
                        let poster = globalRoot.slideshowIndexMap[cleanPath] || "";
                        videoSnapshotProcess.themeFromPoster = poster !== "";
                        if (poster !== "" && typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(poster);
                        }
                        videoSnapshotProcess.targetPath = cleanPath;
                        videoSnapshotProcess.running = false;
                        videoSnapshotProcess.running = true;
                    } else {
                        if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(cleanPath);
                        }
                    }

                    barWindow._loadNew(cleanPath, true);
                }

                function handleDrop(drop) {
                    let raw = "";
                    if (drop.hasUrls && drop.urls.length > 0) {
                        raw = drop.urls[0].toString();
                    } else if (drop.hasText && drop.text.length > 0) {
                        let lines = drop.text.trim().split("\n");
                        raw = lines[0].trim();
                    }
                    if (!raw) return;

                    let cleanPath = decodeURIComponent(raw.replace(/^file:\/\//, "")).trim();
                    if (!barWindow.isSupportedMedia(cleanPath)) return;

                    let scrW = barWindow.width > 0 ? barWindow.width : (barWindow.screen && barWindow.screen.geometry ? barWindow.screen.geometry.width : 1920);
                    let scrH = barWindow.height > 0 ? barWindow.height : (barWindow.screen && barWindow.screen.geometry ? barWindow.screen.geometry.height : 1080);
                    let normX = scrW > 0 ? Math.max(0.0, Math.min(1.0, drop.x / scrW)) : 0.5;
                    let normY = scrH > 0 ? Math.max(0.0, Math.min(1.0, drop.y / scrH)) : 0.5;

                    barWindow.changeWallpaper(cleanPath, {
                        type: 2,
                        originX: normX,
                        originY: normY
                    });
                }

                NumberAnimation {
                    id: transitionAnim
                    target: barWindow
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: barWindow.activeDuration
                    easing.type: Easing.InOutCubic
                    onFinished: barWindow.completeTransition()
                }

                FrameAnimation {
                    id: captureWait
                    property int frames: 0
                    onTriggered: {
                        captureWait.frames++;
                        if (captureWait.frames >= 60) barWindow.applyFrozenFrame();
                    }
                }


                Component {
                    id: videoLayerCompA
                    Item {
                        anchors.fill: parent
                        function play() { playerA.play(); }
                        function stop() { playerA.stop(); }

                        MediaPlayer {
                            id: playerA
                            source: barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            videoOutput: videoOutputA
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    playerA.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputA
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Component {
                    id: videoLayerCompB
                    Item {
                        anchors.fill: parent
                        function play() { playerB.play(); }
                        function stop() { playerB.stop(); }

                        MediaPlayer {
                            id: playerB
                            source: barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            videoOutput: videoOutputB
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    playerB.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputB
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    ShaderEffectSource {
                        id: frozenFrame
                        anchors.fill: parent
                        z: 0
                        sourceItem: (barWindow.capturingFrame || barWindow.frozenActive) ? scene : null
                        live: false
                        recursive: true
                        hideSource: false
                        visible: barWindow.capturingFrame || barWindow.frozenActive
                        onScheduledUpdateCompleted: {
                            if (barWindow.capturingFrame) barWindow.applyFrozenFrame();
                        }
                    }

                    ShaderEffect {
                        id: transitionShaderA
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerA.layer.enabled

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(barWindow.wipeIsVertical ? 1.0 : 0.0, barWindow.swipeDirection, barWindow.transitionSeed, 0.0)
                        property color tint: "transparent"

                        fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb"
                    }

                    Item {
                        id: layerA
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 0
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || (p < 1.0 && !barWindow.frozenActive)

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            if (barWindow.activeTransitionType !== 0) return 1.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        layer.enabled: barWindow.activeTransitionType !== 0 && isIncoming && !barWindow.isPreloading && p < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: transitionShaderA
                            maskThresholdMin: 0.0
                            maskSpreadAtMin: 0.0
                        }

                        AnimatedImage {
                            id: imgA
                            anchors.fill: parent
                            source: !barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoA && barWindow.pathA !== ""
                            cache: true
                            speed: barWindow.playbackPaused ? 0 : 1
                            playing: !Wallpaper.staticWallpapers
                            sourceSize.width: parent.width > 0 ? Math.ceil(parent.width * (Screen.devicePixelRatio || 1)) : 0
                            sourceSize.height: parent.height > 0 ? Math.ceil(parent.height * (Screen.devicePixelRatio || 1)) : 0
                        }

                        Loader {
                            id: videoLoaderA
                            anchors.fill: parent
                            active: barWindow.everVideoA
                            asynchronous: false
                            sourceComponent: videoLayerCompA
                            visible: barWindow.isVideoA
                            onLoaded: {
                                if (item && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }

                    ShaderEffect {
                        id: transitionShaderB
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerB.layer.enabled

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(barWindow.wipeIsVertical ? 1.0 : 0.0, barWindow.swipeDirection, barWindow.transitionSeed, 0.0)
                        property color tint: "transparent"

                        fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb"
                    }

                    Item {
                        id: layerB
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 1
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || (p < 1.0 && !barWindow.frozenActive)

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            if (barWindow.activeTransitionType !== 0) return 1.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        layer.enabled: barWindow.activeTransitionType !== 0 && isIncoming && !barWindow.isPreloading && p < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: transitionShaderB
                            maskThresholdMin: 0.0
                            maskSpreadAtMin: 0.0
                        }

                        AnimatedImage {
                            id: imgB
                            anchors.fill: parent
                            source: !barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoB && barWindow.pathB !== ""
                            cache: true
                            speed: barWindow.playbackPaused ? 0 : 1
                            playing: !Wallpaper.staticWallpapers
                            sourceSize.width: parent.width > 0 ? Math.ceil(parent.width * (Screen.devicePixelRatio || 1)) : 0
                            sourceSize.height: parent.height > 0 ? Math.ceil(parent.height * (Screen.devicePixelRatio || 1)) : 0
                        }

                        Loader {
                            id: videoLoaderB
                            anchors.fill: parent
                            active: barWindow.everVideoB
                            asynchronous: false
                            sourceComponent: videoLayerCompB
                            visible: barWindow.isVideoB
                            onLoaded: {
                                if (item && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }

                    ShaderEffect {
                        id: paintGlow
                        anchors.fill: parent
                        z: 3
                        visible: barWindow.activeTransitionType === 4 && !barWindow.isPreloading && barWindow.transitionProgress < 1.0

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(0.0, 0.0, barWindow.transitionSeed, 1.0)
                        property color tint: ThemeBackend.mauve

                        fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb"
                    }
                }

                DropArea {
                    anchors.fill: parent

                    onEntered: drag => {
                        if (drag.hasUrls || drag.hasText) {
                            if (typeof drag.acceptProposedAction === "function") {
                                drag.acceptProposedAction();
                            } else if (typeof drag.accept === "function") {
                                drag.accept();
                            }
                            drag.accepted = true;
                        }
                    }

                    onDropped: drop => {
                        barWindow.handleDrop(drop);
                        if (typeof drop.acceptProposedAction === "function") {
                            drop.acceptProposedAction();
                        } else if (typeof drop.accept === "function") {
                            drop.accept();
                        }
                        drop.accepted = true;
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton | Qt.LeftButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                DesktopMenuController.toggle(barWindow.screen, mouse.x, mouse.y, "desktop");
                            } else {
                                DesktopMenuController.hide();
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Wallpaper slideshow ---
    // Lives at the top level (outside the per-monitor Variants above) so it
    // fires exactly once regardless of screen count. The Timer only runs
    // when enabled with a non-empty pool, so it costs nothing (no timer,
    // no polling) while the feature is off, which is the common case.
    property var slideshowSettings: ({enabled: false, intervalMinutes: 15, pool: []})
    property int slideshowLastIndex: -1

    function refreshSlideshowSettings() {
        globalRoot.slideshowSettings = Config.getSetting("wallpaperSlideshow", {enabled: false, intervalMinutes: 15, pool: []});
    }

    Connections {
        target: Config
        function onSettingsLoaded() { globalRoot.refreshSlideshowSettings(); }
        function onDataReadyChanged() { if (Config.dataReady) globalRoot.refreshSlideshowSettings(); }
    }

    Component.onCompleted: {
        if (Config.dataReady) globalRoot.refreshSlideshowSettings();
    }

    // Pool indices in playback order: colour-sorted in "color" mode, the
    // pool's own order otherwise.
    function slideshowOrder() {
        let pool = globalRoot.slideshowSettings.pool || [];
        let entries = pool.map((it, i) => ({ it: it, i: i }));
        if ((globalRoot.slideshowSettings.mode || "random") === "color") {
            const order = { "Red": 1, "Orange": 2, "Yellow": 3, "Green": 4, "Blue": 5, "Purple": 6, "Pink": 7, "Monochrome": 8 };
            entries.sort((a, b) => {
                let bA = globalRoot.slideshowBucketMap[a.it.path] || "Monochrome";
                let bB = globalRoot.slideshowBucketMap[b.it.path] || "Monochrome";
                let oA = order[bA] || 10;
                let oB = order[bB] || 10;
                if (oA !== oB) return oA - oB;
                return String(a.it.path).localeCompare(String(b.it.path));
            });
        }
        return entries.map(e => e.i);
    }

    function slideshowAdvance() {
        let pool = globalRoot.slideshowSettings.pool || [];
        if (pool.length === 0) return;

        let idx;
        if ((globalRoot.slideshowSettings.mode || "random") === "color") {
            let order = globalRoot.slideshowOrder();
            idx = order[(order.indexOf(globalRoot.slideshowLastIndex) + 1) % order.length];
        } else {
            idx = Math.floor(Math.random() * pool.length);
            if (pool.length > 1 && idx === globalRoot.slideshowLastIndex) {
                idx = (idx + 1) % pool.length;
            }
        }
        globalRoot.slideshowApply(idx);
    }

    // Manual next/previous (SUPER + numpad +/-). In color mode it walks the
    // colour order both ways; in random mode both keys just draw a new random
    // wallpaper, so there is no history to keep. Restarts the timer so an
    // automatic change does not land right after a manual one.
    function slideshowStep(delta) {
        let pool = globalRoot.slideshowSettings.pool || [];
        if (pool.length === 0) return;
        if ((globalRoot.slideshowSettings.mode || "random") !== "color") {
            globalRoot.slideshowAdvance();
            if (slideshowTimer.running) slideshowTimer.restart();
            return;
        }
        let order = globalRoot.slideshowOrder();
        let pos = order.indexOf(globalRoot.slideshowLastIndex);
        if (pos === -1) {
            let current = Wallpaper.getWallpaperPath("");
            pos = order.findIndex(i => pool[i] && pool[i].path === current);
        }
        let next = pos === -1 ? (delta > 0 ? 0 : order.length - 1)
                              : ((pos + delta) % order.length + order.length) % order.length;
        globalRoot.slideshowApply(order[next]);
        if (slideshowTimer.running) slideshowTimer.restart();
    }

    function slideshowApply(idx) {
        let pool = globalRoot.slideshowSettings.pool || [];
        globalRoot.slideshowLastIndex = idx;
        let item = pool[idx];
        if (!item || !item.path) return;
        Wallpaper.setWallpaper("all", item.path, "fade");

        if (typeof Matugen === "undefined" || typeof Matugen.generate !== "function") return;
        if (!item.isVideo) {
            Matugen.generate(item.path);
            return;
        }
        let poster = item.posterPath || "";
        if (!poster) {
            poster = globalRoot.slideshowIndexMap[item.path] || "";
        }
        if (poster) {
            Matugen.generate(poster);
        }
    }

    IpcHandler {
        target: "slideshow"
        function next(): void { globalRoot.slideshowStep(1); }
        function prev(): void { globalRoot.slideshowStep(-1); }
    }

    property var slideshowIndexMap: ({})
    property var slideshowBucketMap: ({})

    // original file path -> screen-sized copy built by the indexer. A hardware
    // decoder sizes its surface pool from the encoded resolution, so playing a
    // 4K file on a smaller panel costs a few hundred MB of GTT for pixels that
    // are scaled away before they are ever shown. Empty until the copy is ready,
    // and playback silently falls back to the original meanwhile.
    property var transcodedMap: ({})

    FileView {
        id: slideshowIndexFile
        path: Caching.getCacheDir("wallpaper") + "/current_index.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let raw = typeof text === "function" ? text() : text;
            globalRoot.rebuildSlideshowIndexMap(raw);
        }
    }

    function rebuildSlideshowIndexMap(raw) {
        try {
            if (typeof raw !== "string") return;
            let data = JSON.parse(raw);
            let map = {};
            let bucketMap = {};
            let transcoded = {};
            let items = data.items || [];
            for (let i = 0; i < items.length; i++) {
                if (items[i].isVideo && items[i].filePath && items[i].posterPath) {
                    map[items[i].filePath] = items[i].posterPath;
                }
                if (items[i].filePath) {
                    bucketMap[items[i].filePath] = items[i].bucket || "Monochrome";
                }
                if (items[i].filePath && items[i].transcodedPath) {
                    transcoded[items[i].filePath] = items[i].transcodedPath;
                }
            }
            globalRoot.slideshowIndexMap = map;
            globalRoot.slideshowBucketMap = bucketMap;
            globalRoot.transcodedMap = transcoded;
        } catch (e) {}
    }

    Timer {
        id: slideshowTimer
        interval: Math.max(1, globalRoot.slideshowSettings.intervalMinutes || 15) * 60000
        running: !!globalRoot.slideshowSettings.enabled && (globalRoot.slideshowSettings.pool || []).length > 0 && !CurrentFocus.isFullscreenActive
        repeat: true
        triggeredOnStart: false
        onTriggered: globalRoot.slideshowAdvance()
    }

    // Pauses video-wallpaper decoding while a fullscreen/maximized app (games, players)
    // has focus, so it doesn't keep consuming CPU/GPU behind a fully-occluded surface.
    Connections {
        target: CurrentFocus
        function onIsFullscreenActiveChanged() {
            Wallpaper.setPlayback("all", CurrentFocus.isFullscreenActive ? "pause" : "play");
        }
    }
}

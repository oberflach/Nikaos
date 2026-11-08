# Guide for AI assistants working on Nikaos

You are probably here because a Nikaos user asked you to change their desktop.
Read this file first: it explains how Nikaos is built, where things live and
the rules a change must follow. Answer the user in their language.

## What Nikaos is

Nikaos is a desktop shell (bar, settings, widgets, launcher, lock screen,
notifications, wallpaper engine...) written in QML for
[Quickshell](https://quickshell.outfoxxed.me/), mainly for the Hyprland
compositor. It is a fork of [Serpantinum](https://github.com/ilyamiro/serpantinum)
by ilyamiro, under the **GNU AGPL-3.0**.

License rules you must keep when editing or redistributing:
- keep `LICENSE.md` and the AGPL-3.0 license;
- keep the credit to Serpantinum and ilyamiro (README, About tab, welcome
  screen, installer);
- never add telemetry or anything that sends user data somewhere.

## Where the code runs

| What | Path |
|---|---|
| Installed shell (what actually runs) | `~/.local/share/serpantinum/` (`src/`, `bin/`) |
| Git repository the user cloned | wherever they cloned it (installer: `install/install.sh`) |
| User settings | `~/.config/serpantinum/settings.json` |
| State (palettes, game mode flags, version) | `~/.local/state/serpantinum/` |
| Cache (wallpaper index, posters, copies) | `~/.cache/serpantinum/` |
| Hyprland config | `~/.config/hypr/` (`hyprland.lua`, `config/*.lua`) |

The installer copies the repository's `src/` and `bin/` into
`~/.local/share/serpantinum/`. A change made in the installed copy works at
once but is lost on the next reinstall; for a lasting change, edit the
repository and reinstall, or edit both.

### Internal names stay "serpantinum" (do not rename them)

The helper programs `serpantinum-core`, `serpantinum-audio` and
`serpantinum-gamma` are separate projects with these paths and D-Bus names
(`org.serpantinum.*`) built in. So the install, config, state and cache
directories, the `SERPANTINUM_DIR` variable, the `serpantinum` command and
IPC names keep the upstream name. Only what the user sees is called Nikaos,
and `bin/nikaos` / `bin/nikaosd` are aliases of `bin/serpantinum` /
`bin/serpantinumd`.

## Layout of the repository

```
bin/                    nikaos / serpantinum CLI, nikaosd / serpantinumd daemon
install/                installer (install.sh, modules/*.sh, package lists)
compositors/hyprland/   Hyprland config shipped to ~/.config/hypr
config/                 other shipped configs (kitty, sddm)
src/quickshell/         the shell (QML)
  Shell.qml             entry point: loads bar, overlay, widgets, wallpaper...
  qmldir                registers singletons and shared components
  singletons/           global state: system/ (Config, I18n, GameMode, Caching...),
                        theme/ (ThemeBackend, Matugen, Wallpaper), info/ (SysData),
                        audio/, environment/ (TabletMode, Vpn, VirtualKeyboard...)
  bar/                  top bar; modules registered in BarModuleRegistry.qml,
                        their looks in bar/faces/
  guide/                Settings window ("guide" is the old name): one folder or
                        file per tab, tabs listed in guide/GuidePopup.qml
  overlay/              Super+G overlay: Overlay.qml (top chips), OverlayCard.qml
                        (every card: recorder, volume, resources, crosshair, notes,
                        apps, transparency, floating image, game mode)
  cheatsheet/           Super+/ keybind cheatsheet
  widgets/              desktop widgets: WidgetRegistry.qml, faces/, editor
                        (WidgetRedactor.qml), per-widget shade shader
  wallpaper/            WallpaperEngine.qml (playback, transitions, slideshow),
                        WallpaperPicker.qml
  quickactions/         panel that slides from the screen edge
  syspanel/, lock/, launcher/, media/, network/, notifications/, dock/...
  reusables/            shared UI: inputs/ (Toggle, Switch, Input, NumberSelector,
                        Dropdown...), guide/ (SettingsRow, SettingsBlob)...
src/scripts/            shell and Python helpers called from QML
src/assets/             languages/*.json (translations), shaders, fonts, matugen
                        templates, sounds
```

## Rules for changes

1. **Everything the user can change is a clickable option in Settings.** Do not
   ask users to edit config files or write code. If a feature needs a file
   edited (another app's config, a udev rule...), add a button that does it,
   like `src/scripts/integrations.sh` and the Hardware section do.
2. **Machine-specific features are off by default** and live in
   Settings > General > Hardware (`guide/general/GeneralHardwareSection.qml`,
   settings key `hardware`). They must detect whether the hardware exists and
   run nothing when disabled (see `TabletMode.qml`, `Vpn.qml`).
3. **Translate every visible string**: use `I18n.t("some.key", "English fallback")`
   and add the key to at least `src/assets/languages/en.json` and `fr.json`.
4. **Match the surrounding code**: same naming, same comment density, small
   focused changes. Mark Nikaos-specific code with a short comment when it
   changes upstream behaviour.
5. **No hard-coded personal paths** (`/home/<user>`...). Use `Caching.serpantinumDir`,
   `Caching.stateDir`, `Caching.getCacheDir()`, `Quickshell.env("HOME")`.

## How settings work

- Read: `Config.getSetting("section", defaultObject)`; write:
  `Config.setSetting("section", newObject)`. Values end up in `settings.json`
  and every binding using them updates live.
- A settings section is a `SettingsBlob` of `SettingsRow`s, each holding a
  control (`Toggle`, `Switch`, `Input`, `NumberSelector`, `ClickButton`...).
  Copy an existing section, e.g. `guide/general/GeneralHardwareSection.qml`.
- Register a new QML file in the `qmldir` of its folder, then place it in the
  tab file (e.g. `guide/general/GeneralTab.qml`).
- A `Toggle` that writes a setting should bind back after the click:
  `onToggled: (c) => { save(c); myToggle.checked = Qt.binding(() => ...) }`.

## Main features added by Nikaos (where to look)

| Feature | Files |
|---|---|
| Colours morphing with the wallpaper transition | `singletons/theme/ThemeBackend.qml` (morph), `wallpaper/WallpaperEngine.qml` (`triggerTransition`), `singletons/theme/Wallpaper.qml` |
| Per-icon shades of the bar | `ThemeBackend.iconShade*`, `guide/theme/ThemeIconShadesSection.qml` |
| Per-widget hue/brightness (right click in the editor) | `widgets/Widget.qml`, `widgets/WidgetRedactor.qml`, `widgets/shaders/widget_shade.frag` |
| GPU usage | `singletons/info/SysData.qml` (`gpuPercent`), bar `faces/sysmon/`, `quickactions/actions/SystemUsage.qml`, `widgets/faces/usage/Gpu*` |
| Super+G per-app transparency and blur | `overlay/OverlayCard.qml` (transparency card), `scripts/window-transparency*.sh` (writes `~/.config/hypr/config/transparency.lua`) |
| Game mode | `singletons/system/GameMode.qml`, game card in `overlay/OverlayCard.qml`, flags read by `scripts/window-transparency-rules.sh` |
| Screen positions | `guide/display/DisplayMainState.qml` (writes `config/monitor-positions.lua`) |
| Window gaps | `guide/general/GeneralGapsSection.qml`, `scripts/gaps_toggle.sh` |
| Light video wallpapers | `scripts/wallpaper/transcode.py`, `guide/wallpaper/VideoWallpaperSection.qml` |
| Hardware options and one-click setups | `guide/general/GeneralHardwareSection.qml`, `scripts/integrations.sh`, `scripts/conservation_mode.sh` |

## Testing a change

- Reload the shell: `nikaos reload` (or Super+R). Singletons, shaders and the
  daemon need a full restart: `nikaos restart`.
- Logs: `quickshell log "$(ls -td /run/user/$UID/quickshell/by-id/*/ | head -1)log.qslog"`.
  After a reload, look for `ERROR` lines and `Configuration Loaded`.
- Check QML syntax without running: `/usr/lib/qt6/bin/qmllint file.qml`.
- Call the shell from a terminal:
  `quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml ipc call <target> <method>`
  (targets include `theme`, `gamemode`, `overlay`, `wallpaper`, `slideshow`, `floating`).
- Shaders: edit the `.frag` file, then compile it next to it:
  `/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o file.frag.qsb file.frag`.
- Before deleting or overwriting the user's files, back them up and tell them.

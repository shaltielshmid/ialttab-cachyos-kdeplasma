# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A KWin Effect (not a TabBox switcher) for KDE Plasma 6 Wayland. It implements a searchable, MRU-ordered window switcher that stays open after key release until explicitly dismissed. Written entirely in QML — no build step.

## Install / Update

```bash
./install.sh          # first install (also configures keyd for CapsLock → F19)
```

To update after editing QML:

```bash
kpackagetool6 --type KWin/Effect --upgrade ialttab-latched
qdbus6 org.kde.KWin /KWin reconfigure
```

KWin may cache loaded QML. If changes don't appear, disable and re-enable the effect in System Settings → Window Management → Desktop Effects, or log out/in.

## Architecture

The entire effect lives in one file: `ialttab-latched/contents/ui/main.qml`.

**SceneEffect vs TabBox:** Using `SceneEffect` means KWin creates one QML delegate instance per physical screen. The effect itself holds all state; each delegate reads from the parent `effect` object. Only the delegate on `targetScreen` (captured at open time) shows the panel and handles keyboard input.

**Window list state:**
- `mruWindows` — all tracked windows in true MRU order, maintained via `Workspace.windowActivated`. Persists across open/close cycles.
- `shownWindows` — `mruWindows` filtered by the current `query`. Rebuilt on every query change and on open.
- Cold start (first open after enabling): `seedFromStackingOrder()` fills `mruWindows` from `Workspace.stackingOrder` in reverse order as a best-effort MRU approximation.

**Filtering:** `windowMatches()` does simple multi-word substring match against `resourceClass + resourceName + desktopFileName + caption`. Runs on every `query` change via `onQueryChanged: rebuildShownWindows(true)`.

**Multi-screen:** `chooseTargetScreen()` is called at open time and stores a stable string key (`name|x,y,WxH`) in `targetScreenKey`. Each delegate's `targetScreen` computed property compares against this key. Non-target delegates render nothing (the delegate root is a plain `Item` — not a `Rectangle` — to avoid KWin clearing inactive screen framebuffers to black).

**Shortcut:** Registered via `ShortcutHandler` with default `F19`. The install script configures `keyd` to map CapsLock tap → F19.

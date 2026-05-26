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

## Per-app display label rewrites

The user frequently wants to tweak how specific apps are displayed in the picker so they're faster to spot. These are first-class, expected customizations — not edge cases. Examples:

- WhatsApp Web (Chrome PWA): strip the `chrome-` prefix from the class line.
- Dolphin: prefix the title with `Opus`.
- chromium: prefix the class line with `chrome-`.

When the user asks for a rewrite like this, just wire it up exactly as asked — do not gate behind toggles or "smart" detection (same spirit as the hotkeys-unconditional rule in user memory).

**Where to wire it:** the row delegate in `ialttab-latched/contents/ui/main.qml` computes `classText` and `titleText` at the top of the row `delegate: Item` (currently lines 606–607). Route both through a single pair of helpers on the `effect` root — e.g. `displayTitle(w)` / `displayClass(w)` — so every rewrite lives in one place and is easy to scan/edit. Match on `resourceClass` first (e.g. `chrome-whatsapp-…` for Chrome PWAs), then `desktopFileName`, then `caption` substrings as a last resort.

**Search uses the rewritten text, not the raw fields.** The whole point of these rewrites is to fix the user's search experience. If `chrome-` is stripped from WhatsApp Web's display, typing `chrome` MUST NOT surface that window. Update `searchableText()` (currently line 209) to build its haystack from `displayTitle(w)` / `displayClass(w)` so display and search stay in lockstep. Never leave the raw fields in the haystack as a fallback "just in case" — that re-introduces exactly the noise the rewrite was meant to remove.

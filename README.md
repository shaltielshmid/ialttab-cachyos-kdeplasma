# iAltTab Latched Search for KWin / KDE Plasma 6

> **Tested on:** CachyOS (Arch-based) · KDE Plasma 6.6 · KWin 6.6 · Wayland

This is the latched version of the iAltTab-style switcher. It is a **KWin Effect**, not a TabBox switcher, so it opens with a normal shortcut and stays open after you release the key.

It will likely work on any KDE Plasma 6.x / KWin 6.x Wayland setup, but has only been tested on CachyOS with Plasma 6.6.

## Install

```bash
git clone https://github.com/shaltielshmid/ialttab-cachyos-kdeplasma
cd ialttab-cachyos-kdeplasma
./install.sh
```

The installer also configures [keyd](https://github.com/rvaiya/keyd) to remap **CapsLock** to F19 on tap (and Ctrl on hold), so you can trigger the switcher with CapsLock without losing CapsLock's usefulness as a modifier. If `/etc/keyd/default.conf` already exists, the installer skips this step and tells you to add `capslock = overload(control, f19)` to your `[main]` section yourself.

Then check:

```text
System Settings -> Window Management -> Desktop Effects -> iAltTab Latched Search
System Settings -> Shortcuts -> KWin -> Toggle iAltTab Latched Search
```

Default shortcut is `F19`.

## Use

```text
F19              open/close
Type             filter by title/class/app-id
1-9              activate Nth visible entry
Enter            activate selection
Escape           close without switching
Tab/Down/Right   next
Shift+Tab/Up/Left previous
PageUp/PageDown  jump 5
Home/End         first/last
Ctrl+U/Ctrl+L    clear search
Ctrl+W           close selected window
Mouse click      activate window
Middle click     close selected window
```

When opened with an empty search, the initial selection is the previous MRU window, matching Alt-Tab muscle memory, but it does **not** activate until Enter/click.

## Notes

The first run after installing has only a stacking-order fallback for older windows. After the effect is enabled, it maintains MRU order using KWin's `Workspace.windowActivated` signal.

If edits do not appear immediately, disable/enable the effect or log out/in; KWin may cache loaded QML.

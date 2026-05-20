#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
PKG_DIR="$PWD/ialttab-latched"
PLUGIN_ID="ialttab-latched"

# Install keyd if missing
if ! command -v keyd >/dev/null 2>&1; then
  echo "keyd not found, installing..."
  if command -v paru >/dev/null 2>&1; then
    paru -S --noconfirm keyd
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm keyd
  else
    echo "Neither paru nor pacman found. Install keyd manually." >&2
    exit 1
  fi
fi

# Configure keyd: remap CapsLock to F19 (tap) / Ctrl (hold)
KEYD_CONF="/etc/keyd/default.conf"
if [ ! -f "$KEYD_CONF" ]; then
  echo "Creating $KEYD_CONF..."
  sudo mkdir -p /etc/keyd
  sudo tee "$KEYD_CONF" > /dev/null <<'EOF'
[ids]
*

[main]
capslock = overload(control, f19)
EOF
  sudo systemctl enable --now keyd
  echo "keyd configured and started."
else
  echo "NOTE: $KEYD_CONF already exists — skipping keyd configuration."
  echo "      Please add 'capslock = overload(control, f19)' to your [main] section manually."
fi

if ! command -v kpackagetool6 >/dev/null 2>&1; then
  echo "kpackagetool6 was not found. Install KDE Frameworks / kpackage tools first." >&2
  exit 1
fi

if kpackagetool6 --type KWin/Effect --list 2>/dev/null | grep -q "^${PLUGIN_ID}$"; then
  kpackagetool6 --type KWin/Effect --upgrade "$PKG_DIR"
else
  kpackagetool6 --type KWin/Effect --install "$PKG_DIR"
fi

# Enable the effect and ask KWin to reload. The loadEffect call is best-effort;
# opening Desktop Effects and toggling the effect also works.
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kwinrc --group Plugins --key "${PLUGIN_ID}Enabled" true || true
fi

if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$PLUGIN_ID" >/dev/null 2>&1 || true
fi

echo "Installed ${PLUGIN_ID}."
echo "Enable/check it in: System Settings -> Window Management -> Desktop Effects."
echo "Shortcut: System Settings -> Shortcuts -> KWin -> Toggle iAltTab Latched Search."

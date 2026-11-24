#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="org.gabrielbraz.peripheralbattery"

chmod +x "$SCRIPT_DIR/contents/scripts/battery_reader.py"

if kpackagetool6 --type Plasma/Applet --show "$PLUGIN_ID" &>/dev/null; then
    echo "Upgrading widget $PLUGIN_ID..."
    kpackagetool6 --type Plasma/Applet --upgrade "$SCRIPT_DIR"
else
    echo "Installing widget $PLUGIN_ID..."
    kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR"
fi

echo ""
echo "Done! Next steps:"
echo "1. Right-click your KDE Plasma panel -> 'Add or Manage Widgets...'"
echo "2. Search for 'Peripheral Battery' and drag it onto your panel."
echo ""
echo "Tip: if you upgraded an already-loaded widget, restart plasmashell with:"
echo "  systemctl --user restart plasma-plasmashell.service"

#!/bin/bash
# install.sh — seed ~/.local/share/omarchy and ~/.config/omarchy from this
# repo. Idempotent for the dock settings file; themes/default/bin are always
# replaced. Does NOT deploy i3/QS dotfiles — that is deploy.sh.
#
# Layout:
#   ~/.local/share/omarchy/themes/   ← bundled themes
#   ~/.local/share/omarchy/default/  ← themed/*.tpl templates and menu defaults
#   ~/.local/share/omarchy/bin/      ← X11/i3 omarchy-* commands
#   ~/.config/omarchy/themes/        ← user overrides only (empty by design)
#   ~/.config/omarchy/themed/        ← created empty; deploy.sh fills *.tpl
#
# Everything comes from home/.local/share/omarchy in this repo; nothing is
# downloaded. Must run as the login user. If invoked via sudo, re-execs as
# $SUDO_USER so themes do not land in /root/.

set -euo pipefail

# --- resolve install target (never seed root's home by accident) -------------
if [ "$(id -u)" -eq 0 ]; then
	if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
		echo "!! refuse to install as root — run:  ./install.sh" >&2
		echo "   (or:  sudo -u \$USER -H ./install.sh)" >&2
		exit 1
	fi
	echo ":: re-exec as $SUDO_USER (was root via sudo)"
	exec sudo -u "$SUDO_USER" -H "$0" "$@"
fi

TARGET_HOME="${HOME}"
OMARCHY_SHARE="$TARGET_HOME/.local/share/omarchy"
OMARCHY_CONFIG="$TARGET_HOME/.config/omarchy"

echo "========================================================================"
echo "Installing themes and commands"
echo "  user:   $(id -un) ($TARGET_HOME)"
echo "========================================================================"

# Repo root = the directory this script lives in, resolved so it works no
# matter where install.sh is invoked from.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo ":: repo: $REPO_DIR"

SHARE_SRC="$REPO_DIR/home/.local/share/omarchy"

# --- step 1: refresh ~/.local/share/omarchy ----------------------------------
# Replace themes/, default/ and bin/ so a re-run drops files removed from the
# repo; leave the rest of the share dir alone.
echo
echo "-- 1/2  seed $OMARCHY_SHARE ---------------------------------------------"
mkdir -p "$OMARCHY_SHARE" "$OMARCHY_CONFIG"/{themes,themed}
rm -rf "$OMARCHY_SHARE"/{themes,default,bin}
for dir in themes default bin; do
	cp -r "$SHARE_SRC/$dir" "$OMARCHY_SHARE/$dir"
	echo ":: copied $dir/ -> $OMARCHY_SHARE/$dir"
done
INSTALLED=$(find "$OMARCHY_SHARE/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)

echo ":: note: $OMARCHY_CONFIG/themes is for user overrides only (left empty)"

if [ "$INSTALLED" -eq 0 ]; then
	echo "!! no themes landed in $OMARCHY_SHARE/themes — aborting" >&2
	exit 1
fi

# --- step 2: seed dock settings (once) ---------------------------------------
# Write defaults only when missing so a reinstall never
# clobbers an existing customization.
echo
echo "-- 2/2  dock settings ---------------------------------------------------"
DOCK_SETTINGS="$OMARCHY_CONFIG/dock-settings.json"
if [ ! -f "$DOCK_SETTINGS" ]; then
	echo ":: writing default $DOCK_SETTINGS"
	cat > "$DOCK_SETTINGS" <<'EOF'
{
  "fullWidth": false,
  "roundedCorners": true,
  "hoverAnimation": true
}
EOF
else
	echo ":: $DOCK_SETTINGS already present — keeping"
fi

echo
echo "========================================================================"
echo "Installation done."
echo "  themes:  $OMARCHY_SHARE/themes  ($INSTALLED)"
echo "  default: $OMARCHY_SHARE/default"
echo "  bin:     $OMARCHY_SHARE/bin"
echo "  Next:    ./deploy.sh   (i3 / Quickshell / \$HOME dotfiles)"
echo "========================================================================"

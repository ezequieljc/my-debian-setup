#!/bin/bash
# setup.sh — install every system dependency this setup needs on a fresh
# Debian (systemd or sysvinit) or Devuan install. Idempotent; safe to re-run.
#
#   sudo ./setup.sh              required + recommended + the tools the scripts call
#   sudo ./setup.sh --minimal    only the hard-required set (no media/menus/extras)
#   sudo ./setup.sh --optional   also VM / GPU / niche extras (spice, radeontop, …)
#   sudo ./setup.sh --deploy     after installing, run ./install.sh && ./deploy.sh as you
#
# Quickshell and its one backports-only dependency ship in pacotes/ so a fresh
# Debian 13 install never needs trixie-backports or any other extra source.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_RECOMMENDED=1
WITH_OPTIONAL=0
RUN_DEPLOY=0
for arg in "$@"; do
	case "$arg" in
		--minimal)   WITH_RECOMMENDED=0 ;;
		--optional)  WITH_OPTIONAL=1 ;;
		--deploy)    RUN_DEPLOY=1 ;;
		-h|--help)   sed -n '2,14p' "$0"; exit 0 ;;
		*)           echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

# --- become root for apt -------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
	echo "setup.sh needs root for apt — re-running under sudo…"
	exec sudo -E "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "========================================================================"
echo "Dependency setup"
echo "  repo:        $REPO_DIR"
echo "  install for: $TARGET_USER ($TARGET_HOME)"
echo "========================================================================"

# --- package sets -----------------------------------------------------------
# Hard-required: without one of these something core (bar, session, input
# focus, theming, audio/brightness keys, lock, notifications) does not work.
REQUIRED=(
	# bootstrap (rsync: live deploy must replace files by rename, not truncate)
	git rsync ca-certificates curl jq
	# window manager, compositor, session bus
	i3-wm picom dbus-x11
	x11-utils x11-xserver-utils x11-xkb-utils
	# terminal + notifications
	kitty dunst libnotify-bin
	# network / bluetooth / audio / power / brightness
	network-manager bluez rfkill pulseaudio-utils brightnessctl upower
	# wallpaper, lock, idle
	feh hsetroot i3lock xss-lock
	# launcher window-raise, clipboard, live GTK theme push
	xdotool xclip xsettingsd
	# python input-focus helper + i3 IPC (alternating splits) + plugin live watch
	python3 python3-xlib python3-i3ipc inotify-tools
	# polkit agent for pkexec prompts
	mate-polkit
	# process/query tools the scripts shell out to
	psmisc procps xdg-user-dirs
	# QML modules Quickshell plugins import (bar/layouts, controls, tray/effects, shapes, FolderPicker)
	qml6-module-qtquick-layouts
	qml6-module-qtquick-controls
	qml6-module-qtquick-shapes
	qml6-module-qt-labs-folderlistmodel
	qml6-module-qtquick-effects
	# fonts + icons
	fontconfig fonts-jetbrains-mono fonts-noto-color-emoji papirus-icon-theme
)

# Recommended: every widget/panel people actually use.
RECOMMENDED=(
	# media keys / MPRIS (bar media widget). MPD stack omitted — `mpd` postinst
	# fails on Devuan/sysvinit; install mpd/mpdris2/mpc yourself if wanted.
	playerctl
	# screenshots + viewer + `convert` for the colour-picker swatch
	maim flameshot viewnior imagemagick
	# managers opened by widgets (FM is not pinned — Super+Shift+F uses omarchy-launch-files / XDG)
	blueman network-manager-gnome nm-connection-editor
	# battery %, Wi-Fi QR, colour picker, night light
	acpi qrencode gpick redshift
	# power manager started by i3_autostart
	xfce4-power-manager
	# fancy locker + Intel backlight path + `light` fallback
	i3lock-fancy xbacklight light
	# themed system fetch (omarchy-theme-set → ~/.config/fastfetch/config.jsonc)
	fastfetch
	# default terminal ($terminal in i3 keybindings)
	xfce4-terminal
	# network shares (SMB) in the canivt file manager
	gvfs-backends gvfs-fuse
)

# Optional: hardware- or host-specific; nothing breaks without them.
OPTIONAL=(
	spice-vdagent          # VM clipboard sharing + display auto-resize
	thunar                 # XFCE file manager; Ubuntu/GNOME already ships Nautilus
	radeontop              # AMD GPU load in the system stats widget
	intel-gpu-tools        # Intel GPU load via intel_gpu_top (same script)
	# NVIDIA: nvidia-smi comes with the proprietary driver package, not listed here
	power-profiles-daemon  # omarchy-powerprofiles-* (needs D-Bus; works w/ elogind)
	openresolv             # lets omarchy-dns flush the resolver cache
	wireplumber            # wpctl fallback when pactl is absent
)

# No systemd (Devuan / sysvinit Debian): pull elogind so loginctl / xss-lock /
# the locker's session hooks work. On systemd hosts logind already provides it.
if [ ! -d /run/systemd/system ]; then
	REQUIRED+=(elogind libpam-elogind)
fi

# --- resolve + install ----------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive

echo ":: apt-get update"
apt-get update -qq

PKGS=("${REQUIRED[@]}")
if (( WITH_RECOMMENDED )); then PKGS+=("${RECOMMENDED[@]}"); fi
if (( WITH_OPTIONAL ));    then PKGS+=("${OPTIONAL[@]}");    fi

# Drop anything this suite doesn't ship; report it once.
AVAIL=()
MISSING=()
UNINSTALLABLE=()
while read -r p; do
	[ -n "$p" ] || continue
	if apt-cache show "$p" >/dev/null 2>&1; then
		# Some suites can briefly expose a package whose exact-version deps are no
		# longer satisfiable against the currently installed security updates
		# (observed with rfkill on Devuan Excalibur). Skip those instead of aborting
		# the whole bootstrap; the summary calls them out for manual follow-up.
		if apt-get install -s "$p" >/dev/null 2>&1; then
			AVAIL+=("$p")
		else
			UNINSTALLABLE+=("$p")
		fi
	else
		MISSING+=("$p")
	fi
done < <(printf '%s\n' "${PKGS[@]}" | sort -u)

echo ":: installing ${#AVAIL[@]} packages"
apt-get install -y "${AVAIL[@]}"

# --- Quickshell (bundled .deb, pinned) ---------------------------------------
# Debian 13 only ships it in trixie-backports. The exact tested build lives in
# pacotes/; holding it keeps a newer, untested Quickshell from replacing it.
QUICKSHELL_OK=1
DEBS=("$REPO_DIR"/pacotes/*.deb)
if [ "$(dpkg --print-architecture)" = amd64 ] && [ -e "${DEBS[0]}" ]; then
	echo ":: installing bundled Quickshell"
	apt-get install -y "${DEBS[@]}"
	apt-mark hold quickshell libcpptrace1 >/dev/null
elif ! command -v quickshell >/dev/null 2>&1; then
	QUICKSHELL_OK=0
fi

# --- session D-Bus (Quickshell must reach the bus) -----------------------------
OPTS=/etc/X11/Xsession.options
if [ -f "$OPTS" ]; then
	if ! grep -qxF 'use-session-dbus' "$OPTS"; then
		echo 'use-session-dbus' >> "$OPTS"
		echo ":: enabled use-session-dbus in $OPTS"
	fi
else
	cat > "$OPTS" <<-'EOF'
	allow-failsafe
	allow-user-modmap
	allow-user-resources
	allow-user-xsession
	use-ssh-agent
	use-session-dbus
	EOF
	echo ":: created $OPTS with use-session-dbus"
fi

# --- privileged helpers (root-owned; never elevate user-writable bin/) ---------
# omarchy-dns must re-exec a root-owned path under sudo/pkexec. Elevating the
# copy in ~/.local/share/omarchy/bin would be LPE on this port (no /usr/bin
# package). Keep this in sync when the script changes: re-run setup.sh.
DNS_SRC="$REPO_DIR/home/.local/share/omarchy/bin/omarchy-dns"
DNS_DST=/usr/local/libexec/omarchy/omarchy-dns
if [ -f "$DNS_SRC" ]; then
	install -D -o root -g root -m 0755 "$DNS_SRC" "$DNS_DST"
	echo ":: installed root-owned $DNS_DST"
fi

# --- bundled fonts (JetBrainsMono/Iosevka Nerd, Feather) --------
FONT_SRC="$REPO_DIR/home/.local/share/fonts"
if [ -d "$FONT_SRC" ] && [ "$TARGET_USER" != root ]; then
	FONT_DST="$TARGET_HOME/.local/share/fonts"
	TARGET_GROUP="$(id -gn "$TARGET_USER")"
	install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$FONT_DST"
	cp -r "$FONT_SRC/." "$FONT_DST/"
	chown -R "$TARGET_USER:$TARGET_GROUP" "$FONT_DST"
	sudo -u "$TARGET_USER" fc-cache -f >/dev/null 2>&1 || true
	echo ":: installed bundled fonts into $FONT_DST"
fi

# --- optional: deploy the port ------------------------------------------------
if (( RUN_DEPLOY )); then
	if [ "$TARGET_USER" = root ]; then
		echo "!! --deploy skipped: run ./install.sh && ./deploy.sh as your user, not root" >&2
	else
		echo ":: running install.sh + deploy.sh as $TARGET_USER"
		sudo -u "$TARGET_USER" -H bash -c "cd '$REPO_DIR' && ./install.sh && ./deploy.sh"
	fi
fi

# --- summary ----------------------------------------------------------------
echo "========================================================================"
echo "Done."
if (( ! QUICKSHELL_OK )); then
	echo
	echo "  ! Quickshell is not installed: the bundled package is amd64 only."
	echo "    The bar will not start without it."
fi
if [ "${#MISSING[@]}" -gt 0 ]; then
	echo
	echo "  ! not found in apt, install by hand if you want the feature:"
	printf '      %s\n' "${MISSING[@]}"
fi
if [ "${#UNINSTALLABLE[@]}" -gt 0 ]; then
	echo
	echo "  ! present in apt but not currently installable on this system:"
	printf '      %s\n' "${UNINSTALLABLE[@]}"
	echo "    setup.sh skipped them so the rest of the install could continue."
fi
echo
if (( ! RUN_DEPLOY )); then
	echo "  Next:  cd $REPO_DIR && ./install.sh && ./deploy.sh"
fi
echo "  Then:  start an i3 X session and log in fresh"
echo "         (a full login, not 'i3 restart' — see README)."
echo "========================================================================"

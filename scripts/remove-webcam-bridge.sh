#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Undo scripts/setup-webcam-bridge.sh: stop and remove the user unit, drop the
# v4l2loopback configuration and unload the module.
#
#   sudo ./scripts/remove-webcam-bridge.sh

set -euo pipefail

UNIT_NAME=surface-camera-bridge.service
MODPROBE_CONF=/etc/modprobe.d/surface-camera-bridge.conf
MODULESLOAD_CONF=/etc/modules-load.d/surface-camera-bridge.conf

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"
TARGET_USER=${SUDO_USER:-}
[ -n "$TARGET_USER" ] || die "run this through sudo from your desktop account"
[ "$TARGET_USER" != root ] || die "run as the desktop user, not as root"

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
RUNTIME_DIR=/run/user/$TARGET_UID
UNIT_PATH="$TARGET_HOME/.config/systemd/user/$UNIT_NAME"

as_user() {
	runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$RUNTIME_DIR" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" "$@"
}

if [ -S "$RUNTIME_DIR/bus" ]; then
	if as_user systemctl --user list-unit-files "$UNIT_NAME" >/dev/null 2>&1; then
		info "stopping $UNIT_NAME"
		as_user systemctl --user disable --now "$UNIT_NAME" || true
	fi
fi

if [ -e "$UNIT_PATH" ]; then
	info "removing $UNIT_PATH"
	rm -f "$UNIT_PATH"
	[ -S "$RUNTIME_DIR/bus" ] && as_user systemctl --user daemon-reload || true
fi

for f in "$MODPROBE_CONF" "$MODULESLOAD_CONF"; do
	if [ -e "$f" ]; then
		info "removing $f"
		rm -f "$f"
	fi
done

if lsmod | grep -q '^v4l2loopback'; then
	info "unloading v4l2loopback"
	modprobe -r v4l2loopback || printf 'warning: v4l2loopback is still in use\n' >&2
fi

info "done; the Surface camera bridge has been removed"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Give ordinary applications (Webcamoid, browsers, Cheese, ...) a normal
# webcam backed by the Surface Pro 7 IPU4P cameras.
#
# Why this is needed: the intel_ipu4 stack exposes ~55 raw V4L2 nodes. The
# first ~44 are CSI-2 *packet-dump* nodes and the rest are raw Bayer/Y10
# capture nodes with no ISP. Nothing there is a webcam, so applications either
# show garbage/white or refuse to list the camera at all. libcamera provides
# the software ISP (debayer + auto exposure/white balance); this script wires
# libcamera into a v4l2loopback virtual camera.
#
#   sudo ./scripts/setup-webcam-bridge.sh [options]
#
# Options:
#   --camera NAME    camera to stream: the id in parentheses from `cam -l`
#                    (e.g. \_SB_.PCI0.I2C2.CAMF) or its index (1, 2, ...).
#                    Default: libcamerasrc's first camera.
#   --video-nr N     v4l2loopback video number to claim (default 60)
#   --caps CAPS      output caps (default video/x-raw,format=YUY2,width=1280,height=720)
#   --label LABEL    card label (default "Surface Camera")
#   --autostart      also enable the unit so the camera comes up at login
#                    (default: installed but NOT started or enabled - the
#                    bridge powers the sensor, and therefore the indicator
#                    LED, only while it runs)
#   --help
#
# Note: the camera indicator LED is wired to the sensor power rail, so it stays
# lit while the bridge runs. Control it with scripts/webcam-bridge.sh on|off.
# Remove everything with scripts/remove-webcam-bridge.sh.

set -euo pipefail

LABEL="Surface Camera"
VIDEO_NR=60
CAPS="video/x-raw,format=YUY2,width=1280,height=720"
CAMERA=""
AUTOSTART=0
UNIT_NAME=surface-camera-bridge.service

MODPROBE_CONF=/etc/modprobe.d/surface-camera-bridge.conf
MODULESLOAD_CONF=/etc/modules-load.d/surface-camera-bridge.conf

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

usage() { sed -n '4,30p' "$0" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
	case "$1" in
	--camera) [ "$#" -ge 2 ] || die "--camera needs a value"; CAMERA="$2"; shift 2 ;;
	--video-nr) [ "$#" -ge 2 ] || die "--video-nr needs a value"; VIDEO_NR="$2"; shift 2 ;;
	--caps) [ "$#" -ge 2 ] || die "--caps needs a value"; CAPS="$2"; shift 2 ;;
	--label) [ "$#" -ge 2 ] || die "--label needs a value"; LABEL="$2"; shift 2 ;;
	--autostart) AUTOSTART=1; shift ;;
	--no-enable) AUTOSTART=0; shift ;;	# legacy name; this is now the default
	--help | -h) usage; exit 0 ;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
done

# ---------------------------------------------------------------- preflight --
[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"

TARGET_USER=${SUDO_USER:-}
[ -n "$TARGET_USER" ] || die "run this through sudo from your desktop account"
[ "$TARGET_USER" != root ] || die "run as the desktop user, not as root"

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME" ] || die "cannot resolve home directory of $TARGET_USER"
RUNTIME_DIR=/run/user/$TARGET_UID
[ -S "$RUNTIME_DIR/bus" ] || die "no user session bus at $RUNTIME_DIR/bus; log in as $TARGET_USER and retry"

missing=""
command -v v4l2-ctl >/dev/null 2>&1 || missing="$missing v4l2-utils"
command -v gst-launch-1.0 >/dev/null 2>&1 || missing="$missing gstreamer"
command -v cam >/dev/null 2>&1 || missing="$missing libcamera-tools"
gst-inspect-1.0 libcamerasrc >/dev/null 2>&1 || missing="$missing gst-plugin-libcamera"
gst-inspect-1.0 v4l2sink >/dev/null 2>&1 || missing="$missing gst-plugins-good"
modinfo v4l2loopback >/dev/null 2>&1 || missing="$missing v4l2loopback-dkms"
if [ -n "$missing" ]; then
	die "missing packages:$missing
       install with:  sudo pacman -S$missing"
fi

as_user() {
	runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$RUNTIME_DIR" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" "$@"
}

# --------------------------------------------------------- loopback module --
info "configuring the v4l2loopback module"
cat >"$MODPROBE_CONF" <<EOF
# Managed by surfacepro7-camera-ir scripts/setup-webcam-bridge.sh
# exclusive_caps=1 keeps clients that do not negotiate formats (browsers,
# Webcamoid) happy; video_nr is pinned so the node cannot shadow the ~55 IPU4
# raw nodes or move around between boots.
options v4l2loopback devices=1 video_nr=$VIDEO_NR exclusive_caps=1 card_label="$LABEL"
EOF
printf 'v4l2loopback\n' >"$MODULESLOAD_CONF"

if lsmod | grep -q '^v4l2loopback'; then
	info "reloading v4l2loopback with the new options"
	modprobe -r v4l2loopback || die "v4l2loopback is in use; stop whatever is using it and retry"
fi
modprobe v4l2loopback

DEV=/dev/video$VIDEO_NR
[ -c "$DEV" ] || die "expected $DEV after loading v4l2loopback; check 'dmesg | tail'"
info "virtual camera device: $DEV"

# ------------------------------------------------------------- the camera ---
# libcamerasrc's camera-name matches libcamera's Camera::id(), which on this
# platform is the ACPI path, e.g. \_SB_.PCI0.I2C2.CAMF. `cam -l` prints an
# index, a description, and that id in parentheses; accept either the id or the
# index, and refuse anything else instead of installing a crash-looping unit.
cam_list() {
	as_user cam -l 2>/dev/null | sed -n '/Available cameras/,$p' | grep -E '^[0-9]+:'
}

CAMERA_ID=""
if [ -n "$CAMERA" ]; then
	list=$(cam_list)
	[ -n "$list" ] || die "could not list cameras; is the ISP loaded and libcamera working?"
	CAMERA_ID=$(printf '%s\n' "$list" | sed -n 's/.*(\(.*\))$/\1/p' | grep -Fx "$CAMERA" | head -1)
	if [ -z "$CAMERA_ID" ]; then
		CAMERA_ID=$(printf '%s\n' "$list" | awk -F: -v i="$CAMERA" '$1+0==i+0' |
			sed -n 's/.*(\(.*\))$/\1/p' | head -1)
	fi
	if [ -z "$CAMERA_ID" ]; then
		printf 'error: no camera matches "%s"\n\navailable cameras:\n%s\n\n' "$CAMERA" "$list" >&2
		printf 'pass the id in parentheses, or the index shown by cam -l\n' >&2
		exit 1
	fi
	info "camera: $CAMERA_ID"
else
	info "camera: default (libcamerasrc picks its first camera; use --camera to choose)"
fi

# ---------------------------------------------------------------- the unit --
# The pipeline lives in a wrapper script rather than in ExecStart: systemd
# unescapes backslashes in ExecStart, which would eat the leading '\' of the
# ACPI camera id and make libcamera reject the name.
BIN_DIR="$TARGET_HOME/.local/bin"
RUNNER="$BIN_DIR/surface-camera-bridge-run"
install -d -o "$TARGET_UID" -g "$TARGET_GID" "$BIN_DIR"

cat >"$RUNNER" <<EOF
#!/bin/sh
# Generated by surfacepro7-camera-ir scripts/setup-webcam-bridge.sh
CAMERA_NAME='$CAMERA_ID'
DEV='$DEV'
set -- -e libcamerasrc
[ -n "\$CAMERA_NAME" ] && set -- "\$@" "camera-name=\$CAMERA_NAME"
exec gst-launch-1.0 "\$@" ! queue ! videoconvert ! videoscale \\
	! $CAPS ! v4l2sink device="\$DEV" sync=false
EOF
chown "$TARGET_UID:$TARGET_GID" "$RUNNER"
chmod 755 "$RUNNER"

UNIT_DIR="$TARGET_HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"
install -d -o "$TARGET_UID" -g "$TARGET_GID" "$UNIT_DIR"

cat >"$UNIT_PATH" <<EOF
[Unit]
Description=Surface Pro 7 camera bridge (libcamera -> v4l2loopback)
After=graphical-session.target

[Service]
Type=simple
ExecStart=$RUNNER
Restart=always
RestartSec=2
Nice=5

[Install]
WantedBy=default.target
EOF
chown "$TARGET_UID:$TARGET_GID" "$UNIT_PATH"
info "installed $UNIT_PATH"

# Never leave the unit enabled unless the user asked for it: a v4l2loopback
# bridge streams continuously, which keeps the sensor powered and the camera
# indicator LED lit the whole time.
as_user systemctl --user disable "$UNIT_NAME" >/dev/null 2>&1 || true
as_user systemctl --user daemon-reload

if [ "$AUTOSTART" = 1 ]; then
	as_user systemctl --user enable --now "$UNIT_NAME"
	sleep 5
	if as_user systemctl --user is-active --quiet "$UNIT_NAME"; then
		info "bridge is running and will start at login"
	else
		printf '%s\n' "warning: $UNIT_NAME is not active; recent log:" >&2
		as_user journalctl --user -u "$UNIT_NAME" -n 20 --no-pager >&2 || true
	fi
else
	info "unit installed but NOT enabled: the camera stays off (LED dark) until you start it"
fi

# ---------------------------------------------------------------- verify ----
if [ -c "$DEV" ]; then
	printf '\n'
	v4l2-ctl -d "$DEV" --get-fmt-video 2>/dev/null | sed -n '1,5p' || true
	printf '\n'
	info "applications should now see \"$LABEL\" as $DEV"
	printf '    check:  v4l2-ctl --list-devices\n'
	printf '    test :  gst-launch-1.0 v4l2src device=%s ! videoconvert ! autovideosink\n' "$DEV"
	printf '    on/off: %s/scripts/webcam-bridge.sh on|off|status\n' "$(dirname "$0")"
fi

if [ "$AUTOSTART" != 1 ]; then
	printf '\n'
	info "start it now with:  %s/scripts/webcam-bridge.sh on" "$(dirname "$0")"
fi

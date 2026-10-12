#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Turn the Surface camera bridge on or off.
#
#   ./scripts/webcam-bridge.sh on | off | status
#
# The camera indicator LED is wired to the sensor power rail in hardware, so it
# stays lit for as long as the bridge runs - the bridge has to keep the real
# sensor streaming for the virtual camera to have frames. That is a privacy
# feature, not a bug: software cannot stream and keep the LED dark. Use
# "off" whenever you do not need the camera.
#
# No root required - this is a systemd user unit.

set -euo pipefail

UNIT=surface-camera-bridge.service
DEV="${DEV:-/dev/video60}"

usage() { sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-status}" in
on)
	systemctl --user start "$UNIT"
	sleep 2
	if systemctl --user is-active --quiet "$UNIT"; then
		echo "bridge running; $DEV is live and the camera LED is on"
	else
		echo "bridge failed to start; log:" >&2
		systemctl --user --no-pager -n 20 status "$UNIT" >&2 || true
		exit 1
	fi
	;;
off)
	systemctl --user stop "$UNIT"
	echo "bridge stopped; camera LED should be off"
	;;
status)
	if systemctl --user is-active --quiet "$UNIT"; then
		echo "running - $DEV is live, camera LED is on"
	else
		echo "stopped - camera LED is off, apps will not see a camera"
	fi
	;;
-h | --help | help)
	usage
	;;
*)
	echo "usage: $0 [on|off|status]" >&2
	exit 2
	;;
esac

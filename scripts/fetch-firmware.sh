#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Install ipu4p_cpd.bin, the Microsoft-signed CPD firmware the IPU4P ISP needs
# to boot. The firmware is proprietary and is deliberately NOT part of this
# package: this script only helps you obtain it from Microsoft's own Surface
# Pro 7 driver package and place it in /lib/firmware/.
#
#   sudo ./scripts/fetch-firmware.sh
#   sudo ./scripts/fetch-firmware.sh --workdir /data/sp7-fw
#   sudo FIRMWARE=/path/to/cpd_component_signed.bin ./scripts/fetch-firmware.sh
#
# The driver package is ~678 MB and unpacking needs a few GB, so the script
# chooses a work directory that actually has room instead of blindly using
# /tmp, which is very often a small RAM-backed tmpfs.
#
# Mirrors the procedure used by the upstream Surface Pro 7 IPU4 stack
# (ruslanbay/sp7-ipu4-camera install.sh). The download/extraction path could
# not be exercised in this repository's development environment (no msitools,
# no root, /tmp too small), so treat it as a convenience wrapper around those
# documented commands.

set -euo pipefail

MSI_URL="https://download.microsoft.com/download/b7ea0d32-93fb-4733-b78c-4263b314dbf4/SurfacePro7_Win11_22621_25.090.3489.0.msi"
DEST="${DEST:-/lib/firmware/ipu4p_cpd.bin}"
WORKDIR="${WORKDIR:-}"
FIRMWARE_SRC="${FIRMWARE:-}"
MIN_FREE_MB="${MIN_FREE_MB:-4096}"
KEEP="${KEEP:-0}"

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
usage: fetch-firmware.sh [options]

  -w, --workdir DIR   download/unpack here (default: first candidate with
                      enough free space; /tmp is skipped when it is too small)
  -d, --dest FILE     install the firmware here
                      (default /lib/firmware/ipu4p_cpd.bin)
  -k, --keep          keep the downloaded .msi and the extracted files
  -h, --help          show this help

environment:
  FIRMWARE=/path/to/cpd_component_signed.bin  use an existing file
  MIN_FREE_MB=4096                            required free space in MiB
  DEST, WORKDIR, KEEP                         same as the options above
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	-w | --workdir)
		[ "$#" -ge 2 ] || die "--workdir needs a directory"
		WORKDIR="$2"
		shift 2
		;;
	-d | --dest)
		[ "$#" -ge 2 ] || die "--dest needs a file"
		DEST="$2"
		shift 2
		;;
	-k | --keep)
		KEEP=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1 (try --help)"
		;;
	esac
done

# Free space in MiB on the filesystem holding $1; walks up to an existing dir.
avail_mb() {
	local d="$1" out=""

	while [ ! -d "$d" ] && [ "$d" != "/" ]; do
		d="$(dirname "$d")"
	done

	# Must not trip `set -e`/`pipefail` when df cannot inspect the path.
	out="$(df -Pk "$d" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }')" || true

	printf '%s\n' "$out"
	return 0
}

candidates() {
	local home=""

	if [ -n "${SUDO_USER:-}" ]; then
		home="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
	fi
	if [ -n "$home" ]; then
		printf '%s\n' "$home/.cache/sp7-cpd-firmware"
	fi

	printf '%s\n' "/var/tmp/sp7-cpd-firmware"

	if [ -n "${TMPDIR:-}" ]; then
		printf '%s\n' "${TMPDIR}/sp7-cpd-firmware"
	fi

	printf '%s\n' "/tmp/sp7-cpd-firmware"

	return 0
}

pick_workdir() {
	local best="" best_mb=-1 dir mb

	if [ -n "$WORKDIR" ]; then
		mb="$(avail_mb "$WORKDIR")"
		if [ -z "$mb" ] || [ "$mb" -lt "$MIN_FREE_MB" ]; then
			die "$WORKDIR has ${mb:-?} MiB free, need ${MIN_FREE_MB} MiB; pick a bigger filesystem with --workdir"
		fi
		printf '%s\n' "$WORKDIR"
		return 0
	fi

	while IFS= read -r dir; do
		[ -n "$dir" ] || continue
		mb="$(avail_mb "$dir")"
		[ -n "$mb" ] || continue
		if [ "$mb" -ge "$MIN_FREE_MB" ]; then
			printf '%s\n' "$dir"
			return 0
		fi
		if [ "$mb" -gt "$best_mb" ]; then
			best="$dir"
			best_mb="$mb"
		fi
	done < <(candidates)

	die "no candidate work directory has ${MIN_FREE_MB} MiB free (largest: ${best:-none}, ${best_mb} MiB); free space, lower MIN_FREE_MB, or pass --workdir /path/with/space"
}

install_firmware() {
	local src="$1" destdir size

	[ -s "$src" ] || die "firmware file is missing or empty: $src"

	destdir="$(dirname "$DEST")"
	mkdir -p "$destdir" 2>/dev/null ||
		die "cannot create $destdir; re-run with sudo"
	[ -w "$destdir" ] ||
		die "cannot write to $destdir; re-run with sudo"

	install -m 644 "$src" "$DEST"
	size="$(stat -c '%s' "$DEST")"
	printf 'installed %s (%s bytes)\n' "$DEST" "$size"
	printf 'now reload the driver:  sudo modprobe intel_ipu4\n'
}

if [ -n "$FIRMWARE_SRC" ]; then
	install_firmware "$FIRMWARE_SRC"
	exit 0
fi

if [ -s "$DEST" ]; then
	printf 'already installed: %s (%s bytes)\n' "$DEST" "$(stat -c '%s' "$DEST")"
	exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v msiextract >/dev/null 2>&1 || die \
	"msiextract is required to unpack Microsoft's .msi (install 'msitools'), or pass FIRMWARE=/path/to/cpd_component_signed.bin"

work="$(pick_workdir)"
mkdir -p "$work"

mb="$(avail_mb "$work")"
if [ -z "$mb" ] || [ "$mb" -lt "$MIN_FREE_MB" ]; then
	die "$work has ${mb:-?} MiB free, need ${MIN_FREE_MB} MiB (override with MIN_FREE_MB=...)"
fi

msi="$work/$(basename "$MSI_URL")"
extract="$work/extract"

printf 'work directory : %s (%s MiB free)\n' "$work" "$mb"
printf 'Downloading Microsoft Surface Pro 7 driver package (~678 MB)...\n'
curl -fL --retry 3 "$MSI_URL" -o "$msi"

printf 'Extracting...\n'
rm -rf "$extract"
mkdir -p "$extract"
msiextract -C "$extract" "$msi" >/dev/null

mapfile -t found < <(find "$extract" -type f -name cpd_component_signed.bin)
[ "${#found[@]}" -eq 1 ] || die \
	"expected exactly one cpd_component_signed.bin in the package, found ${#found[@]}"

install_firmware "${found[0]}"

if [ "$KEEP" = "1" ]; then
	printf 'kept work directory: %s\n' "$work"
else
	rm -rf "$extract" "$msi"
	rmdir "$work" 2>/dev/null || true
	printf 'cleaned up %s\n' "$work"
fi

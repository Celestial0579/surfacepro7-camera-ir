#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Verification for the surfacepro7-camera-ir packages.
#
#   ./scripts/verify.sh [kernel-release]
#   ./scripts/verify.sh --simd-only
#
# Checks, without needing root:
#   1. both .pkg.tar.zst archives exist;
#   2. pacman -Qip accepts them (valid .PKGINFO);
#   3. .MTREE and .PKGINFO are present in the archives;
#   4. the module payload is complete (9 modules) and installs below
#      usr/lib/modules/<release>/extra/surfacepro7-camera-ir/;
#   5. every module carries a matching vermagic;
#   6. the v4 build contains no unprotected SIMD/FPU instructions.

set -uo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

simd_only=0
[ "${1:-}" = "--simd-only" ] && simd_only=1

PKG_A="surfacepro7-camera-ir-ipu4-ov5693-ov8865-ov7251-7x-1-1-x86_64.pkg.tar.zst"
PKG_B="surfacepro7-camera-ir-ipu4-ov5693-ov8865-ov7251-7x-v4-1-1-x86_64.pkg.tar.zst"

MODULES=(
	intel-ipu4.ko
	intel-ipu4-isys.ko
	intel-ipu4-psys.ko
	intel-ipu4-isys-csslib.ko
	intel-ipu4-psys-csslib.ko
	ov5693.ko
	ov8865.ko
	ov7251.ko
	surfacepro7_acpi.ko
)

fail=0
ok()   { printf '  [ OK ] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; fail=1; }
skip() { printf '  [skip] %s\n' "$*"; }

check_simd() {
	local pkg="$1" tmp ko hits
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN

	if ! bsdtar -xf "$pkg" -C "$tmp" 2>/dev/null; then
		bad "$pkg: extraction failed"
		return
	fi

	hits=0
	while IFS= read -r ko; do
		if objdump -d "$ko" 2>/dev/null |
			grep -qE '%(xmm|ymm|zmm)[0-9]+'; then
			bad "$(basename "$ko"): SIMD/FPU register use detected"
			objdump -d "$ko" |
				grep -oE '^[[:space:]]*[0-9a-f]+:.*%(xmm|ymm|zmm)[0-9]+' |
				head -5
			hits=1
		fi
	done < <(find "$tmp" -name '*.ko')

	[ "$hits" -eq 0 ] && ok "$pkg: no xmm/ymm/zmm register use in any module"

	if objdump -d "$tmp"/usr/lib/modules/*/extra/surfacepro7-camera-ir/*.ko 2>/dev/null |
		grep -qE '\b(vmovdqa|vmovdqu|vpxor|vzeroupper|movaps|movups|pxor|addps|mulps)\b'; then
		bad "$pkg: SSE/AVX mnemonics present"
	else
		ok "$pkg: no SSE/AVX/AVX-512 mnemonics"
	fi
}

check_simd_of_build() {
	# The already-built tree (used by build-v4.sh right after makepkg).
	local hits=0 ko
	while IFS= read -r ko; do
		if objdump -d "$ko" 2>/dev/null |
			grep -qE '%(xmm|ymm|zmm)[0-9]+'; then
			bad "built $(basename "$ko"): SIMD/FPU register use detected"
			hits=1
		fi
	done < <(find "$here" -name '*.ko')
	[ "$hits" -eq 0 ] && ok "built tree: no xmm/ymm/zmm register use in any module"
}

if [ "$simd_only" -eq 1 ]; then
	if [ -f "$PKG_B" ]; then
		check_simd "$PKG_B"
	else
		check_simd_of_build
	fi
	exit "$fail"
fi

echo "== verify: surfacepro7-camera-ir =="
echo "kernel: ${KERNEL_VERSION:-$(uname -r)}"
echo

echo "-- 1. archives --"
for p in "$PKG_A" "$PKG_B"; do
	if [ -f "$p" ]; then
		ok "$p ($(du -h "$p" | cut -f1))"
	else
		bad "$p missing"
	fi
done

echo
echo "-- 2. pacman -Qip --"
for p in "$PKG_A" "$PKG_B"; do
	[ -f "$p" ] || { bad "$p missing"; continue; }
	if out="$(pacman -Qip "$p" 2>&1)"; then
		ok "$p recognised"
		printf '%s\n' "$out" | grep -E '^(Name|Version|Architecture|Depends|Conflicts|Provides|Install Script)' |
			sed 's/^/        /'
	else
		bad "$p not recognised: $out"
	fi
done

echo
echo "-- 3. archive metadata --"
for p in "$PKG_A" "$PKG_B"; do
	[ -f "$p" ] || continue
	for m in .PKGINFO .MTREE; do
		if bsdtar -tf "$p" 2>/dev/null | grep -qx "$m"; then
			ok "$p: $m present"
		else
			bad "$p: $m missing"
		fi
	done
done

echo
echo "-- 4. module payload and install path --"
for p in "$PKG_A" "$PKG_B"; do
	[ -f "$p" ] || continue
	list="$(bsdtar -tf "$p" 2>/dev/null)"
	for m in "${MODULES[@]}"; do
		if printf '%s\n' "$list" |
			grep -qE "usr/lib/modules/[^/]+/extra/surfacepro7-camera-ir/$m$"; then
			ok "$p: $m"
		else
			bad "$p: $m missing or installed outside extra/surfacepro7-camera-ir/"
		fi
	done
	n=$(printf '%s\n' "$list" | grep -c 'extra/surfacepro7-camera-ir/.*\.ko$')
	[ "$n" -eq "${#MODULES[@]}" ] &&
		ok "$p: exactly ${#MODULES[@]} modules installed" ||
		bad "$p: expected ${#MODULES[@]} modules, found $n"
done

echo
echo "-- 5. vermagic --"
for p in "$PKG_A" "$PKG_B"; do
	[ -f "$p" ] || continue
	tmp="$(mktemp -d)"
	bsdtar -xf "$p" -C "$tmp" 2>/dev/null
	bad_v=0
	while IFS= read -r ko; do
		vm="$(modinfo -F vermagic "$ko" 2>/dev/null | awk '{print $1}')"
		case "$vm" in
		7.*|6.*) ;;
		*) bad_v=1; bad "$(basename "$ko"): unexpected vermagic '$vm'" ;;
		esac
	done < <(find "$tmp" -name '*.ko')
	[ "$bad_v" -eq 0 ] && ok "$p: all modules carry a kernel vermagic"
	rm -rf "$tmp"
done

echo
echo "-- 6. v4 SIMD/FPU safety --"
if [ -f "$PKG_B" ]; then
	check_simd "$PKG_B"
else
	skip "$PKG_B not built yet"
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "RESULT: PASS"
else
	echo "RESULT: FAIL"
fi
exit "$fail"

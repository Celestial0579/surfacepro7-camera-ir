#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build package B (x86-64-v4 optimised build) and place the .pkg.tar.zst next
# to PKGBUILD.v4.
#
#   ./scripts/build-v4.sh [kernel-release]
#
# The kernel release defaults to the running kernel, or to $KERNEL_VERSION.

set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

export KERNEL_VERSION="${1:-${KERNEL_VERSION:-$(uname -r)}}"

echo "==> building package B (x86-64-v4) for kernel ${KERNEL_VERSION}"
echo "    kernel build tree: /lib/modules/${KERNEL_VERSION}/build"

if [ ! -d "/lib/modules/${KERNEL_VERSION}/build" ]; then
	echo "error: /lib/modules/${KERNEL_VERSION}/build not found" >&2
	echo "       install the matching kernel headers, or pass the right kernel release" >&2
	exit 1
fi

if ! echo 'int main(void){return 0;}' |
	gcc -march=x86-64-v4 -x c - -o /dev/null 2>/dev/null; then
	echo "error: the toolchain does not support -march=x86-64-v4" >&2
	exit 1
fi

# BUILDDIR: keep makepkg's $srcdir away from this project's src/ directory
# (see scripts/build-basic.sh for the full explanation).
makepkg -p PKGBUILD.v4 -f --noconfirm --nodeps \
	BUILDDIR="${BUILDDIR:-${TMPDIR:-/tmp}/makepkg-surfacepro7-camera-ir-v4}"

echo
echo "==> produced:"
ls -l ./*.pkg.tar.zst 2>/dev/null || true
echo
echo "==> verifying that no unprotected SIMD/FPU instructions were emitted"
"$here/scripts/verify.sh" --simd-only

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build package A (basic x86-64 build) and place the .pkg.tar.zst next to the
# PKGBUILD.
#
#   ./scripts/build-basic.sh [kernel-release]
#
# The kernel release defaults to the running kernel, or to $KERNEL_VERSION.

set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

export KERNEL_VERSION="${1:-${KERNEL_VERSION:-$(uname -r)}}"

echo "==> building package A (basic) for kernel ${KERNEL_VERSION}"
echo "    kernel build tree: /lib/modules/${KERNEL_VERSION}/build"

if [ ! -d "/lib/modules/${KERNEL_VERSION}/build" ]; then
	echo "error: /lib/modules/${KERNEL_VERSION}/build not found" >&2
	echo "       install the matching kernel headers, or pass the right kernel release" >&2
	exit 1
fi

# BUILDDIR: makepkg defaults BUILDDIR to $startdir, which makes its own
# $srcdir resolve to this project's src/ directory - the driver sources!
# Pointing BUILDDIR elsewhere guarantees makepkg never touches src/.
#
# --nodeps: the metadata dependency is the 'linux' package; on derivative
# kernels (linux-surface / linux-cachyos-surface) that name is not installed,
# and makepkg must not try to install it as an unprivileged user.
makepkg -p PKGBUILD -f --noconfirm --nodeps \
	BUILDDIR="${BUILDDIR:-${TMPDIR:-/tmp}/makepkg-surfacepro7-camera-ir-basic}"

echo
echo "==> produced:"
ls -l ./*.pkg.tar.zst 2>/dev/null || true

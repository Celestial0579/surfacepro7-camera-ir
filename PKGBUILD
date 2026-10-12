# Maintainer: surfacepro7-camera-ir
#
# Package A - basic x86-64 build.
#
# Surface Pro 7 (Intel Ice Lake, IPU4P 8086:8a19) camera stack:
#   intel_ipu4 / intel_ipu4_isys / intel_ipu4_psys / *_csslib  (IPU4 core,
#       ISYS, PSYS, MMU, CSI2, media controller, async notifier, runtime PM)
#   ov5693 (front), ov8865 (rear), ov7251 (IR, Y10 + exposure/gain + STROBE)
#   surfacepro7_acpi (ACPI power resources / INT3472 topology glue)
#
# The package is kernel specific: modules are built against the running
# kernel's build tree and installed below that kernel's extra/ directory.

pkgname=surfacepro7-camera-ir-ipu4-ov5693-ov8865-ov7251-7x
pkgver=1
pkgrel=1
pkgdesc="Surface Pro 7 IPU4/IPU4P camera + IR drivers (intel_ipu4 core/ISYS/PSYS/MMU/CSI2, ov5693, ov8865, ov7251 IR, SP7 ACPI glue) - basic x86-64 build"
arch=('x86_64')
url="https://github.com/linux-surface/linux-surface"
license=('GPL-2.0-only')
depends=('linux')
optdepends=('v4l-utils: 测试工具 (v4l2-ctl / media-ctl)')
conflicts=('surfacepro7-camera-ir-ipu4-ov5693-ov8865-ov7251-7x-v4')
provides=('surfacepro7-camera-ir')
# Kernel modules must never be stripped nor LTO'd.
options=('!strip' '!debug' '!lto')
install=surfacepro7-camera-ir.install

_kernelver="${KERNEL_VERSION:-$(uname -r)}"
_moddir="usr/lib/modules/${_kernelver}/extra/surfacepro7-camera-ir"
_kcflags="-O2 -march=x86-64 -mtune=generic -fno-strict-aliasing"

build() {
	cd "$startdir"
	make clean KERNEL_VERSION="$_kernelver" >/dev/null 2>&1 || true
	make modules -j"$(nproc)" KERNEL_VERSION="$_kernelver" KCFLAGS="$_kcflags"
}

package() {
	cd "$startdir"

	install -d "$pkgdir/$_moddir"
	find . -name '*.ko' -exec install -m 644 {} "$pkgdir/$_moddir/" \;

	install -d "$pkgdir/usr/share/doc/$pkgname"
	install -m 644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
	install -m 644 PKGBUILD "$pkgdir/usr/share/doc/$pkgname/PKGBUILD"
	install -m 644 dkms.conf "$pkgdir/usr/share/doc/$pkgname/dkms.conf" 2>/dev/null || true
	if [ -d patches ]; then
		install -d "$pkgdir/usr/share/doc/$pkgname/patches"
		install -m 644 patches/*.patch "$pkgdir/usr/share/doc/$pkgname/patches/"
	fi
}

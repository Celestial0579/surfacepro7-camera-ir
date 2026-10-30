#!/bin/sh
# Build surfacepro7-camera_<version>_all.deb
#   packaging/build-deb.sh [VERSION]
# Driver source: branch sp7-package of ../surfacepro7-camera-ir (all fixes).
set -eu

VERSION=${1:-0.1.0}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$HERE/..
OUT=$HERE/../dist
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# 1. Files from the tested tree
cp -a "$HERE/root/." "$STAGE/"

# 2. DKMS source from the package branch, versioned like the package
SRC=$STAGE/usr/src/surfacepro7-camera-ir-$VERSION
mkdir -p "$SRC"
git -C "$REPO" archive sp7-package | tar -x -C "$SRC"
sed -i "s/^PACKAGE_VERSION=.*/PACKAGE_VERSION=\"$VERSION\"/" "$SRC/dkms.conf"
rm -rf "$SRC/PKGBUILD" "$SRC/PKGBUILD.v4" "$SRC/surfacepro7-camera-ir.install" "$SRC/.gitignore" "$SRC/ubuntu-package"

# 3. Debian metadata
mkdir -p "$STAGE/DEBIAN"
for f in control postinst prerm postrm; do
	sed "s/@VERSION@/$VERSION/g" "$HERE/DEBIAN/$f" > "$STAGE/DEBIAN/$f"
done
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm" "$STAGE/DEBIAN/postrm"
echo /etc/libcamera/ipa/simple/ov8865.yaml > "$STAGE/DEBIAN/conffiles"
cp "$HERE/copyright" "$STAGE/usr/share/doc/surfacepro7-camera/copyright"
sed "s/@VERSION@/$VERSION/g; s/@DATE@/$(date -R)/" "$HERE/changelog" | gzip -9n > "$STAGE/usr/share/doc/surfacepro7-camera/changelog.gz"

# 4. Permissions and checksums
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f ! -perm -u+x -exec chmod 644 {} +
find "$STAGE" -type f -perm -u+x -exec chmod 755 {} +
(cd "$STAGE" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' | xargs -0 md5sum > DEBIAN/md5sums)
sed -i "/^Description:/i Installed-Size: $(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)" "$STAGE/DEBIAN/control"

mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$OUT/surfacepro7-camera_${VERSION}_all.deb"

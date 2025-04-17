#!/bin/sh

VERSION=1.0.0

OS="$(uname)"
ARCH="$(uname -m)"
TARGET="$OS-$ARCH"

PKG_ROOT="$PWD"
BUILD_ROOT=$(realpath "../../")
PKG_NAME="bemgr-$VERSION-$TARGET"
TARBALL="$PKG_NAME.tar.xz"
PKG_DIR="$PKG_ROOT/$PKG_NAME"

if [ -d "$PKG_DIR" ]
then
    echo rm -rf "$PKG_DIR"
    rm -rf "$PKG_DIR"
fi

if [ -e "$TARBALL" ]
then
    echo rm "$TARBALL"
    rm "$TARBALL"
fi

echo mkdir "$PKG_DIR"
mkdir "$PKG_DIR"

echo cp -r files/* "$PKG_DIR"
cp -r files/* "$PKG_DIR"

echo cp "$BUILD_ROOT/LICENSE_1_0.txt" "$PKG_DIR"
cp "$BUILD_ROOT/LICENSE_1_0.txt" "$PKG_DIR"

echo cd "$BUILD_ROOT"
cd "$BUILD_ROOT"
echo ""

echo ./install.sh "$PKG_DIR"
./install.sh "$PKG_DIR"
echo ""

echo cd "$PKG_ROOT"
cd "$PKG_ROOT"
echo ""

echo tar Jcvf "$TARBALL" "$PKG_NAME"
tar Jcvf "$TARBALL" "$PKG_NAME"
echo ""

echo rm -rf "$PKG_NAME"
rm -rf "$PKG_NAME"
echo ""

echo sha256sum "$TARBALL"
sha256sum "$TARBALL"

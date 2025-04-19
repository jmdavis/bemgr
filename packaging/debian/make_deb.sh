#!/bin/sh

#https://wiki.debian.org/Packaging/Intro
#https://www.debian.org/doc/manuals/maint-guide/dreq.en.html

VERSION=1.0.1

TARBALL="bemgr_${VERSION}.orig.tar.gz"
UNTARRED="bemgr-${VERSION}"

wget "https://github.com/jmdavis/bemgr/archive/refs/tags/v${VERSION}.tar.gz" || exit 1
mv "v${VERSION}.tar.gz" "${TARBALL}"  || exit 1
tar xvf "${TARBALL}"

DATE=$(date '+%a, %d %b %Y %T %z')

echo "bemgr (${VERSION}-1) UNRELEASED; urgency=low" > debian/changelog
echo "" >> debian/changelog
echo "  * Initial release." >> debian/changelog
echo "" >> debian/changelog
echo " -- Jonathan M Davis <jmdavis@jmdavisprog.com>  ${DATE}" >> debian/changelog

cp -a debian "${UNTARRED}" || exit 1
cd "${UNTARRED}" || exit 1
debuild -us -uc

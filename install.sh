#!/bin/sh

if [ "$#" -ne 1 ]
then
    echo "./install.sh <INSTALL PREFIX>"
    exit 1
fi

PREFIX=$1

if [ ! -d "$PREFIX" ]
then
    echo "$PREFIX does not exist"
    exit 1
fi

if [ -w $PREFIX ]
then
    SUDO=""
else
    SUDO="sudo "
fi

echo dub clean
dub clean
echo ""

if which ldc2 > /dev/null
then
    echo dub build --build=release --compiler=ldc2
    dub build --build=release --compiler=ldc2 || exit 1
else
    echo dub build --build=release --compiler=dmd
    dub build --build=release --compiler=dmd || exit 1
fi
echo ""

echo ${SUDO}mkdir -p "$PREFIX/sbin"
${SUDO}mkdir -p "$PREFIX/sbin" || exit 1

echo ${SUDO}cp bemgr "$PREFIX/sbin/"
${SUDO}cp bemgr "$PREFIX/sbin/" || exit 1

echo gzip -k bemgr.8
gzip -k bemgr.8 || exit 1

echo ${SUDO}mkdir -p "$PREFIX/share/man/man8/"
${SUDO}mkdir -p "$PREFIX/share/man/man8/" || exit 1

echo ${SUDO}cp bemgr.8.gz "$PREFIX/share/man/man8/"
${SUDO}cp bemgr.8.gz "$PREFIX/share/man/man8/" || exit 1

echo rm bemgr.8.gz
rm bemgr.8.gz

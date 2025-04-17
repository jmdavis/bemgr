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

echo ${SUDO}mkdir -p "$PREFIX/sbin"
${SUDO}mkdir -p "$PREFIX/sbin" || exit 1

echo ${SUDO}cp sbin/bemgr "$PREFIX/sbin/"
${SUDO}cp sbin/bemgr "$PREFIX/sbin/" || exit 1

echo ${SUDO}mkdir -p "$PREFIX/share/man/man8/"
${SUDO}mkdir -p "$PREFIX/share/man/man8/" || exit 1

echo ${SUDO}cp share/man/man8/bemgr.8.gz "$PREFIX/share/man/man8/"
${SUDO}cp share/man/man8/bemgr.8.gz "$PREFIX/share/man/man8/" || exit 1

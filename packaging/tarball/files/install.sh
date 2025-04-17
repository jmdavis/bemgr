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

echo ${SUDO}cp -Rv sbin $PREFIX/
${SUDO}cp -Rv sbin $PREFIX/
echo ""

echo ${SUDO}cp -Rv share $PREFIX/
${SUDO}cp -Rv share $PREFIX/

#!/bin/sh

echo Clean build...
dub clean

echo Build release build...
if which ldc2 > /dev/null
then
    dub build --build=release --compiler=ldc2 || exit 1
else
    dub build --build=release --compiler=dmd || exit 1
fi

echo sudo cp bemgr /usr/local/sbin/
sudo cp bemgr /usr/local/sbin/

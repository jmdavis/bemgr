#!/bin/sh

echo dub clean
dub clean

if which ldc2 > /dev/null
then
    echo dub build --build=release --compiler=ldc2
    dub build --build=release --compiler=ldc2 || exit 1
else
    echo dub build --build=release --compiler=dmd
    dub build --build=release --compiler=dmd || exit 1
fi

echo sudo cp bemgr /usr/local/sbin/
sudo cp bemgr /usr/local/sbin/

echo sudo mkdir -p /usr/local/share/man/man8
sudo mkdir -p /usr/local/share/man/man8

echo gzip -k bemgr.8
gzip -k bemgr.8

echo sudo mv bemgr.8.gz /usr/local/share/man/man8/
sudo mv bemgr.8.gz /usr/local/share/man/man8/

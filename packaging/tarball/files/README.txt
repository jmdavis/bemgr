This directory from a tarball including a built version of bemgr.

See https://github.com/jmdavis/bemgr or read the man page for more information
on bemgr.

To install the files onto your system, you can run

    ./install.sh <prefix>

e.g. if you wanted to install the files in /usr/local, then you'd run

    ./install.sh /usr/local

It will copy the files with sudo if the user doesn't have permission to write
to the prefix; otherwise, it will copy without sudo.

Or if you don't want to install the files, you can just add the sbin in this
directory to your PATH to be able to run bemgr without installing it (though
that won't install the man page either).

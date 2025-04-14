# The Build Tools

`bemgr` is written in [D](https://dlang.org), so it requires a D compiler. In
general, it's recommended to build with `ldc` (which uses llvm) rather than
`dmd` (which is the reference compiler), because `ldc` optimizes better, though
enough of what `bemgr` is doing involves triggering zfs shell commands that the
performance difference isn't large. `gdc` should work as well, but it's usually
slower in getting updates.

On FreeBSD, it is recommended that the compiler be `dmd` version 2.111.0 or
later (or a version of `ldc` or `gdc` which is based on `dmd` version 2.111.0
or later), since there was a change in 2.111.0 which significantly affected the
performance of triggering shell commands from D (e.g. `bemgr list` could take
around 0.5 seconds with 2.110.0 but more like 0.04 seconds with 2.111.0). Linux
appears to not have the same problem for whatever reason, so 2.110.0 performs
similarly to 2.111.0 on Linux. Of course, if you're reading this more than a
few months after this was written, you'll probably have a newer version anyway.

See [https://dlang.org/download.html](https://dlang.org/download.html) to
download a D compiler, or install a package such as `dmd` or `ldc` using your
system's package manager.

`dub` (D's official package manager and build tool) is required and comes with
`dmd`. It may also come with `ldc` depending on how `ldc` is installed.

# Building bemgr

To do a release build of `bemgr` with the default compiler, run

`dub build --build=release`

The default compiler will probably be `dmd`, but it could also be `ldc`
depending on how you installed `dub`.

To build with ldc specifically, run

`dub build --build=release --compiler=ldc2`

Alternatively, the `install.sh` script can be used. It will do a clean build
with `ldc` if it's installed and `dmd` otherwise, and then it will copy `bemgr`
to `/usr/local/sbin` and its man page to `/usr/local/share/man/man8`.

# Testing

If you're interested in making changes to `bemgr` and testing them, `dub test`
will build and run the unit tests with the default compiler (and since `dmd`
builds faster than `ldc`, there isn't much reason to use `ldc` if you're just
testing the code). The unit tests are pretty minimal, since most of the useful
testing requires running `bemgr` rather than testing its internals, but there
are some unit tests for the internals.

[integration\_tests/README.md](integration\_tests/README.md) contains
information on running the integration tests, which involves running `bemgr` in
a VM to make sure that it's behaving properly (and you wouldn't want to test it
on an actual system, since if you're making changes, and they're wrong, you
could screw up your system).

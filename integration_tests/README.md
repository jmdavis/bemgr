Do _not_ run these tests on a system that you actually care about. They assume
that they can do whatever they need to with the boot pool to test `bemgr`'s
functionality.

The tests are designed to be run in a VM with a pool named `zroot`. The parent
dataset of the boot environments is expected to be `ROOT`, and when the tests
are run, the only BE that should exist is `zroot/ROOT/default` (and of course,
it has to be the active BE). It must also have no snapshots. The tests will
check for these conditions and attempt to catch it if you run them on a real
system, but ultimately, it's up to you to not run them on a real system.

In addition, no snapshotting tool such as `zfs-auto-snapshot` should be
running, since it could create additional snapshots while the tests are running
and screw up the results.

Since which other datasets exist depends on the exact OS setup (and could
differ between FreeBSD and Linux), those can exist and shouldn't be messed with
by the tests - though of course, that assumes that `bemgr` doesn't have bugs, and
the whole point of these tests is to check that `bemgr` doesn't have bugs by
testing a bunch of stuff in an environment where it's not a problem if the
current setup gets destroyed if things go wrong.

The tests create a variety of combinations of datasets, snapshots, and clones
and run the various `bemgr` commands on the pool to ensure that each of the
commands functions properly. Many of the combinations are combinations that
should not happen in practice (e.g. a boot environment with child datasets or
snapshots which have the exact same creation time). Not only is `bemgr` tested
with the datasets and snapshots having been created purely with `bemgr`, but
some of the combinations include messing with the pool with direct zfs commands
to create bad scenarios to make sure that `bemgr` handles them sanely.

And of course, since tests can fail if the code is wrong, and presumably, the
tests are being run, because the code has been changed, a test environment that
can be screwed up is required.

To run the tests, just run

```
sudo dub test
```

from within the integration\_tests directory. It will do a clean build of
`bemgr` in the main directory and then run the integration tests using that
`bemgr` executable. The tests themselves are implemented within the `unittest`
blocks of the integration\_tests executable.

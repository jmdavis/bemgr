# bemgr activate

`bemgr activate <beName>`

This sets the given boot environment as the default boot environment, so it
will be the active boot environment the next time that the computer is
rebooted.

In more detail:

1. If the dataset of the BE is a
[clone](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-clone.8.html),
then it is
[promoted](https://openzfs.github.io/openzfs-docs/man/v2.3/8/zfs-promote.8.html#zfs-promote-8).

2. The dataset's
[`canmount`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#canmount)
property is set to `noauto` (which it should be already, but if someone has been messing
with the BE datasets manually, it might not be).

3. The dataset's
[`mountpoint`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#mountpoint)
property is set to `/` (which it should be already, but if someone has been messing
with the BE datasets manually, it might not be).

4. The `bootfs`
[`zpool property`](https://openzfs.github.io/openzfs-docs/man/v2.3/8/zpool-set.8.html)
is set to the dataset for the given boot environment so that the boot manager knows
to now boot it by default.

# bemgr create

`bemgr create [-e <beName> | -e <beName@snapshot>] <newBeName>`

This creates a new boot environment from an existing boot environment.

If `-e` is not used, then the new BE is created from the currently active BE.
For instance, if `default` were the current BE, and the parent of the BE
datasets is `zroot/ROOT`, then `bemgr create foo` will take a snapshot of
`zroot/ROOT/default` and clone that snapshot to create `zroot/ROOT/foo`.

If `-e <beName>` is used, then the new BE is created by taking a snapshot of
the BE provided to `-e` rather than the currently active BE. It is then cloned
just like would have occurred if the snapshot had been from the current BE. For
instance, `bemgr create -e foo bar` would create a snapshot of `zroot/ROOT/foo`
and clone it to create `zroot/ROOT/bar` regardless of which BE was currently
active.

If `-e <beName@snapshot>` is used, then instead of taking the snapshot of a BE
and cloning it, the given snapshot is cloned. So, if `zroot/ROOT/foo` had the
snapshot `zroot/ROOT/foo@2025-04-02_update`,
`bemgr -e foo@2025-04-02_update bar` would clone
`zroot/ROOT/foo@2025-04-02_update` and create `zroot/ROOT/bar`.

Regardless of what the newly created boot environment is a clone of, it has its
[`canmount`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#canmount)
property set to `noauto` and its
[`mountpoint`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#mountpoint)
property set to `/`.

Note that the default boot environment remains unchanged. `bemgr activate`
needs to be used to activate the new boot environment if that is desired.

# bemgr create

`bemgr create <beName@snapshot>`

Rather than creating a new boot environment, this just creates a snapshot of a
boot environment. For instance, if the parent of the BE datasets is
`zroot/ROOT`, then `bemgr foo@bar` will take a snapshot of `zroot/ROOT/foo`
which was `zroot/ROOT/foo@bar`. So, `bemgr create foo@bar` would be equivalent
to `zfs snap zroot/ROOT/foo@bar`.

# bemgr destroy

`bemgr destroy [-n] <beName>`

This destroys the given boot environment (and its origin if it has one and no
other dataset has the same origin).

`-n` tells `bemgr` to do a dry-run, so instead of actually destroying anything,
it simply prints out what would have been promoted or destroyed if `-n` hadn't
been used.

Note that there is no confirmation. So, anyone feeling paranoid about making
sure that they're destroying what they intend to should use `-n` to verify, but
without it, `bemgr destroy` will just destroy what it's supposed to without
nagging about stuff like whether the origin should be destroyed.

`-k` tells `bemgr` to keep the origin in the case where the BE dataset is a
clone; otherwise, it will be destroyed as long as it is not the origin of
another dataset. If the dataset is not a clone, then `-k` has no effect.

Normally, if any of what's being destroyed is mounted, it will be unmounted and
destroyed without a problem, but if it's actively in use, then zfs may refuse
to unmount it. `-F` can be used to forcibly unmount what's being destroyed if
that occurs (or you can unmount it first). Of course, normally, inactive
datasets are not mounted, and `bemgr` will refuse to destroy a dataset if it's
active.  So, `bemgr` destroy can't be used to destroy the currently running OS.

However, note that on Linux, there are corner cases where `-F` will fail (e.g.
if a snapshot affected by a promotion is currently mounted), because Linux
apparently doesn't support forcibly unmounting things to the degree that
FreeBSD does. `zfs destroy` is the only zfs command on Linux which supports
forcibly unmounting, and it does not support it for snapshots. So, if `bemgr`
needs to do any other commands which would require forcibly unmounting a
dataset or snapshot, they are likely to fail on Linux even with `-F`.

In more detail, what `bemgr destroy` does is:

1. If any of the boot environment's snapshots are the origin of another dataset
   (i.e. a dataset is a clone of that snapshot), then a clone of the newest
   snapshot with a clone will be promoted, shifting that origin snapshot and
   the other snapshots which are older than it to the clone that's promoted,
   meaning that they will not be destroyed.

2. If the boot environment has an origin (and thus is a clone), and that origin
   snapshot is not the origin of another dataset, then that origin snapshot will
   be destroyed.

3. The dataset itself and any of its remaining snapshots will be destroyed.

So, `bemgr` destroys what it destroys without asking for confirmation -
including the origin snapshot of the given dataset - but it promotes clones
where necessary so that the BE that it was told to destroy can be destroyed
without destroying any other datasets. The idea is that no cruft will be left
behind, and the user will not be nagged, but `-n` provides a way to preview the
results if desired.

# bemgr destroy

`bemgr destroy [-n] <beName@snapshot>`

This will destroy the given snapshot. So, if `zroot/ROOT` is the parent dataset
of the BEs, then `bemgr destroy foo@bar` will destroy `zroot/ROOT/foo@bar` and
would be equivalent to `zfs destroy zroot/ROOT/foo@bar`.

If the given snapshot is the origin of another dataset, then an error will be
printed out, and nothing will be destroyed.

`-n` tells `bemgr` to do a dry-run, so instead of actually destroying anything,
it simply prints out what would have been destroyed if `-n` hadn't been used.

Normally, if any of what's being destroyed is mounted, it will be unmounted and
destroyed without a problem, but if it's actively in use, then zfs may refuse
to unmount it. `-F` can be used to forcefully unmount what's being destroyed if
that occurs (or you can unmount it first). Of course, normally, snapshots are
not mounted.

Note however that `-F` will not always work on Linux, because `-f` for
`zfs destroy` does not forcibly unmount snapshots, and `zfs unmount` does not
support `-f` on Linux. If the snapshot is mounted, `bemgr` will attempt to
unmount it before destroying it so that it can be destroyed, but it can't
forcibly unmount it.

# bemgr export

`bemgr export [-k] [-v] sourceBE`

Takes a snapshot of the given BE and does `zfs send` on it to stdout so that it
can be piped or redirected to a file, or to ssh, etc.

`-k` makes it so that the snapshot is kept after the export has completed;
otherwise, the snapshot will be destroyed.

`-v` makes the output verbose.

# bemgr import

`bemgr import [-v] targetBE`

Takes a dataset from stdin (presumably having been read from a file or ssh) which
is then used with `zfs recv` to create a new boot environment with the given name.

`-v` makes the output verbose, though `zfs recv` doesn't print out much with
`-v`. `zfs send` is the end that gets the output that actually indicates the
progress of the stream, so `bemgr export -v` has much more useful output than
`bemgr import -v` does.

As with any new boot environment, the newly created BE has its
[`canmount`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#canmount)
property set to `noauto` and its
[`mountpoint`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#mountpoint)
property set to `/`.

# bemgr list

`bemgr list [-H]`

This lists out the existing boot environments, sorted by their creation time.

`-H` is used for scripting. It replaces all of the spaces between columns with
a single tab character. It also removes the column headers.

e.g.
```
BE                                 Active  Mountpoint    Space  Referenced  If Last  Created
2024-12-15_update                  -       -           562.95M      53.81G    61.3G  2024-12-15 20:57:18
2025-01-04_update                  -       -           737.47M      54.06G   61.55G  2025-01-04 02:48:02
2025-02-04_update                  -       -           698.62M      56.66G   64.15G  2025-02-04 19:22:18
14.1-RELEASE-p6_2025-02-09_094839  -       -             1.19M      57.07G   64.56G  2025-02-09 09:48:39
2025-02-09_freebsd14_2             -       -             1.94M      57.07G   64.56G  2025-02-09 17:00:25
14.2-RELEASE-p1_2025-02-09_181633  -       -             2.01M      58.22G   65.71G  2025-02-09 18:16:33
default                            NR      /            75.18G      59.04G   66.64G  2025-03-03 00:44:23
2025-03-29_update                  -       -              236K      59.03G    66.6G  2025-03-29 18:27:05
```

## Columns
* _BE_

  The name of the boot environment

* _Active_

  The active boot environment is the one that's mounted as root. `"-"`
means that that BE is inactive. `"N"` means that that BE is the active boot
environment now, and `"R"` means that it will be the active boot environment
when the system is next rebooted.

* _Mountpoint_

  The current mountpoint of the BE. `"-"` means that that boot environment is
not currently mounted and does not say anything about the
[`mountpoint`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#mountpoint)
property of the dataset (normally, that's always `/` for a BE's dataset).

  The currently active BE will show `/` as its mountpoint, and any other
BE which shows a mountpoint other than `"-"` will be showing its current
mountpoint and not the
[`mountpoint`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#mountpoint)
property of the dataset. Normally, no BEs other than the currently active one
will be mounted, but it is possible to mount them using `bemgr mount` or via
`mount`.

* _Space_

  For BEs whose dataset is not a clone, this is equivalent of the
[`used`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#used)
property of the dataset. For BEs whose dataset is a clone of a snapshot, it's
the `used` property of the dataset + the `used` property of the origin snapshot.

* _Referenced_

  This is equivalent to the
[`referenced`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#referenced)
property of the BE's dataset.

* _If Last_

  This is the amount of space that the BE is calculated to take up if
all of the other BE's are destroyed.

  In specific, if the BE's dataset is not a clone, then it's the total of the
[`usedbydataset`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#usedbydataset)
property of the BE's dataset, the
[`usedbyrefreservation`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#usedbyrefreservation)
property of the BE's dataset, and the
[`used`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#used)
property of any of its snapshots which are not the origin of another BE's
dataset (since `bemgr destroy` destroys the origin snapshot for a BE when it
destroys that BE). So, it's equivalent to the
[`used`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#used)
property of the dataset minus the space for its snapshots which are the origin
of another BE's dataset.

  If the BE's dataset is a clone, then the calculation is the same but under the
assumption that it's
[promoted](https://openzfs.github.io/openzfs-docs/man/v2.3/8/zfs-promote.8.html#zfs-promote-8)
first (which would move some snapshots currently under another dataset to the
dataset being promoted, since the origin snapshot and snapshots older than the
origin snapshot get moved to the dataset being promoted when it's promoted).
So, some snapshots besides the origin or those currently on that dataset could
be included. But regardless, no snapshots which are the origin of another BE's
dataset are included in `If Last` for any BE, since those snapshots are
destroyed when `bemgr destroy` is used on those BEs.

* _Created_

  This is the
[`creation`](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html#creation)
property of the BE's dataset, which gives the date/time that the BE was created.

# bemgr list

`bemgr list -a [-H] [-s]`

`bemgr list -a` lists out the existing boot environments, sorted by their
creation time, but it also lists out the dataset for each BE and the origin for
each BE (if it has one). If `-s` is provided, then the snapshots are also
listed (`-s` implies `-a`, so if it's used on its own, it's equivalent to
`-as`).

`-H` is used for scripting. It replaces all of the spaces between columns with
a single tab character. It also removes the column headers.

e.g. `bemgr list -a`
```
BE/Dataset/Snapshot                             Active  Mountpoint    Space  Referenced  Created

2024-12-15_update
  zroot/ROOT/2024-12-15_update                  -       -           562.95M      53.81G  2024-12-15 20:57:18
    zroot/ROOT/default@2024-12-15-20:57:18      -       -           562.94M      53.81G  2024-12-15 20:57:18

2025-01-04_update
  zroot/ROOT/2025-01-04_update                  -       -           737.47M      54.06G  2025-01-04 02:48:02
    zroot/ROOT/default@2025-01-04-02:48:02      -       -           737.46M      54.06G  2025-01-04 02:48:02

2025-02-04_update
  zroot/ROOT/2025-02-04_update                  -       -           698.62M      56.66G  2025-02-04 19:22:18
    zroot/ROOT/default@2025-02-04-19:22:18      -       -           698.61M      56.66G  2025-02-04 19:22:18

14.1-RELEASE-p6_2025-02-09_094839
  zroot/ROOT/14.1-RELEASE-p6_2025-02-09_094839  -       -             1.19M      57.07G  2025-02-09 09:48:39
    zroot/ROOT/default@2025-02-09-09:48:39-0    -       -             1.19M      57.07G  2025-02-09 09:48:39

2025-02-09_freebsd14_2
  zroot/ROOT/2025-02-09_freebsd14_2             -       -             1.94M      57.07G  2025-02-09 17:00:25
    zroot/ROOT/default@2025-02-09-17:00:24      -       -             1.93M      57.07G  2025-02-09 17:00:24

14.2-RELEASE-p1_2025-02-09_181633
  zroot/ROOT/14.2-RELEASE-p1_2025-02-09_181633  -       -             2.01M      58.22G  2025-02-09 18:16:33
    zroot/ROOT/default@2025-03-03-00:44:23      -       -             1.32M      58.22G  2025-03-03 00:44:23

default
  zroot/ROOT/default                            NR      /            75.18G      59.04G  2025-03-03 00:44:23

2025-03-29_update
  zroot/ROOT/2025-03-29_update                  -       -              236K      59.03G  2025-03-29 18:27:05
    zroot/ROOT/default@2025-03-29-18:27:05-0    -       -              228K      59.03G  2025-03-29 18:27:05
```

e.g. `bemgr list -as`
```
BE/Dataset/Snapshot                                           Active  Mountpoint    Space  Referenced  Created

2024-12-15_update
  zroot/ROOT/2024-12-15_update                                -       -           562.95M      53.81G  2024-12-15 20:57:18
    zroot/ROOT/default@2024-12-15-20:57:18                    -       -           562.94M      53.81G  2024-12-15 20:57:18

2025-01-04_update
  zroot/ROOT/2025-01-04_update                                -       -           737.47M      54.06G  2025-01-04 02:48:02
    zroot/ROOT/default@2025-01-04-02:48:02                    -       -           737.46M      54.06G  2025-01-04 02:48:02

2025-02-04_update
  zroot/ROOT/2025-02-04_update                                -       -           698.62M      56.66G  2025-02-04 19:22:18
    zroot/ROOT/default@2025-02-04-19:22:18                    -       -           698.61M      56.66G  2025-02-04 19:22:18

14.1-RELEASE-p6_2025-02-09_094839
  zroot/ROOT/14.1-RELEASE-p6_2025-02-09_094839                -       -             1.19M      57.07G  2025-02-09 09:48:39
    zroot/ROOT/default@2025-02-09-09:48:39-0                  -       -             1.19M      57.07G  2025-02-09 09:48:39

2025-02-09_freebsd14_2
  zroot/ROOT/2025-02-09_freebsd14_2                           -       -             1.94M      57.07G  2025-02-09 17:00:25
    zroot/ROOT/default@2025-02-09-17:00:24                    -       -             1.93M      57.07G  2025-02-09 17:00:24

14.2-RELEASE-p1_2025-02-09_181633
  zroot/ROOT/14.2-RELEASE-p1_2025-02-09_181633                -       -             2.01M      58.22G  2025-02-09 18:16:33
    zroot/ROOT/default@2025-03-03-00:44:23                    -       -             1.32M      58.22G  2025-03-03 00:44:23

default
  zroot/ROOT/default                                          NR      /            75.18G      59.04G  2025-03-03 00:44:23
  zroot/ROOT/default@2024-12-15-20:57:18                      -       -           562.94M      53.81G  2024-12-15 20:57:18
  zroot/ROOT/default@2025-01-04-02:48:02                      -       -           737.46M      54.06G  2025-01-04 02:48:02
  zroot/ROOT/default@2025-02-04-19:22:18                      -       -           698.61M      56.66G  2025-02-04 19:22:18
  zroot/ROOT/default@2025-02-09-09:48:39-0                    -       -             1.19M      57.07G  2025-02-09 09:48:39
  zroot/ROOT/default@2025-02-09-17:00:24                      -       -             1.93M      57.07G  2025-02-09 17:00:24
  zroot/ROOT/default@2025-03-03-00:44:23                      -       -             1.32M      58.22G  2025-03-03 00:44:23
  zroot/ROOT/default@zfs-auto-snap_daily-2025-03-28-05h07     -       -            88.02M      59.03G  2025-03-28 05:07:01
  zroot/ROOT/default@zfs-auto-snap_daily-2025-03-29-05h07     -       -             2.95M      59.03G  2025-03-29 05:07:01
  zroot/ROOT/default@2025-03-29-18:27:05-0                    -       -              228K      59.03G  2025-03-29 18:27:05
  zroot/ROOT/default@zfs-auto-snap_daily-2025-03-30-05h07     -       -             1.17M      58.96G  2025-03-30 05:07:01
  zroot/ROOT/default@zfs-auto-snap_daily-2025-03-31-05h07     -       -             2.53M      58.97G  2025-03-31 05:07:01
  zroot/ROOT/default@zfs-auto-snap_daily-2025-04-01-05h07     -       -             1.25M      58.95G  2025-04-01 05:07:01
  zroot/ROOT/default@zfs-auto-snap_daily-2025-04-02-05h07     -       -              724K      58.96G  2025-04-02 05:07:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-15h00    -       -              496K      58.96G  2025-04-02 15:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-16h00    -       -              416K      58.96G  2025-04-02 16:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-17h00    -       -              424K      58.96G  2025-04-02 17:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-18h00    -       -              492K      58.96G  2025-04-02 18:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-19h00    -       -              908K      58.96G  2025-04-02 19:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-20h00    -       -              392K      58.96G  2025-04-02 20:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-21h00    -       -              392K      58.96G  2025-04-02 21:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-22h00    -       -              400K      58.96G  2025-04-02 22:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-02-23h00    -       -              408K      58.96G  2025-04-02 23:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-00h00    -       -              384K      58.96G  2025-04-03 00:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-01h00    -       -              384K      58.96G  2025-04-03 01:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-02h00    -       -              464K      58.96G  2025-04-03 02:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-03h00    -       -              552K      58.96G  2025-04-03 03:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-04h00    -       -              676K      58.96G  2025-04-03 04:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-05h00    -       -              288K      58.96G  2025-04-03 05:00:01
  zroot/ROOT/default@zfs-auto-snap_daily-2025-04-03-05h07     -       -              352K      58.96G  2025-04-03 05:07:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-06h00    -       -              392K      58.96G  2025-04-03 06:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-07h00    -       -              368K      58.96G  2025-04-03 07:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-08h00    -       -              408K      58.96G  2025-04-03 08:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-09h00    -       -              424K      58.96G  2025-04-03 09:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-10h00    -       -              392K      58.96G  2025-04-03 10:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-11h00    -       -              384K      58.96G  2025-04-03 11:00:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-12h00    -       -              468K      58.96G  2025-04-03 12:00:32
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-13h00    -       -                0B      59.04G  2025-04-03 13:00:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h05  -       -                0B      59.04G  2025-04-03 13:05:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h10  -       -              104K      59.04G  2025-04-03 13:10:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h15  -       -              104K      59.04G  2025-04-03 13:15:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h20  -       -              104K      59.04G  2025-04-03 13:20:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h25  -       -                0B      59.04G  2025-04-03 13:25:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h30  -       -                0B      59.04G  2025-04-03 13:30:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h35  -       -                0B      59.04G  2025-04-03 13:35:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h40  -       -                0B      59.04G  2025-04-03 13:40:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h45  -       -                0B      59.04G  2025-04-03 13:45:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h50  -       -                0B      59.04G  2025-04-03 13:50:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-13h55  -       -              104K      59.04G  2025-04-03 13:55:01
  zroot/ROOT/default@zfs-auto-snap_hourly-2025-04-03-14h00    -       -              104K      59.04G  2025-04-03 14:00:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-14h05  -       -              128K      59.04G  2025-04-03 14:05:01
  zroot/ROOT/default@zfs-auto-snap_frequent-2025-04-03-14h10  -       -                0B      59.04G  2025-04-03 14:10:01

2025-03-29_update
  zroot/ROOT/2025-03-29_update                                -       -              236K      59.03G  2025-03-29 18:27:05
    zroot/ROOT/default@2025-03-29-18:27:05-0                  -       -              228K      59.03G  2025-03-29 18:27:05
```

The columns are basically the same as with `bemgr list` without `-a` except
that there is no `If Last`. However, the column for names is obviously somewhat
different.

In the case of
```
2025-02-04_update
  zroot/ROOT/2025-02-04_update                                -       -           698.62M      56.66G  2025-02-04 19:22:18
    zroot/ROOT/default@2025-02-04-19:22:18                    -       -           698.61M      56.66G  2025-02-04 19:22:18
```

`2024-02-04_update` is the BE name, `zroot/ROOT/2025-02-04_update` is the
dataset for that BE, and `zroot/ROOT/default@2025-02-04-19:22:18` is the origin
snapshot of that dataset. Since the dataset has no snapshots of its own, that's
the entire list even with `-s`, whereas if it had additional snapshots, they'd
be listed after the origin. For instance, if it gained a `foo` and `bar` snapshot,
then its output from `bemgr list -as` would look something like

```
2025-02-04_update
  zroot/ROOT/2025-02-04_update                                -       -            955.4M      56.66G  2025-02-04 19:22:18
    zroot/ROOT/default@2025-02-04-19:22:18                    -       -           955.39M      56.66G  2025-02-04 19:22:18
  zroot/ROOT/2025-02-04_update@foo                            -       -                0B      56.66G  2025-04-15 19:38:05
  zroot/ROOT/2025-02-04_update@bar                            -       -                0B      56.66G  2025-04-15 19:38:07
```

or if instead it were activated (and thus its dataset was promoted), then its
output from `bemgr list -as` would look something like

```
2025-02-04_update
  zroot/ROOT/2025-02-04_update                                -       -            70.02G      56.66G  2025-02-04 19:22:18
  zroot/ROOT/2025-02-04_update@2024-12-15-20:57:18            -       -           562.94M      53.81G  2024-12-15 20:57:18
  zroot/ROOT/2025-02-04_update@2025-01-04-02:48:02            -       -           737.46M      54.06G  2025-01-04 02:48:02
  zroot/ROOT/2025-02-04_update@2025-02-04-19:22:18            -       -                8K      56.66G  2025-02-04 19:22:18
```

since the origin snapshot and the snapshots older than it would
be moved to `zroot/ROOT/2025-02-04_update` when it's promoted.

# bemgr mount

`bemgr mount <beName> <mountpoint>`

This mounts the given boot environment at the given mountpoint. It has no
effect on the mountpoint property of the dataset. It's intended for use
cases where you need to access the contents of a boot environment without
actually booting it.

For instance, if the parent dataset of the BEs is `zroot/ROOT`, then
`bemgr mount foo /mnt` would be equivalent to
`mount -t zfs zroot/ROOT/foo /mnt` on FreeBSD or
`mount -t zfs -o zfsutil zroot/ROOT/foo /mnt` on Linux.

The mountpoint must exist.

# bemgr rename

`bemgr rename <origBEName> <newBEName>`

This renames the given boot environment. It has no effect on mounting.

For instance, if the parent dataset of the BEs is `zroot/ROOT`, then
`bemgr rename foo bar` would be equivalent to
`zfs rename -u zroot/ROOT/foo zroot/ROOT/bar`.

In addition, if the BE in the `bootfs` zpool property is the one that's renamed
(i.e. the BE that will be active when the system next boots), then the `bootfs`
zpool property is updated accordingly.

# bemgr umount

`bemgr umount [-f] <beName>`

`bemgr unmount [-f] <beName>`

This unmounts the given boot environment (but will not work on the currently
active boot environment).

For instance, if the parent dataset of the BEs is `zroot/ROOT`, then
`bemgr umount foo` would be equivalent to `zfs unmount zroot/ROOT/foo`.

On FreeBSD, `-f` causes the dataset to be unmounted even if it's busy. On
Linux, `-f` is not supported, because `zfs umount` on Linux does not support
forcefully unmounting datasets.

On FreeBSD, `-f` attempts to unmount the dataset even if it's busy. However, on
Linux, `-f` currently does nothing, because `zfs unmount` on Linux does not
support forcibly unmounting datasets. `-f` is passed along to `zfs unmount`, so
if it starts supporting it on Linux at some point in the future, then `bemgr
umount` should start supporting it on Linux as well, but of course, that may
never happen.

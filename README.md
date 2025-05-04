`bemgr` is a program for managing ZFS boot environments on either FreeBSD or
Linux. It is modeled after programs such as `bectl` and `beadm`. `bemgr` was
created primarily because bectl and beadm don't exist for Linux, but it works
on FreeBSD as well. Its feature set is similar to those of bectl and beadm,
though there are some differences - e.g. `bemgr list` lists "Referenced" and
"If Last" (which shows how much space a boot environment would take up if the
others were all destroyed) rather than having the `-D` flag like bectl and
beadm.

# ZFS and Boot Environments

FreeBSD documentation on boot environments:
[https://wiki.freebsd.org/BootEnvironments](https://wiki.freebsd.org/BootEnvironments)

zfsbootmenu documentation on boot environments:
[https://docs.zfsbootmenu.org/en/v3.0.x/general/bootenvs-and-you.html](https://docs.zfsbootmenu.org/en/v3.0.x/general/bootenvs-and-you.html)

The typical layout for zfs boot environments would be something like
```
zroot/ROOT/default
zroot/ROOT/2025-03-29_before_update
zroot/ROOT/2025-04-17_before_update
zroot/ROOT/testing_some_package
```

The pool name of course does not matter, and the parent dataset doesn't need to
be named `ROOT`, but it's common practice. Each dataset under the parent
dataset is a separate boot environment. Each boot environment dataset contains
the root of the filesystem, allowing you to have separate copies, making
rolling back changes easy. And since the combination of `zfs snap` and
`zfs clone` makes it so that data is shared across datasets until it's changed,
the space requirements are much less than they would be if the boot
environments were fully independent copies. So, COW (copy-on-write) comes to
the rescue as it often does with ZFS.

Each boot environment should have its `mountpoint` property set to `/`, and its
`canmount` property should be set to `noauto` so that it does not get mounted
automatically. The `bootfs` property on the pool will then tell the boot
manager which boot environment to mount as root by default (e.g.
`bootfs=zroot/ROOT/default`)

`bemgr` expects that boot environments will not have any child datasets. Other
datasets can of course be mounted on top of the boot environment, but they
should be placed elsewhere in the pool and not under the datasets for the boot
environments.

Directories that should be separate from the OS and shared across boot
environments - such as /home or /var/log - then have their own datasets which
mount on top of the boot environment. So, when you switch between boot
environments, those directories are unchanged.

So, common usage would be to run `bemgr create` to create a new boot
environment from the currently active boot environment before making large
changes to the OS (e.g. updating the packages which are installed or doing a
major OS upgrade). That way, if something goes wrong, it's possible to restore
the previous state of the OS by switching to the previous boot environment.

`bemgr activate` is used to set a different boot environment as the default so
that it will be the active boot environment the next time that the computer
reboots (and boot managers will typically give the ability to manually select a
boot environment other than the default to boot from).

`bemgr destroy` is used to remove boot environments.

`bemgr rename` is used to rename a boot environment.

`bemgr list` is used to list the boot environments on the system.

`bemgr mount` is used to mount an inactive boot environment in an alternate
location in order to access its files.

`bemgr umount` is used to unmount a mounted inactive boot environment.

`bemgr export` is used to export a boot environment to stdout.

`bemgr import` is used to import a boot environment from stdin.

# `bemgr` Commands

See [usage](usage.md) for detailed information on each of the commands.

# FreeBSD

A standard install of FreeBSD on ZFS will be set up to use boot environments,
so no special handling is required. `freebsd-update` now even creates a new
boot environment when it updates the system (though `pkg upgrade` does not).

bemgr is certainly not necessary on FreeBSD, since bectl comes with it, and
beadm can be easily installed via ports. However, it wasn't much work to get
`bemgr` working on FreeBSD, and it allows for anyone using it on Linux to have
the same experience on FreeBSD if that's desirable. And since it does behave
slightly differently than bectl and beadm do, it may be more to your liking
depending on your preferences.

# Linux

The [zfsbootmenu documentation](https://docs.zfsbootmenu.org) has instructions
for how to install ZFS on root with boot environments on several distros.

Similarly, the
[OpenZFS documentation](https://openzfs.github.io/openzfs-docs/Getting%20Started/index.html)
has guides for installing ZFS on root on several distros (though not
necessarily with boot environments).

bemgr does nothing to explicitly support any boot managers, so for a boot manager
to work with bemgr, it must work with standard ZFS boot environments.

[zfsbootmenu](https://zfsbootmenu.org/) is known to work with bemgr, because it
supports standard ZFS boot environments without any special handling being
required. It also supports up-to-date versions of ZFS and thus does not require
restricting the feature set used by a boot pool.

For those who wish to use zfsbootmenu in a dual-boot environment, rEFInd can be
used to load both zfsbootmenu and the boot loaders for other operating systems.

[GRUB](https://www.gnu.org/software/grub/) is not explicitly supported. It may
be possible to use GRUB with bemgr, but GRUB is not designed around using ZFS
boot environments, and it does not support recent ZFS features.

# Building `bemgr`

See [building](building.md)

# Differences from `beadm` and `bectl`

The primary differences between `beadm` and `bectl` and `bemgr` are that

1. `bemgr list` has the _Referenced_ and _If Last_ columns, whereas `beadm` and
   `bectl` do not - though they have the `-D` flag which causes the _Space_
   column to be similar to _If Last_.

2. `bemgr list` and `beadm list` both list the BEs sorted by their creation
   times, whereas `bectl list` sorts them by their names by default. However,
   `bectl list` does have a flag to specify the property to sort the list by,
   whereas `bemgr list` and `beadm list` do not.

3. `bemgr destroy` destroys origins without asking for confirmation, but it has
   `-n` to do a dry-run, whereas `beadm destroy` asks before destroying
   origins, and `bectl destroy` does not destroy origins by default. And
   neither `beadm destroy` nor `bectl destroy` has a way to do dry-runs.

4. bemgr has no equivalent to `beadm chroot` or `bectl jail`.

# Differences from `zectl`

`zectl` is a Linux-only solution which provides similar functionality to
`beadm` and `bectl`. However, it differs from them more than `bemgr` does
(which may be good or bad depending on your preferences or use cases). Some of
the differences between `zectl` and `bemgr` are

1. `zectl` has a way to provide plugins to support bootloaders. At present,
   it only provides a plugin for systemdboot, but that means that it supports
   both zfsbootmenu (since zfsbootmenu doesn't require special support)
   and systemdboot, whereas `bemgr` only supports zfsbootmenu.

2. `zectl get` and `zectl set` allow `zectl` to get and set properties specific
   to `zectl` on the parent dataset of the BEs (e.g. related to the bootloader
   plugin you want to use). `bemgr` has no comparable functionality, but it
   also doesn't have any zfs properties specific to it that it would need to
   get or set.

3. `zectl list` only has the _Name_, _Active_, _Mountpoint_, and _Creation_
   columns. It provides no information about space utilization.

4. `zectl list` lists the BEs sorted by their names, whereas `bemgr list` lists
   them sorted by their creation times.

5. `zectl list` does not provide either the `-a` or `-s` flags and provides no
   way to list snapshots or the origins of BEs which are clones.

6. `zectl create` cannot create snapshots. However, `zectl snapshot` provides
   that functionality.

7. Like `bemgr destroy`, `zectl destroy` destroys origins without asking for
   confirmation, but it does not have a flag to do a dry-run, so you can't see
   what it's going to destroy first.

8. `zectl destroy` does not appear to attempt to promote clones in order to
   make it possible to destroy boot environments which have snapshots which are
   the origin of another BE (or of any other dataset). It will succeed at
   destroying a BE when it cannot destroy its origin (e.g. because another BE
   has the same origin), but it reports that it's failed.

   So, `zectl destroy` should work just fine in the typical case where you
   create a new BE from the current one when upgrading and then later destroy
   it, but if you're creating a lot of snapshots of BEs and creating other BEs
   from those snapshots, you're probably going to run into cases where it
   fails, whereas `bemgr destroy` attempts to promote clones where necessary so
   that the destruction can succeed. Of course, that doesn't mean that there
   aren't any corner cases where `bemgr destroy` will fail, but it seems to
   handle many more than `zectl destroy` does.

9. `zectl` has no `import` or `export` commands.

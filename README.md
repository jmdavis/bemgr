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

`bemgr activate` is used to switch to a different boot environment the next
time that the computer reboots (and boot managers will typically give the
ability to manually select a boot environment other than the default to boot
from).

`bemgr destroy` is used to remove boot environments.

`bemgr rename` is used to rename a boot environment.

`bemgr list` is used to list the boot environments on the system.

`bemgr mount` is used to mount an inactive boot environment in an alternate
location in order to access its files.

`bemgr umount` is used to unmount a mounted inactive boot environment.

`bemgr export` is used to export a boot environment to stdout.

`bemgr import` is used to import a boot environment from stdin.

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

# Installation

# Commands

See [usage](usage.md)

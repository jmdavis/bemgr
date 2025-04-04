// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module bemgr.mount;

int doMount(string[] args)
{
    enum helpMsg =
`bemgr mount <beName> <mountpoint>

  Mounts the given boot environment at the given mountpoint.
  It has no effect on the mountpoint property of the dataset.
`;
    import std.exception : enforce;
    import std.file : exists, isDir;
    import std.format : format;
    import std.getopt : getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;

    import bemgr.util : getPoolInfo, runCmd;

    bool help;

    getopt(args, "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 4, helpMsg);

    immutable beName = args[2];
    immutable mountpoint = args[3];

    auto poolInfo = getPoolInfo();
    immutable dataset = buildPath(poolInfo.beParent, beName);

    runCmd(format!`zfs list %s`(esfn(dataset)), format!"Error: %s does not exist"(dataset));
    enforce(dataset !in poolInfo.mountpoints,  format!"Error: %s is already mounted"(dataset));

    enforce(mountpoint.exists, format!"Error: %s does not exist"(mountpoint));
    enforce(mountpoint.isDir, format!"Error: %s is not a directory"(mountpoint));

    version(FreeBSD)
        runCmd(format!"mount -t zfs %s %s"(esfn(dataset), esfn(mountpoint)));
    else version(linux)
        runCmd(format!"mount -t zfs -o zfsutil %s %s"(esfn(dataset), esfn(mountpoint)));
    else
        static assert(false, "Unsupport OS");

    return 0;
}

int doUmount(string[] args)
{
    enum helpMsg =
`bemgr umount <beName>
bemgr unmount <beName>

  Unmounts the given inactive boot environment.
  It does not support forcefully unmounting, because zfs umount does not support
  it on Linux, but if you know where the mountpoint is, then
`;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;

    import bemgr.util : getPoolInfo, runCmd;

    bool help;

    getopt(args, "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 3, helpMsg);

    immutable beName = args[2];

    auto poolInfo = getPoolInfo();
    immutable dataset = buildPath(poolInfo.beParent, beName);

    runCmd(format!`zfs list %s`(esfn(dataset)), format!"Error: %s does not exist"(dataset));
    enforce(dataset in poolInfo.mountpoints, format!"Error: %s is not mounted"(dataset));

    runCmd(format!"zfs umount %s"(esfn(dataset)));

    return 0;
}

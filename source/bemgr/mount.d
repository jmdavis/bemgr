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
  It has no effect on the mountpoint property of the dataset.`;

    import std.exception : enforce;
    import std.file : exists, isDir;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;

    import bemgr.util : enforceDSExists, getPoolInfo, runCmd;

    bool help;

    getopt(args, config.bundling,
           "help", &help);

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

    enforceDSExists(dataset);
    enforce(dataset !in poolInfo.mountpoints,  format!"Error: %s is already mounted"(dataset));

    enforce(mountpoint.exists, format!"Error: %s does not exist"(mountpoint));
    enforce(mountpoint.isDir, format!"Error: %s is not a directory"(mountpoint));

    version(FreeBSD)
        runCmd(format!"mount -t zfs %s %s"(esfn(dataset), esfn(mountpoint)));
    else version(linux)
        runCmd(format!"mount -t zfs -o zfsutil %s %s"(esfn(dataset), esfn(mountpoint)));
    else
        static assert(false, "Unsupported OS");

    return 0;
}

int doUmount(string[] args)
{
    enum helpMsg =
`bemgr umount <beName>
bemgr unmount <beName>

  Unmounts the given inactive boot environment.

  -f On FreeBSD, this will forcefully unmount the dataset.
     It is not supported on Linux, because "zfs mount" does not support it on
     Linux.`;

    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;

    import bemgr.util : enforceDSExists, getPoolInfo, runCmd;

    bool force;
    bool help;

    version(FreeBSD)
    {
        getopt(args, config.bundling,
               "f", &force,
               "help", &help);
    }
    else version(linux)
    {
        getopt(args, config.bundling,
               "help", &help);
    }
    else
        static assert(false, "Unsupported OS");

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 3, helpMsg);

    immutable beName = args[2];

    auto poolInfo = getPoolInfo();
    immutable dataset = buildPath(poolInfo.beParent, beName);

    enforceDSExists(dataset);
    enforce(dataset in poolInfo.mountpoints, format!"Error: %s is not mounted"(dataset));

    runCmd(format!"zfs umount%s %s"(force ? " -f" : "", esfn(dataset)));

    return 0;
}

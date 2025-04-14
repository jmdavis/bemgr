// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module realapp;

import std.range.primitives;

int realMain(string[] args)
{
    immutable helpMsg =
`bemgr - A program for managing zfs boot environments on FreeBSD or Linux

  begmr --help
  bemgr activate <beName>
  bemgr create [-e <beName> | -e <beName@snapshot>] <newBEName>
  bemgr create <beName@snapshot>
  bemgr destroy [-n] [-F] <beName>
  bemgr destroy [-n] [-F] <beName@snapshot>
  bemgr export [-k] [-v] sourceBE
  bemgr import [-v] targetBE
  bemgr list [-a] [-H] [-s]
  bemgr mount <beName> <mountpoint>
  bemgr rename <origBEName> <newBEName>
  bemgr umount [-f] <beName>
  bemgr unmount [-f] <beName>

Use --help on individual commands for more information.`;

    import std.exception : enforce;
    import std.getopt : GetOptException;
    import std.stdio : stderr, writeln;

    import bemgr.create : doCreate, doRename;
    import bemgr.destroy : doDestroy;
    import bemgr.export_ : doExport, doImport;
    import bemgr.list : doList;
    import bemgr.mount : doMount, doUmount;

    try
    {
        enforce(args.length >= 2, helpMsg);

        switch(args[1])
        {
            case "activate": return doActivate(args);
            case "create": return doCreate(args);
            case "destroy": return doDestroy(args);
            case "export": return doExport(args);
            case "import": return doImport(args);
            case "list": return doList(args);
            case "mount": return doMount(args);
            case "rename": return doRename(args);
            case "umount":
            case "unmount": return doUmount(args);
            case "--help": writeln(helpMsg); return 0;
            default: throw new Exception(helpMsg);
        }
    }
    catch(Exception e)
    {
        stderr.writeln(e.msg);
        return 1;
    }
}

int doActivate(string[] args)
{
    enum helpMsg =
`  bemgr activate <beName>

    Sets the given boot environment as the one to boot the next time that the
    computer is rebooted.`;

    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writefln, writeln;

    import bemgr.util : getPoolInfo, promote, runCmd, versionWithSetU, Version;

    bool help;

    getopt(args, config.bundling,
           "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 3, helpMsg);

    immutable beName = args[2];
    auto poolInfo = getPoolInfo();
    immutable dataset = buildPath(poolInfo.beParent, beName);

    // These two should already be the case, since they're set when the boot
    // environment is created, but we can't guarantee that no one has messed
    // with them since then, so better safe than sorry. set -u needs to be used
    // with mountpoint to ensure that if the dataset has already been mounted,
    // it won't be unmounted and then remounted on top of the currently running
    // OS.
    runCmd(format!"zfs set canmount=noauto %s"(esfn(dataset)));

    // Unfortunately, set -u doesn't exist prior to zfs version 2.2.0, and there
    // isn't a way to do the same thing without it.
    if(poolInfo.zfsVersion >= versionWithSetU)
        runCmd(format!"zfs set -u mountpoint=/ %s"(esfn(dataset)));
    else
    {
        if(runCmd(format!"zfs get -Ho value mountpoint %s"(esfn(dataset))) != "/")
        {
            if(auto mountpoint = dataset in poolInfo.mountpoints)
            {
                throw new Exception(format!
`The mountpoint property of %s is not "/", but it is mounted, so bemgr cannot fix it for you.
It needs to be unmounted before it can be activated.`(dataset));
            }
            else
                runCmd(format!"zfs set mountpoint=/ %s"(esfn(dataset)));
        }
    }

    if(poolInfo.bootFS == dataset)
    {
        writeln("Already activated");
        return 0;
    }

    immutable origin = runCmd(format!"zfs list -Ho origin %s"(esfn(dataset)),
                              format!"Error: %s does not exist"(dataset));
    if(origin != "-")
        promote(dataset);

    runCmd(format!"zpool set bootfs=%s %s"(esfn(dataset), esfn(poolInfo.pool)));

    writefln("Successfully activated: %s", beName);

    return 0;
}

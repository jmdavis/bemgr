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

    import bemgr.create : doCreate;
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
            case "umount": return doUmount(args);
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

    import bemgr.util : getPoolInfo, runCmd;

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

    if(poolInfo.bootFS == dataset)
        writeln("Already activated");

    if(poolInfo.rootFS != dataset)
    {
        // These two should already be the case, since they're set when the
        // boot environment is created, but we can't guarantee that no one has
        // messed with them since then, so better safe than sorry.
        // set -u needs to be used with mountpoint to ensure that if the
        // dataset has already been mounted, it won't be unmounted and then
        // remounted on top of the currently running OS.
        runCmd(format!"zfs set canmount=noauto %s"(esfn(dataset)));
        runCmd(format!"zfs set -u mountpoint=/ %s"(esfn(dataset)));
    }

    immutable origin = runCmd(format!"zfs list -Ho origin %s"(esfn(dataset)),
                              format!"Error: %s does not exist"(dataset));
    if(origin != "-")
        runCmd(format!"zfs promote %s"(esfn(dataset)));

    runCmd(format!"zpool set bootfs=%s %s"(esfn(dataset), esfn(poolInfo.pool)));

    writefln("Successfully activated: %s", beName);

    return 0;
}

int doRename(string[] args)
{
    enum helpMsg =
`bemgr rename <origBEName> <newBEName>

  Renames the given boot environment.`;

    import std.exception : enforce;
    import std.format : format;
    import std.getopt : getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : stderr, writeln;

    import bemgr.util : getPoolInfo, runCmd;

    bool help;

    getopt(args, "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 4, helpMsg);

    immutable origBE = args[2];
    immutable newBE = args[3];

    auto poolInfo = getPoolInfo();
    immutable source = buildPath(poolInfo.beParent, origBE);
    immutable target = buildPath(poolInfo.beParent, newBE);
    immutable renamingRootFS = poolInfo.rootFS == source;

    runCmd(format!"zfs rename -u %s %s"(esfn(source), esfn(target)));

    if(renamingRootFS)
    {
        // This should never happen, but it is technically possible if the
        // current non-root user has permissions to rename BEs but then can't
        // change the pool's properties. Realistically though, no user other
        // than root should have permissions like that on the BEs.
        scope(failure)
            stderr.writefln!"Warning: The active BE was renamed, but the bootfs property on %s could not be updated to match."(poolInfo.pool);

        runCmd(format!"zpool set bootfs=%s %s"(esfn(target), esfn(poolInfo.pool)));
    }

    return 0;
}

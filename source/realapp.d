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

  bemgr activate <beName>\n" ~
  bemgr create [-e <nonActiveBE> | -e <beName@snapshot>] <beName>\n" ~
  bemgr create <beName@snapshot>\n" ~
  bemgr destroy [-n] <beName>\n" ~
  bemgr destroy [-n] <beName@snapshot>\n" ~
  bemgr list [-H] [--origin | -o]\n" ~
  bemgr mount <beName> <mountpoint>\n" ~
  bemgr rename <origBEName> <newBEName>\n" ~
  bemgr umount [-f <beName>]\n" ~

Use --help on individual commands for more information.`;

    import std.exception : enforce;
    import std.getopt : GetOptException;
    import std.stdio : stderr, writeln;

    import bemgr.create : doCreate;
    import bemgr.destroy : doDestroy;
    import bemgr.list : doList;

    try
    {
        enforce(args.length >= 2, helpMsg);

        switch(args[1])
        {
            case "activate": return doActivate(args);
            case "create": return doCreate(args);
            case "destroy": return doDestroy(args);
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

    Sets the given boot environment as the one to boot next time that the
    computer is rebooted.`;

    import std.exception : enforce;
    import std.format : format;
    import std.getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writefln, writeln;

    import bemgr.util : getPoolInfo, isMounted, runCmd;

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

    enforce(!isMounted(dataset), "Error: Cannot activate a mounted dataset");

    immutable origin = runCmd(format!"zfs list -Ho origin %s"(esfn(dataset)),
                              format!"Error: %s does not exist"(dataset));

    if(origin != "-")
        runCmd(format!"zfs promote %s"(esfn(dataset)));

    // These two should already be the case, since they're set when the boot
    // environment is created, but we can't guarantee that no one has messed
    // with them since then, so better safe than sorry. It's also why we need
    // to check whether the dataset is mounted, since we don't want to mess
    // with the mountpoint while the dataset is mounted (doing so can actually
    // result in it being mounted on top of the running OS, making the OS
    // inaccessible).
    runCmd(format!"zfs set canmount=noauto %s"(esfn(dataset)));
    runCmd(format!"zfs set mountpoint=/ %s"(esfn(dataset)));

    runCmd(format!"zpool set bootfs=%s"(esfn(dataset)));

    writefln("Successfully activated: %s", beName);

    return 0;
}

int doMount(string[] args)
{
    assert(0);
}

int doRename(string[] args)
{
    enum helpMsg =
`bemgr rename <origBEName> <newBEName>

  Renames the given boot environment.`;

    import std.exception : enforce;
    import std.format : format;
    import std.getopt;
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

    immutable origBE = args[2];
    immutable newBE = args[3];

    auto poolInfo = getPoolInfo();
    immutable source = buildPath(poolInfo.beParent, origBE);
    immutable target = buildPath(poolInfo.beParent, newBE);

    runCmd(format!"zfs rename %s %s"(esfn(source), esfn(target)));

    return 0;
}

int doUmount(string[] args)
{
    assert(0);
}

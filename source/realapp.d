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

  bemgr activate <beName>
  bemgr create [-e <beName> | -e <beName@snapshot>] <newBeName>
  bemgr create <beName@snapshot>
  bemgr destroy [-n] <beName>
  bemgr destroy [-n] <beName@snapshot>
  bemgr export [-v] sourceBE
  bemgr import [-v] targetBE
  bemgr list [-a] [-H] [-s]
  bemgr mount <beName> <mountpoint>
  bemgr rename <origBEName> <newBEName>
  bemgr umount <beName>
  bemgr unmount <beName>

Use --help on individual commands for more information.`;

    import std.exception : enforce;
    import std.getopt : GetOptException;
    import std.stdio : stderr, writeln;

    import bemgr.create : doCreate;
    import bemgr.destroy : doDestroy;
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
    import std.getopt : getopt;
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

    if(poolInfo.bootFS == dataset)
        writeln("Already activated");

    if(poolInfo.rootFS != dataset)
    {
        // We want to be able to make it so that the currently active BE is
        // active again on reboot if another BE is currently set to be active
        // on reboot, but we don't want to muck around with mounted BE's
        // otherwise, since changing the mountpoint to / will make it mount on
        // top of the currently active BE and screw the system up.
        enforce(!isMounted(dataset), "Error: Cannot activate a mounted dataset");

        // These two should already be the case, since they're set when the
        // boot environment is created, but we can't guarantee that no one has
        // messed with them since then, so better safe than sorry. It's also
        // why we need to check whether the dataset is mounted, since we don't
        // want to mess with the mountpoint while the dataset is mounted (doing
        // so can actually result in it being mounted on top of the running OS,
        // making the OS inaccessible).
        runCmd(format!"zfs set canmount=noauto %s"(esfn(dataset)));
        runCmd(format!"zfs set mountpoint=/ %s"(esfn(dataset)));
    }

    immutable origin = runCmd(format!"zfs list -Ho origin %s"(esfn(dataset)),
                              format!"Error: %s does not exist"(dataset));
    if(origin != "-")
        runCmd(format!"zfs promote %s"(esfn(dataset)));

    runCmd(format!"zpool set bootfs=%s %s"(esfn(dataset), esfn(poolInfo.pool)));

    writefln("Successfully activated: %s", beName);

    return 0;
}

int doExport(string[] args)
{
    enum helpMsg =
`bemgr export <sourceBE>

  Exports the given boot environment to stdout. stdout must be piped or
  redirected to another program or file.

  -v displays verbose output
`;
    import std.datetime.date : DateTime;
    import std.datetime.systime : Clock;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName, executeShell, spawnShell, wait;
    import std.stdio : stderr, writeln;

    import bemgr.util : getPoolInfo, runCmd;

    bool verbose;
    bool help;

    getopt(args, "v", &verbose,
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
    immutable snapName = format!"%s@%s"(dataset, (cast(DateTime)Clock.currTime()).toISOExtString());

    runCmd(format!`zfs list %s`(esfn(dataset)), format!"Error: %s does not exist"(dataset));

    runCmd(format!`zfs snap %s`(esfn(snapName)));
    if(verbose)
        stderr.writefln("Created snapshot: %s\n", snapName);

    scope(success)
    {
        if(verbose)
            stderr.writeln("\nExport complete");
    }

    scope(exit)
    {
        if(executeShell(format!`zfs list %s`(esfn(snapName))).status == 0)
        {
           if(executeShell(format!`zfs destroy %s`(esfn(snapName))).status == 0)
           {
               if(verbose)
                   stderr.writefln("\n%s destroyed", snapName);
           }
           else
               stderr.writefln!"Warning: Failed to destroy snapshot for export: %s"(snapName);
        }
        else
            stderr.writefln("Warning: %s is missing and thus cannot be destroyed", snapName);
    }

    enforce(wait(spawnShell(format!`zfs send%s %s`(verbose ? " -v" : "", esfn(snapName)))) == 0,
            "Error: zfs send failed");

    return 0;
}

int doImport(string[] args)
{
    enum helpMsg =
`bemgr import <targetBE>

  Takes input from stdin to create the given boot environment and creates
  the given boot environment from it.

  -v displays verbose output
`;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName, executeShell, spawnShell, wait;
    import std.stdio : stderr, writeln;

    import bemgr.util : getPoolInfo, runCmd;

    bool verbose;
    bool help;

    getopt(args, "v", &verbose,
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

    enforce(executeShell(format!`zfs list %s`(esfn(dataset))).status != 0,
            format!"Error: %s already exists"(dataset));

    enforce(wait(spawnShell(format!`zfs recv%s -u %s`(verbose ? " -v" : "", esfn(dataset)))) == 0,
            "Error: zfs recv failed");

    {
        immutable cmd = format!"zfs set canmount=noauto %s"(esfn(dataset));
        if(verbose)
            stderr.writefln("\n%s", cmd);
        runCmd(cmd);
    }

    {
        immutable cmd = format!"zfs set mountpoint=/ %s"(esfn(dataset));
        if(verbose)
            stderr.writefln("\n%s", cmd);
        runCmd(cmd);
    }

    if(verbose)
        stderr.writeln("\nImport complete");

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

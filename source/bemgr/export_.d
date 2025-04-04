// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module bemgr.export_;

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

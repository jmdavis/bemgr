// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module bemgr.create;

import std.range.primitives;

int doCreate(string[] args)
{
    enum helpMsg =
`bemgr create [-e <beName> | -e <beName@snapshot>] <newBEName>

  Creates a new boot environment with the given name from the currently active
  boot environment - e.g. "bemgr foo" would create a new boot environment named
  "foo" by snapshoting the currently active boot environment and then cloning
  that snapshot.

  -e specifies the boot environment or snapshot of a boot environment to clone
     the new boot environment from rather than the currently active boot
     environment.

bemgr create <beName@snapshot>

  Creates a new snapshot - e.g. "bemgr foo@bar" would take a snapshot of foo's
  dataset and name the snapshot "bar", so if "zroot/ROOT" were the parent of the
  BE datasets, then the snapshot would be "zroot/ROOT/foo@bar".`;

    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName, executeShell;
    import std.stdio : writeln;
    import std.string : indexOf;

    import bemgr.util : createSnapshotWithTime, enforceDSExists, getPoolInfo, runCmd;

    string origin;
    bool help;

    getopt(args, config.bundling,
           "e", &origin,
           "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 3, helpMsg);

    immutable newBE = args[2];
    auto poolInfo = getPoolInfo();

    {
        immutable at = newBE.indexOf('@');

        if(at != -1)
        {
            enforce(origin.empty, "Error: -e is illegal when creating a snapshot");
            enforceDSExists(buildPath(poolInfo.beParent, newBE[0 .. at]));

            immutable snapName = newBE[at + 1 .. $];
            enforceValidName(snapName, true);
            runCmd(format!"zfs snap %s"(esfn(buildPath(poolInfo.beParent, newBE))));

            return 0;
        }
    }

    enforceValidName(newBE, false);

    immutable clone = buildPath(poolInfo.beParent, newBE);
    enforce(executeShell(format!"zfs list %s"(esfn(clone))).status != 0, format!"Error: %s already exists"(newBE));

    if(origin.empty)
        origin = createSnapshotWithTime(poolInfo.rootFS);
    else if(origin.indexOf('@') == -1)
    {
        origin = buildPath(poolInfo.beParent, origin);
        enforceDSExists(origin);
        origin = createSnapshotWithTime(origin);
    }
    else
    {
        origin = buildPath(poolInfo.beParent, origin);
        enforceDSExists(origin);
    }

    runCmd(format!"zfs clone -o canmount=noauto -o mountpoint=/ %s %s"(esfn(origin), esfn(clone)));

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

    enforceValidName(newBE, false);
    runCmd(format!"zfs rename -u %s %s"(esfn(source), esfn(target)));

    // This should never actually be necessary, but if someone has been
    // manually messing with these properties, they could be wrong, so we'll
    // set them back to make sure.
    runCmd(format!"zfs set canmount=noauto %s"(esfn(target)));
    runCmd(format!"zfs set -u mountpoint=/ %s"(esfn(target)));

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

private:

bool validName(string beName)
{
    foreach(c; beName)
    {
        switch(c)
        {
            case '0': .. case '9':
            case 'a': .. case 'z':
            case 'A': .. case 'Z':
            case '_':
            case '.':
            case ':':
            case '-': continue;
            default: return false;
        }
    }

    return true;
}

unittest
{
    import std.ascii : digits, letters;

    assert(validName(digits));
    assert(validName(letters));
    assert(validName("_.:-"));

    assert(!validName(" "));
    assert(!validName("+"));
    assert(!validName("="));
    assert(!validName("!"));
    assert(!validName("@"));
    assert(!validName("#"));
    assert(!validName("$"));
    assert(!validName("%"));
    assert(!validName("^"));
    assert(!validName("&"));
    assert(!validName("*"));
    assert(!validName("("));
    assert(!validName(")"));
    assert(!validName("?"));
    assert(!validName("|"));
    assert(!validName("/"));
    assert(!validName("\\"));
    assert(!validName("\""));
    assert(!validName("\'"));
    assert(!validName(","));
    assert(!validName(";"));
    assert(!validName("<"));
    assert(!validName(">"));
}

void enforceValidName(string name, bool snapshot)
{
    import std.exception : enforce;
    import std.format : format;

    enum allowed = `
    ASCII letters: a-z A-Z
    ASCII Digits: 0-9
    Underscore: _
    Period: .
    Colon: :
    Hypthen: -`;

    if(snapshot)
    {
        enum fmt =
`Error: Cannot create a snapshot with the name "%s".
The characters allowed in boot environment snapshots names are:` ~ allowed;

        enforce(validName(name), format!fmt(name));
    }

    enum fmt =
`Error: Cannot create a boot environment with the name "%s".
The characters allowed in boot environment names are:` ~ allowed;

    enforce(validName(name), format!fmt(name));
}

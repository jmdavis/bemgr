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
    import std.process : esfn = escapeShellFileName;
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

    enum allowed = `
    ASCII letters: a-z A-Z
    ASCII Digits: 0-9
    Underscore: _
    Period: .
    Colon: :
    Hypthen: -`;

    {
        immutable at = newBE.indexOf('@');

        if(at != -1)
        {
            enforce(origin.empty, "Error: -e is illegal when creating a snapshot");
            enforceDSExists(buildPath(poolInfo.beParent, newBE[0 .. at]));

            enum fmt =
`Error: Cannot create a snapshot with the name "%s".
The characters allowed in boot environment snapshots names are:` ~ allowed;

            enforce(validName(newBE), format!fmt(newBE));
            runCmd(format!"zfs snap %s"(esfn(buildPath(poolInfo.beParent, newBE))));

            return 0;
        }
    }

    {
        enum fmt =
`Error: Cannot create a boot environment with the name "%s".
The characters allowed in boot environment names are:` ~ allowed;

        enforce(validName(newBE), format!fmt((newBE)));
    }

    immutable clone = buildPath(poolInfo.beParent, newBE);

    if(origin.empty)
        origin = createSnapshotWithTime(poolInfo.rootFS);
    else if(origin.indexOf('@') == -1)
    {
        enforceDSExists(origin);
        origin = createSnapshotWithTime(buildPath(poolInfo.beParent, origin));
    }
    else
    {
        origin = buildPath(poolInfo.beParent, origin);
        enforceDSExists(origin);
    }

    runCmd(format!"zfs clone %s %s"(esfn(origin), esfn(clone)));
    runCmd(format!"zfs set canmount=noauto %s"(esfn(clone)));
    runCmd(format!"zfs set -u mountpoint=/ %s"(esfn(clone)));

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

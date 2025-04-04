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

    import std.datetime.date : DateTime;
    import std.datetime.systime : Clock;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;
    import std.string : indexOf;

    import bemgr.util : getPoolInfo, runCmd;

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

    {
        enum fmt =
`Error: Cannot create a boot environment with the name "%s"
The characters allowed in boot environment names are:
    ASCII letters: a-z A-Z
    ASCII Digits: 0-9
    Underscore: _
    Period: .
    Colon: :
    Hypthen: -`;

        enforce(validName(newBE), format!fmt((newBE)));
    }

    auto poolInfo = getPoolInfo();
    immutable clone = buildPath(poolInfo.beParent, newBE);

    if(origin.empty)
    {
        origin = format!"%s@%s"(poolInfo.rootFS, (cast(DateTime)Clock.currTime()).toISOExtString());
        runCmd(format!"zfs snap %s"(esfn(origin)));
    }
    else if(origin.indexOf('@') == -1)
    {
        origin = format!"%s/%s@%s"(poolInfo.beParent, origin, (cast(DateTime)Clock.currTime()).toISOExtString());
        runCmd(format!"zfs snap %s"(esfn(origin)));
    }
    else
        origin = buildPath(poolInfo.beParent, origin);

    runCmd(format!"zfs clone %s %s"(esfn(origin), esfn(clone)));
    runCmd(format!"zfs set canmount=noauto %s"(esfn(clone)));
    runCmd(format!"zfs set mountpoint=/ %s"(esfn(clone)));

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

// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module realapp;

import std.bigint : BigInt;
import std.datetime.date : DateTime, Month;
import std.range.primitives;

int realMain(string[] args)
{
    import std.exception : enforce;
    import std.getopt : GetOptException;
    import std.stdio : stderr, writeln;

    immutable helpMsg =
        "bemgr - A program for managing zfs boot environments on FreeBSD or Linux\n" ~
        "\n" ~
        "  bemgr activate <beName>\n" ~
        "  bemgr create [-e <nonActiveBE> | -e <beName@snapshot>] <beName>\n" ~
        "  bemgr create <beName@snapshot>\n" ~
        "  bemgr destroy [-F] <beName@snapshot | beName@snapshot>\n" ~
        "  bemgr list [-aHso]\n" ~
        "  bemgr mount beName <mountpoint>\n" ~
        "  bemgr rename <origBEName> <newBEName>\n" ~
        "  bemgr umount [-f <beName>]\n" ~
        "\n" ~
        "Use --help on individual commands for more information.";

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
    import std.exception : enforce;
    import std.format : format;
    import std.getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writefln, writeln;

    enum helpMsg =
    "  bemgr activate <beName>\n" ~
    "\n" ~
    "    Sets the given boot environment as the one to boot next time that the\n" ~
    "    computer is rebooted.";

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

int doCreate(string[] args)
{
    import std.algorithm.searching : canFind;
    import std.datetime.date : DateTime;
    import std.datetime.systime : Clock;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;
    import std.string : representation;

    enum helpMsg =
    "  bemgr create [-e <nonActiveBE> | -e <beName@snapshot>] <beName>\n" ~
    "\n" ~
    "    Creates a new boot environment named beName.\n" ~
    "\n" ~
    "    -e specifies the boot environment or snapshot of a boot environment to \n" ~
    "       clone the new boot environment from.";

    string origin;
    bool help;

    getopt(args, "|e", &origin,
                 "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 3, helpMsg);

    immutable newBE = args[2];

    {
        enum fmt = `Error: Cannot create a boot environment with the name "%s"` ~ "\n" ~
                   "The characters allowed in boot environment names are:\n" ~
                   "    ASCII letters: a-z A-Z" ~
                   "    ASCII Digits: 0-9" ~
                   "    Underscore: _\n" ~
                   "    Period: .\n" ~
                   "    Colon: :\n" ~
                   "    Hypthen: -";
        enforce(validName(newBE), format!fmt((newBE)));
    }

    auto poolInfo = getPoolInfo();
    immutable clone = buildPath(poolInfo.beParent, newBE);

    if(origin.empty)
    {
        origin = format!"%s@%s"(poolInfo.rootFS, (cast(DateTime)Clock.currTime()).toISOExtString());
        runCmd(format!"zfs snap %s"(esfn(origin)));
    }
    else if(!origin.representation.canFind(ubyte('@')))
    {
        origin = format!"%s@%s"(origin, (cast(DateTime)Clock.currTime()).toISOExtString());
        runCmd(format!"zfs snap %s"(esfn(origin)));
    }

    runCmd(format!"zfs clone %s %s"(esfn(origin), esfn(clone)));
    runCmd(format!"zfs set canmount=noauto %s"(esfn(clone)));
    runCmd(format!"zfs set mountpoint=/ %s"(esfn(clone)));

    return 0;
}

int doDestroy(string[] args)
{
    assert(0);
}

int doList(string[] args)
{
    import std.format : format;
    import std.getopt : getopt;
    import std.stdio : write, writeln;

    enum helpMsg =
    "bemgr list [-Ho]\n" ~
    `    Display all boot environments. The "Active" field indicates whether the ` ~ "\n" ~
    `    boot environment is active now (N); active on reboot ("R"); or both ("NR").` ~ "\n" ~
    "\n" ~
    "    -H will print headers, and it separates fields by a single tab instead of \n" ~
    "       arbitrary whitespace. Use for scripting.\n" ~
    "\n" ~
    "    --origin|-o will print out the origin snapshot for each boot environment.";


    bool noHeaders;
    bool printOrigin;
    bool help;

    getopt(args,
           "|H", &noHeaders,
           "origin|o", &printOrigin,
           "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    string[][] rows;

    if(!noHeaders)
        rows ~= ["BE", "Active", "Mountpoint", "Space", "Referenced", "Created", "Origin"];

    auto poolInfo = getPoolInfo();

    foreach(beInfo; getBEInfos(poolInfo))
    {
        string active;
        if(beInfo.dataset.name == poolInfo.rootFS)
            active = beInfo.dataset.name == poolInfo.bootFS ? "NR" : "N";
        else
            active = beInfo.dataset.name == poolInfo.bootFS ? "R" : "-";

        immutable mountpoint = beInfo.dataset.mounted ? beInfo.dataset.mountpoint : "-";

        auto originInfo = beInfo.dataset.originInfo;

        // Origins are snapshots, so they don't have reservations.
        immutable space = bytesToSize(originInfo ? originInfo.used
                                                 : beInfo.dataset.usedByDataset + beInfo.dataset.usedByRefReservation);
        immutable referenced = bytesToSize(originInfo ? originInfo.referenced : beInfo.dataset.referenced);

        string creation;
        with(beInfo.dataset.creationTime)
            creation = format!"%s-%02d-%02d %02d:%02d"(year, month, day, hour, minute);

        rows ~= [beInfo.name, active, mountpoint, space, referenced, creation, originInfo ? originInfo.name : "-"];
    }

    if(!noHeaders)
    {
        import std.algorithm.comparison : max;
        import std.algorithm.iteration : map;
        import std.array : array;

        auto colLens = rows[0].map!((a) => a.length)().array();

        foreach(row; rows[1 .. $])
        {
            foreach(i, col; row)
                colLens[i] = max(colLens[i], col.length);
        }

        foreach(l, row; rows)
        {
            foreach(c, ref col; row)
            {
                // avoid trailing whitespace
                if(c == row.length)
                    continue;

                if(col.length < colLens[c])
                {
                    auto newCol = new char[](colLens[c]);

                    // For c == 3 and c == 4, the idea is to right-justify the
                    // numbers so that they line up nicely.
                    if(c == 3 || c == 4)
                    {
                        newCol[0 .. $ - col.length] = ' ';
                        newCol[$ - col.length .. $] = col;
                    }
                    else
                    {
                        newCol[0 .. col.length] = col;
                        newCol[col.length .. $] = ' ';
                    }

                    col = cast(string)newCol;
                }
            }
        }
    }

    foreach(row; rows)
    {
        if(!printOrigin)
            --row.length;

        foreach(i; 0 .. row.length - 1)
        {
            write(row[i]);
            write(noHeaders ? "\t" : "  ");
        }
        writeln(row[$ - 1]);
    }

    return 0;
}

int doMount(string[] args)
{
    assert(0);
}

int doRename(string[] args)
{
    import std.exception : enforce;
    import std.format : format;
    import std.getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;

    enum helpMsg =
    "  bemgr rename <origBEName> <newBEName>\n" ~
    "\n" ~
    "    Renames the given boot environment.";

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

struct PoolInfo
{
    string pool;
    string rootFS;
    string bootFS;
    string beParent;

    this(string pool, string rootFS, string bootFS)
    {
        import std.path : dirName;

        this.pool = pool;
        this.rootFS = rootFS;
        this.bootFS = bootFS;
        this.beParent = rootFS.dirName;
    }
}

struct BEInfo
{
    import std.typecons : Nullable;

    string name;
    DSInfo dataset;
    DSInfo[] snapshots;
}

// Dataset / Snapshot Info
struct DSInfo
{
    string name;
    string mountpoint;
    bool mounted;

    // The space used by the dataset and its children.
    BigInt used;

    // The space used directly by the dataset.
    BigInt usedByDataset;

    // The space used by the snapshots of the dataset.
    BigInt usedBySnapshots;

    // The space used by the refreservation of this dataset.
    BigInt usedByRefReservation;

    // The space reference by the dataset but not directly contained within it.
    BigInt referenced;

    DateTime creationTime;
    string originName;
    DSInfo* originInfo;
    bool snapshot;

    enum listCmd = `zfs list -H -t filesystem,snapshot,volume ` ~
                   // These are the fields parsed in the constructor, with
                   // creation being divided up further, because it has spaces
                   // between the parts of the date/time.
                   `-o name,mountpoint,mounted,used,usedds,usedsnap,usedrefreserv,refer,creation,origin ` ~
                   `-r %s`;

    this(string line)
    {
        import std.algorithm.searching : canFind;
        import std.exception : enforce;
        import std.string : representation, split;

        auto parts = line.split();
        enforce(parts.length == 14,
                `Error: The format from "zfs list" seems to have changed from what bemgr expects`);
        this.name = parts[0];
        this.mountpoint = parts[1];
        this.mounted = parts[2] == "yes";
        this.used = parseSizeAsBytes(parts[3]);
        this.usedByDataset = parseSizeAsBytes(parts[4]);
        this.usedBySnapshots = parseSizeAsBytes(parts[5]);
        this.usedByRefReservation = parseSizeAsBytes(parts[6]);
        this.referenced = parseSizeAsBytes(parts[7]);
        //immutable dow = parts[8]; // ignored, since it's just duplicate info
        immutable month = parts[9];
        immutable day = parts[10];
        immutable time = parts[11];
        immutable year = parts[12];
        this.originName = parts[13];

        this.creationTime = parseDate(year, month, day, time);
        this.snapshot = name.representation.canFind(ubyte('@'));
    }
}

string runCmd(string cmd)
{
    import std.exception : enforce;
    import std.format : format;
    import std.process : executeShell;
    import std.string : strip;

    immutable result = executeShell(cmd);
    enforce(result.status == 0, result.output);
    return result.output.strip();
}

string runCmd(string cmd, lazy string errorMsg)
{
    import std.exception : enforce;
    import std.format : format;
    import std.process : executeShell;
    import std.string : strip;

    immutable result = executeShell(cmd);
    enforce(result.status == 0, errorMsg);
    return result.output.strip();
}

PoolInfo getPoolInfo()
{
    import std.algorithm.searching : find, startsWith;
    import std.exception : enforce;
    import std.format : format;
    import std.process : escapeShellFileName;

    immutable rootFS = runCmd(`mount | awk '/ \/ / {print $1}'`, "Failed to get the root filesystem");
    enforce(!rootFS.startsWith("/dev"), "Error: This system does not boot from a ZFS pool");

    auto found = rootFS.find('/');
    enforce(!found.empty, "This system is not configured for boot environments");
    immutable pool = rootFS[0 .. rootFS.length - found.length];

    immutable bootFS = runCmd(format!`zpool get -H -o value bootfs %s`(escapeShellFileName(pool)),
                              format!"Error: ZFS boot pool '%s' has unset 'bootfs' property"(pool));

    return PoolInfo(pool, rootFS, bootFS);
}

BEInfo[] getBEInfos(PoolInfo poolInfo)
{
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : countUntil, find, startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.exception : enforce;
    import std.format : format;
    import std.process : escapeShellFileName;
    import std.range : chain, only;
    import std.string : representation, splitLines;

    immutable result = runCmd(format!(DSInfo.listCmd)(escapeShellFileName(poolInfo.beParent)),
                              "Error: Failed to get the list of boot environments");
    auto dsInfos = result.splitLines().map!DSInfo().filter!(a => a.name != poolInfo.beParent)().array();

    BEInfo[] retval;

    foreach(dsInfo; dsInfos)
    {
        if(dsInfo.snapshot)
            continue;

        BEInfo beInfo;
        beInfo.name = dsInfo.name[poolInfo.beParent.length + 1 .. $];
        beInfo.dataset = dsInfo;

        foreach(other; dsInfos)
        {
            if(other.name.representation.startsWith(chain(dsInfo.name, only(ubyte('@')))))
                beInfo.snapshots ~= other;
        }

        beInfo.snapshots.sort!((a, b) => a.creationTime < b.creationTime)();

        retval ~= beInfo;
    }

    retval.sort!((a, b) => a.dataset.creationTime < b.dataset.creationTime)();

    foreach(ref beInfo; retval)
    {
        if(beInfo.dataset.originName != "-")
        {
            immutable origin = beInfo.dataset.originName;
            auto originBE = retval.find!(a => a.dataset.name == origin[0 .. origin.representation.countUntil(ubyte('@'))])();
            enforce(!originBE.empty, format!"Error: Failed to find dataset for %s"(origin));

            auto originSnapshot = originBE.front.snapshots.find!(a => a.name == origin)();
            enforce(!originSnapshot.empty, format!"Error: Failed to find %s"(origin));

            beInfo.dataset.originInfo = &originSnapshot.front;
        }
    }

    return retval;
}

// Realistically, using BigInt is overkill, since boot pools generally aren't
// going to reach beyond the terabytes, and anyone storing large amounts of
// data will have it on a separate pool, but beadm apparently supports through
// zettabytes, so we're doing it here for consistency. And it isn't much more
// complex than just using ulong.
enum Units : BigInt
{
    bytes = BigInt(1),
    kilobytes = BigInt(1024),
    megabytes = BigInt(1048576),
    gigabytes = BigInt(1073741824),
    terabytes = BigInt(1099511627776UL),
    petabytes = BigInt(1125899906842624UL),
    exabytes = BigInt(1152921504606846976UL),
    zettabytes = BigInt("1180591620717411303424")
}

BigInt parseSizeAsBytes(string size)
{
    import std.algorithm.searching : all, find;
    import std.ascii : isDigit;
    import std.conv : to;
    import std.exception : enforce;
    import std.math : pow;
    import std.format : format;
    import std.range : take;

    if(size == "-")
        return BigInt();

    BigInt mul;

    switch(size[$ - 1])
    {
        case 'B': mul = Units.bytes; break;
        case 'K': mul = Units.kilobytes; break;
        case 'M': mul = Units.megabytes; break;
        case 'G': mul = Units.gigabytes; break;
        case 'T': mul = Units.terabytes; break;
        case 'P': mul = Units.petabytes; break;
        case 'E': mul = Units.exabytes; break;
        case 'Z': mul = Units.zettabytes; break;
        default: throw new Exception(format!"Error: Unexpected format for size of dataset or snapshot: %s"(size));
    }

    auto num = size[0 .. $ - 1];
    auto found = num.find(".");
    auto whole = num[0 .. num.length - found.length];
    auto decimal = found.empty ? "" : found[1 .. $];

    enforce(!whole.empty &&
            whole.all!isDigit() &&
            (found.empty || (!decimal.empty && decimal.all!isDigit())),
            format!"Error: Unexpected format for size of dataset or snapshot: %s"(size));

    auto retval = BigInt(whole) * mul;

    if(decimal.empty)
        return retval;

    if(decimal.length == 1)
        return retval + mul * to!ubyte(decimal.take(1)) / 10;

    return retval + mul * to!ubyte(decimal.take(2)) / 100;
}

unittest
{
    import std.exception : assertThrown;
    import std.math : pow;

    assert(parseSizeAsBytes("-") == 0);

    assert(parseSizeAsBytes("0B") == 0);
    assert(parseSizeAsBytes("0K") == 0);
    assert(parseSizeAsBytes("0M") == 0);
    assert(parseSizeAsBytes("0G") == 0);
    assert(parseSizeAsBytes("0T") == 0);
    assert(parseSizeAsBytes("0P") == 0);
    assert(parseSizeAsBytes("0E") == 0);
    assert(parseSizeAsBytes("0Z") == 0);

    assert(parseSizeAsBytes("0.0B") == 0);
    assert(parseSizeAsBytes("0.0K") == 0);
    assert(parseSizeAsBytes("0.0M") == 0);
    assert(parseSizeAsBytes("0.0G") == 0);
    assert(parseSizeAsBytes("0.0T") == 0);
    assert(parseSizeAsBytes("0.0P") == 0);
    assert(parseSizeAsBytes("0.0E") == 0);
    assert(parseSizeAsBytes("0.0Z") == 0);

    assert(parseSizeAsBytes("0.00123456789B") == 0);
    assert(parseSizeAsBytes("0.00123456789K") == 0);
    assert(parseSizeAsBytes("0.00123456789M") == 0);
    assert(parseSizeAsBytes("0.00123456789G") == 0);
    assert(parseSizeAsBytes("0.00123456789T") == 0);
    assert(parseSizeAsBytes("0.00123456789P") == 0);
    assert(parseSizeAsBytes("0.00123456789E") == 0);
    assert(parseSizeAsBytes("0.00123456789Z") == 0);

    assert(parseSizeAsBytes("0.0123456789B") == 0);
    assert(parseSizeAsBytes("0.0123456789K") == 10);
    assert(parseSizeAsBytes("0.0123456789M") == 10485UL);
    assert(parseSizeAsBytes("0.0123456789G") == 10737418UL);
    assert(parseSizeAsBytes("0.0123456789T") == 10995116277UL);
    assert(parseSizeAsBytes("0.0123456789P") == 11258999068426UL);
    assert(parseSizeAsBytes("0.0123456789E") == 11529215046068469UL);
    assert(parseSizeAsBytes("0.0123456789Z") == 11805916207174113034UL);

    assert(parseSizeAsBytes("0.019B") == 0);
    assert(parseSizeAsBytes("0.019K") == 10);
    assert(parseSizeAsBytes("0.019M") == 10485UL);
    assert(parseSizeAsBytes("0.019G") == 10737418UL);
    assert(parseSizeAsBytes("0.019T") == 10995116277UL);
    assert(parseSizeAsBytes("0.019P") == 11258999068426UL);
    assert(parseSizeAsBytes("0.019E") == 11529215046068469UL);
    assert(parseSizeAsBytes("0.019Z") == 11805916207174113034UL);

    assert(parseSizeAsBytes("1.2B") == 1);
    assert(parseSizeAsBytes("1.2K") == 1228UL);
    assert(parseSizeAsBytes("1.2M") == 1258291UL);
    assert(parseSizeAsBytes("1.2G") == 1288490188UL);
    assert(parseSizeAsBytes("1.2T") == 1319413953331UL);
    assert(parseSizeAsBytes("1.2P") == 1351079888211148UL);
    assert(parseSizeAsBytes("1.2E") == 1383505805528216371UL);
    assert(parseSizeAsBytes("1.2Z") == BigInt("1416709944860893564108"));

    assert(parseSizeAsBytes("1.27B") == 1);
    assert(parseSizeAsBytes("1.27K") == 1300UL);
    assert(parseSizeAsBytes("1.27M") == 1331691UL);
    assert(parseSizeAsBytes("1.27G") == 1363652116UL);
    assert(parseSizeAsBytes("1.27T") == 1396379767275UL);
    assert(parseSizeAsBytes("1.27P") == 1429892881690132UL);
    assert(parseSizeAsBytes("1.27E") == 1464210310850695659UL);
    assert(parseSizeAsBytes("1.27Z") == BigInt("1499351358311112355348"));

    assert(parseSizeAsBytes("123456789.0B") == BigInt("123456789"));
    assert(parseSizeAsBytes("123456789.0K") == BigInt("126419751936"));
    assert(parseSizeAsBytes("123456789.0M") == BigInt("129453825982464"));
    assert(parseSizeAsBytes("123456789.0G") == BigInt("132560717806043136"));
    assert(parseSizeAsBytes("123456789.0T") == BigInt("135742175033388171264"));
    assert(parseSizeAsBytes("123456789.0P") == BigInt("138999987234189487374336"));
    assert(parseSizeAsBytes("123456789.0E") == BigInt("142335986927810035071320064"));
    assert(parseSizeAsBytes("123456789.0Z") == BigInt("145752050614077475913031745536"));

    assert(parseSizeAsBytes("123456789.7B") == BigInt("123456789"));
    assert(parseSizeAsBytes("123456789.7K") == BigInt("126419752652"));
    assert(parseSizeAsBytes("123456789.7M") == BigInt("129453826716467"));
    assert(parseSizeAsBytes("123456789.7G") == BigInt("132560718557662412"));
    assert(parseSizeAsBytes("123456789.7T") == BigInt("135742175803046310707"));
    assert(parseSizeAsBytes("123456789.7P") == BigInt("138999988022319422164172"));
    assert(parseSizeAsBytes("123456789.7E") == BigInt("142335987734855088296112947"));
    assert(parseSizeAsBytes("123456789.7Z") == BigInt("145752051440491610415219657932"));

    assertThrown(parseSizeAsBytes("0.0"));
    assertThrown(parseSizeAsBytes("B"));
    assertThrown(parseSizeAsBytes(".0B"));
    assertThrown(parseSizeAsBytes("0.B"));
    assertThrown(parseSizeAsBytes("0.0W"));
    assertThrown(parseSizeAsBytes("0.0 B"));
    assertThrown(parseSizeAsBytes("0.0B "));
}

string bytesToSize(BigInt bytes)
{
    import std.ascii : toUpper;
    import std.format : format;
    import std.traits : EnumMembers;

    alias names = __traits(allMembers, Units);
    alias values = EnumMembers!Units;

    foreach(i, e; values)
    {
        static if(i < names.length - 1)
            immutable cond = bytes < values[i + 1];
        else
            immutable cond = true;

        if(cond)
        {
            auto first = bytes * 100 / e;
            auto whole = first / 100;
            auto decimal = first % 100;
            if(decimal == 0)
                return format!`%s%s`(whole, names[i][0].toUpper());
            if(decimal % 10 == 0)
                return format!`%s.%s%s`(whole, decimal / 10, names[i][0].toUpper());
            return format!`%s.%02d%s`(whole, decimal, names[i][0].toUpper());
        }
    }
}

unittest
{
    import std.math : pow;

    assert(bytesToSize(BigInt(0)) == "0B");
    assert(bytesToSize(BigInt(pow(1024UL, 1))) == "1K");
    assert(bytesToSize(BigInt(pow(1024UL, 2))) == "1M");
    assert(bytesToSize(BigInt(pow(1024UL, 3))) == "1G");
    assert(bytesToSize(BigInt(pow(1024UL, 4))) == "1T");
    assert(bytesToSize(BigInt(pow(1024UL, 5))) == "1P");
    assert(bytesToSize(BigInt(pow(1024UL, 6))) == "1E");
    assert(bytesToSize(BigInt(pow(1024UL, 6)) * BigInt(1024UL)) == "1Z");

    assert(bytesToSize(BigInt(pow(1024UL, 1) * 5) + 10) == "5K");
    assert(bytesToSize(BigInt(pow(1024UL, 2) * 5) + pow(1024UL, 1) * 10) == "5M");
    assert(bytesToSize(BigInt(pow(1024UL, 3) * 5) + pow(1024UL, 2) * 10) == "5G");
    assert(bytesToSize(BigInt(pow(1024UL, 4) * 5) + pow(1024UL, 3) * 10) == "5T");
    assert(bytesToSize(BigInt(pow(1024UL, 5) * 5) + pow(1024UL, 4) * 10) == "5P");
    assert(bytesToSize(BigInt(pow(1024UL, 6) * 5) + pow(1024UL, 5) * 10) == "5E");
    assert(bytesToSize(BigInt(pow(1024UL, 6)) * BigInt(1024UL) * 5 + pow(1024, 5) * 10) == "5Z");

    assert(bytesToSize(BigInt(pow(1024UL, 1) * 5) + 11) == "5.01K");
    assert(bytesToSize(BigInt(pow(1024UL, 2) * 5) + pow(1024UL, 1) * 11) == "5.01M");
    assert(bytesToSize(BigInt(pow(1024UL, 3) * 5) + pow(1024UL, 2) * 11) == "5.01G");
    assert(bytesToSize(BigInt(pow(1024UL, 4) * 5) + pow(1024UL, 3) * 11) == "5.01T");
    assert(bytesToSize(BigInt(pow(1024UL, 5) * 5) + pow(1024UL, 4) * 11) == "5.01P");
    assert(bytesToSize(BigInt(pow(1024UL, 6) * 5) + pow(1024UL, 5) * 11) == "5.01E");
    assert(bytesToSize(BigInt(pow(1024UL, 6)) * BigInt(1024UL) * 5 + (BigInt(pow(1024UL, 6)) * 11)) == "5.01Z");

    assert(bytesToSize(BigInt(pow(1024UL, 1) * 5) + 103) == "5.1K");
    assert(bytesToSize(BigInt(pow(1024UL, 2) * 5) + pow(1024UL, 1) * 103) == "5.1M");
    assert(bytesToSize(BigInt(pow(1024UL, 3) * 5) + pow(1024UL, 2) * 103) == "5.1G");
    assert(bytesToSize(BigInt(pow(1024UL, 4) * 5) + pow(1024UL, 3) * 103) == "5.1T");
    assert(bytesToSize(BigInt(pow(1024UL, 5) * 5) + pow(1024UL, 4) * 103) == "5.1P");
    assert(bytesToSize(BigInt(pow(1024UL, 6) * 5) + pow(1024UL, 5) * 103) == "5.1E");
    assert(bytesToSize(BigInt(pow(1024UL, 6)) * BigInt(1024UL) * 5 + (BigInt(pow(1024UL, 6)) * 103)) == "5.1Z");

    assert(bytesToSize(BigInt(pow(1024UL, 1) * 5) + 134) == "5.13K");
    assert(bytesToSize(BigInt(pow(1024UL, 2) * 5) + pow(1024UL, 1) * 134) == "5.13M");
    assert(bytesToSize(BigInt(pow(1024UL, 3) * 5) + pow(1024UL, 2) * 134) == "5.13G");
    assert(bytesToSize(BigInt(pow(1024UL, 4) * 5) + pow(1024UL, 3) * 134) == "5.13T");
    assert(bytesToSize(BigInt(pow(1024UL, 5) * 5) + pow(1024UL, 4) * 134) == "5.13P");
    assert(bytesToSize(BigInt(pow(1024UL, 6) * 5) + pow(1024UL, 5) * 134) == "5.13E");
    assert(bytesToSize(BigInt(pow(1024UL, 6)) * BigInt(1024UL) * 5 + (BigInt(pow(1024UL, 6)) * 134)) == "5.13Z");

    assert(bytesToSize(BigInt(pow(1024UL, 1) * 8) - 1) == "7.99K");
    assert(bytesToSize(BigInt(pow(1024UL, 2) * 8) - 1) == "7.99M");
    assert(bytesToSize(BigInt(pow(1024UL, 3) * 8) - 1) == "7.99G");
    assert(bytesToSize(BigInt(pow(1024UL, 4) * 8) - 1) == "7.99T");
    assert(bytesToSize(BigInt(pow(1024UL, 5) * 8) - 1) == "7.99P");
    assert(bytesToSize(BigInt(pow(1024UL, 6) * 8) - 1) == "7.99E");
    assert(bytesToSize(BigInt(pow(1024UL, 6)) * BigInt(1024UL) * 8 - 1) == "7.99Z");
}

DateTime parseDate(string year, string month, string day, string time)
{
    import std.algorithm.searching : find;
    import std.conv : ConvException, to;
    import std.datetime : DateTimeException, TimeOfDay;
    import std.exception : enforce;
    import std.format : format;
    import std.range : takeOne;

    try
    {
        DateTime retval;
        retval.year = to!int(year);
        retval.month = parseMonth(month);
        retval.day = to!int(day);
        retval.timeOfDay = TimeOfDay.fromISOExtString(format!"%s%s:00"(time.length == 4 ? "0" : "", time));

        return retval;
    }
    catch(ConvException)
    {
        enum fmt = "Error: Unexpected format for creation date of dataset or snapshot: %s %s %s %s";
        throw new Exception(format!fmt(month, day, time, year));
    }
    catch(DateTimeException)
    {
        enum fmt = "Error: Creation date/time of dataset or snapshot is an invalid date/time: %s %s %s %s";
        throw new Exception(format!fmt(month, day, time, year));
    }
}

unittest
{
    import core.exception : AssertError;
    import std.exception : assertThrown, enforce;

    void test(string year, string month, string day, string time, DateTime expected, size_t line = __LINE__)
    {
        enforce!AssertError(parseDate(year, month, day, time) == expected, "unittest failure", __FILE__, line);
    }

    test("2023", "Oct", "14", "23:33", DateTime(2023, 10, 14, 23, 33));
    test("2024", "Sep", "23", "6:06", DateTime(2024, 9, 23, 6, 6));
    test("2025", "Feb", "9", "9:48", DateTime(2025, 2, 9, 9, 48));
    test("2025", "Mar", "19", "05:07", DateTime(2025, 3, 19, 5, 7));

    assertThrown(parseDate("2025", "Feb", "29", "9:48"));
    assertThrown(parseDate("2022", "dec", "29", "9:48"));
    assertThrown(parseDate("Feb", "Feb", "9", "9:48"));
    assertThrown(parseDate("2025", "2025", "9", "9:48"));
    assertThrown(parseDate("2025", "Feb", "Feb", "9:48"));
    assertThrown(parseDate("2025", "Feb", "9", "Feb"));
    assertThrown(parseDate("2025", "Feb", "9", "29:48"));
    assertThrown(parseDate("2025", "Feb", "9", ":48"));
    assertThrown(parseDate("2025", "Feb", "9", ":489"));
}

Month parseMonth(string month)
{
    import std.conv : ConvException;
    import std.format : format;
    import std.string : capitalize;

    switch(month)
    {
        foreach(e; __traits(allMembers, Month))
            mixin(format!`case "%s": return Month.%s;`(e.capitalize(), e));
        default: throw new ConvException("Failed to convert month string to a Month");
    }
}

unittest
{
    import std.exception : assertThrown;

    assert(parseMonth("Jan") == Month.jan);
    assert(parseMonth("Feb") == Month.feb);
    assert(parseMonth("Mar") == Month.mar);
    assert(parseMonth("Apr") == Month.apr);
    assert(parseMonth("May") == Month.may);
    assert(parseMonth("Jun") == Month.jun);
    assert(parseMonth("Jul") == Month.jul);
    assert(parseMonth("Aug") == Month.aug);
    assert(parseMonth("Sep") == Month.sep);
    assert(parseMonth("Oct") == Month.oct);
    assert(parseMonth("Nov") == Month.nov);
    assert(parseMonth("Dec") == Month.dec);

    assertThrown(parseMonth("jan"));
    assertThrown(parseMonth("feb"));
    assertThrown(parseMonth("mar"));
    assertThrown(parseMonth("apr"));
    assertThrown(parseMonth("may"));
    assertThrown(parseMonth("jun"));
    assertThrown(parseMonth("jul"));
    assertThrown(parseMonth("aug"));
    assertThrown(parseMonth("sep"));
    assertThrown(parseMonth("oct"));
    assertThrown(parseMonth("nov"));
    assertThrown(parseMonth("dec"));

    assertThrown(parseMonth("jAn"));
    assertThrown(parseMonth("fEb"));
    assertThrown(parseMonth("mAr"));
    assertThrown(parseMonth("aPr"));
    assertThrown(parseMonth("mAy"));
    assertThrown(parseMonth("jUn"));
    assertThrown(parseMonth("jUl"));
    assertThrown(parseMonth("aUg"));
    assertThrown(parseMonth("sEp"));
    assertThrown(parseMonth("oCt"));
    assertThrown(parseMonth("nOv"));
    assertThrown(parseMonth("dEc"));

    assertThrown(parseMonth("jaN"));
    assertThrown(parseMonth("feB"));
    assertThrown(parseMonth("maR"));
    assertThrown(parseMonth("apR"));
    assertThrown(parseMonth("maY"));
    assertThrown(parseMonth("juN"));
    assertThrown(parseMonth("juL"));
    assertThrown(parseMonth("auG"));
    assertThrown(parseMonth("seP"));
    assertThrown(parseMonth("ocT"));
    assertThrown(parseMonth("noV"));
    assertThrown(parseMonth("deC"));

    assertThrown(parseMonth("JAN"));
    assertThrown(parseMonth("FEB"));
    assertThrown(parseMonth("MAR"));
    assertThrown(parseMonth("APR"));
    assertThrown(parseMonth("MAY"));
    assertThrown(parseMonth("JUN"));
    assertThrown(parseMonth("JUL"));
    assertThrown(parseMonth("AUG"));
    assertThrown(parseMonth("SEP"));
    assertThrown(parseMonth("OCT"));
    assertThrown(parseMonth("NOV"));
    assertThrown(parseMonth("DEC"));
}

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

bool isMounted(string dataset)
{
    import std.algorithm.searching : find, startsWith;
    import std.format : format;
    import std.string : representation, splitLines;

    // Unfortunately, datasets mounted with mount -t zfs don't seem to show up
    // as mounted in the zfs properties. So, we have to use the mount command to
    // get that information so that we can know for sure whether it's actually
    // mounted or not.

    auto mountLines = runCmd("mount", format!"Error: Failed to determine whether %s was mounted"(dataset)).splitLines();
    immutable lineStart = format!"%s on "(dataset).representation;

    return !mountLines.find!(a => a.representation.startsWith(lineStart)).empty;
}

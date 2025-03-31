// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module bemgr.list;

import std.range.primitives;

import bemgr.util : PoolInfo;

int doList(string[] args)
{
    enum helpMsg =
`bemgr list [-Ho]
  Display all boot environments. The "Active" field indicates whether the
  boot environment is active now (N); active on reboot ("R"); or both ("NR").

  -H will print headers, and it separates fields by a single tab instead of
     arbitrary whitespace. Use for scripting.

  --origin | -o will print out the origin snapshot for each boot environment.`;

    import std.format : format;
    import std.getopt : getopt;
    import std.stdio : write, writeln;

    import bemgr.util : bytesToSize, getPoolInfo;

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
            creation = format!"%s-%02d-%02d %02d:%02d:%02d"(year, month, day, hour, minute, second);

        rows ~= [beInfo.name, active, mountpoint, space, referenced, creation, beInfo.dataset.originName];
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

private:

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
    import std.bigint : BigInt;
    import std.datetime : DateTime;

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

    enum listCmd = `zfs list -Hpt filesystem,snapshot,volume ` ~
                   // These are the fields parsed in the constructor
                   `-o name,mountpoint,mounted,used,usedds,usedsnap,usedrefreserv,refer,creation,origin ` ~
                   `-r %s`;

    this(string line)
    {
        import std.algorithm.searching : canFind;
        import std.exception : enforce;
        import std.string : representation, split;

        import bemgr.util : parseDate, parseSize;

        auto parts = line.split();
        enforce(parts.length == 10,
                `Error: The format from "zfs list" seems to have changed from what bemgr expects`);

        this.name = parts[0];
        this.mountpoint = parts[1];
        this.mounted = parts[2] == "yes";
        this.used = parseSize(parts[3], "used");
        this.usedByDataset = parseSize(parts[4], "usedds");
        this.usedBySnapshots = parseSize(parts[5], "usedsnap");
        this.usedByRefReservation = parseSize(parts[6], "usedrefreserv");
        this.referenced = parseSize(parts[7], "refer");
        this.creationTime = parseDate(parts[8]);
        this.originName = parts[9];

        this.snapshot = name.representation.canFind(ubyte('@'));
    }
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

    import bemgr.util : runCmd;

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
            if(other.name.representation.startsWith(chain(dsInfo.name.representation, only(ubyte('@')))))
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

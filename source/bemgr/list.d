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
`bemgr list [-a] [-H] [-s]
  Display all boot environments. The "Active" field indicates whether the
  boot environment is active now (N); active on reboot ("R"); or both ("NR").

  -a will print out the datesets and origins for each boot environment.

  -H will not print headers, and it separates fields by a single tab instead of
     arbitrary whitespace. Used for scripting.

  -s will print out the snapshots each boot environment (it implies -a).`;

    import std.datetime.date : DateTime;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.stdio : write, writeln;

    import bemgr.util : bytesToSize, getPoolInfo;

    bool all;
    bool noHeaders;
    bool snapshots;
    bool help;

    getopt(args, config.bundling,
           "a", &all,
           "H", &noHeaders,
           "s", &snapshots,
           "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 2, helpMsg);

    if(snapshots)
        all = true;

    string[][] rows;
    bool[] rightJustify;

    if(!noHeaders)
    {
        if(all)
        {
            rows ~= ["BE/Dataset/Snapshot", "Active", "Mountpoint", "Space", "Referenced", "Created"];
            rows ~= [""];
            rightJustify = [false, false, false, true, true, false];
        }
        else
        {
            rows ~= ["BE", "Active", "Mountpoint", "Space", "Referenced", "If Last", "Created"];
            rightJustify = [false, false, false, true, true, true, false];
        }
    }

    auto poolInfo = getPoolInfo();
    auto beInfos = getBEInfos(poolInfo);

    static string creationToString(DateTime dt)
    {
        return format!"%s-%02d-%02d %02d:%02d:%02d"(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    }

    foreach(i, beInfo; beInfos)
    {
        if(all)
            rows ~= [beInfo.name];

        {
            string active;
            if(beInfo.dataset.name == poolInfo.rootFS)
                active = beInfo.dataset.name == poolInfo.bootFS ? "NR" : "N";
            else
                active = beInfo.dataset.name == poolInfo.bootFS ? "R" : "-";

            immutable mountpoint = beInfo.dataset.mounted ? beInfo.dataset.mountpoint : "-";
            immutable space = bytesToSize(beInfo.space);
            immutable referenced = bytesToSize(beInfo.referenced);
            immutable creation = creationToString(beInfo.dataset.creationTime);

            if(all)
                rows ~= ["  " ~ beInfo.dataset.name, active, mountpoint, space, referenced, creation];
            else
            {
                immutable ifLast = bytesToSize(beInfo.ifLast);
                rows ~= [beInfo.name, active, mountpoint, space, referenced, ifLast, creation];
            }
        }

        if(all)
        {
            if(auto originInfo = beInfo.dataset.originInfo)
            {
                enum active = "-";
                enum mountpoint = "-";
                immutable space = bytesToSize(originInfo.used);
                immutable referenced = bytesToSize(originInfo.referenced);
                immutable creation = creationToString(originInfo.creationTime);
                rows ~= ["    " ~ originInfo.name, active, mountpoint, space, referenced, creation];
            }

            if(snapshots)
            {
                foreach(snap; beInfo.snapshots)
                {
                    enum active = "-";
                    enum mountpoint = "-";
                    immutable space = bytesToSize(snap.used);
                    immutable referenced = bytesToSize(snap.referenced);
                    immutable creation = creationToString(snap.creationTime);
                    rows ~= ["  " ~ snap.name, active, mountpoint, space, referenced, creation];
                }
            }

            if(i != beInfos.length - 1)
                rows ~= [""];
        }
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

                    // The idea is to right-justify the disk space numbers so
                    // that they line up nicely.
                    if(rightJustify[c])
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
    import std.bigint : BigInt;

    string name;
    DSInfo dataset;
    DSInfo[] snapshots;

    // The space that the dataset takes up on its own.
    // For clones, this is used of the dataset + used of the origin snapshot
    // Otherwise, it's used of the dataset.
    BigInt space;

    // The space that the dataset references.
    // For clones, this is referenced of the dataset + references of the origin
    // snapshot.
    // Otherwise, it's referenced of the dataset.
    BigInt referenced;

    // The space that the boot environment would take up if all of the other
    // boot environments (and their clones) were destroyed.
    BigInt ifLast;
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
    import std.algorithm.searching : find, startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.exception : enforce;
    import std.format : format;
    import std.process : escapeShellFileName;
    import std.range : chain, only;
    import std.string : indexOf, representation, splitLines;

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

    BEInfo*[string] snapshotToCloneBE;

    foreach(ref beInfo; retval)
    {
        beInfo.space += beInfo.dataset.used;
        beInfo.referenced = beInfo.dataset.referenced;

        if(beInfo.dataset.originName != "-")
        {
            immutable origin = beInfo.dataset.originName;
            auto originBE = retval.find!(a => a.dataset.name == origin[0 .. origin.indexOf('@')])();
            enforce(!originBE.empty, format!"Error: Failed to find dataset for %s"(origin));

            auto originSnapshot = originBE.front.snapshots.find!(a => a.name == origin)();
            enforce(!originSnapshot.empty, format!"Error: Failed to find %s"(origin));

            beInfo.dataset.originInfo = &originSnapshot.front;
            snapshotToCloneBE[originSnapshot.front.name] = &beInfo;

            beInfo.space += beInfo.dataset.originInfo.used;
        }
    }

    foreach(ref beInfo; retval)
    {
        beInfo.ifLast += beInfo.dataset.usedByDataset + beInfo.dataset.usedByRefReservation;

        foreach(i, snap; beInfo.snapshots)
        {
            if(auto cloneBE = snap.name in snapshotToCloneBE)
            {
                // The snapshots which would be moved over to the clone if it
                // were promoted. The snapshots were sorted by creation time
                // above, so the ones before i are older than the origin
                // snapshot.
                foreach(s; beInfo.snapshots[0 .. i])
                {
                    // The snapshots which are the origins for other clones
                    // would be destroyed with those clones, so they aren't
                    // counted.
                    if(s.name !in snapshotToCloneBE)
                        (*cloneBE).ifLast += s.used;
                }
                (*cloneBE).ifLast += snap.referenced;
            }
            else
                beInfo.ifLast += snap.used;
        }
    }

    return retval;
}

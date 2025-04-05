// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module bemgr.destroy;

import std.range.primitives;

import bemgr.util : PoolInfo;

int doDestroy(string[] args)
{
    enum helpMsg =
`bemgr destroy [-n] [-F] <beName>

  Destroys the given boot environment.

  If any of the boot environment's snapshots are the origin of another dataset,
  then the newest dataset of the newest snapshot will be promoted.
  If the boot environment has an origin (and thus is a clone), and that origin
  is not the origin of another dataset, then the origin will also be destroyed.

  Note that unlike beadm, there is no confirmation.

  -n Do a dry run. This will print out what would be destroyed and what
     what would be promoted if -n were not used.

  -F will forcefully unmount the dataset and any of its snapshots which are
     mounted. So, it will be unmounted even it is in use.

bemgr destroy [-n] [-F] <beName@snapshot>

  Destroys the given snapshot.

  If the snapshot is the origin of a dataset, then the result will be an error
  and nothing will be destroyed.

  Note that unlike beadm, there is no confirmation.

  -n same as above

  -F same as above`;

    import std.algorithm.iteration : splitter;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writefln, writeln;
    import std.string : indexOf, lineSplitter;

    import bemgr.util : enforceDSExists, getPoolInfo, runCmd;

    bool dryRun;
    bool force;
    bool help;

    getopt(args, config.bundling,
           "n", &dryRun,
           "f", &force,
           "help", &help);

    if(help)
    {
        writeln(helpMsg);
        return 0;
    }

    enforce(args.length == 3, helpMsg);

    immutable toDestroy = args[2];
    auto poolInfo = getPoolInfo();

    if(toDestroy.indexOf('@') != -1)
    {
        immutable snapName = buildPath(poolInfo.beParent, toDestroy);
        enforceDSExists(snapName);

        immutable result = runCmd(format!"zfs list -Ho clones %s"(esfn(snapName)),
                                  "Error: Failed to get the list of clones");
        enforce(result == "-",
                format!"Error: %s is the origin of:\n%-(%s\n%)"(snapName, result.splitter(',')));

        if(dryRun)
            writefln("Snapshot to destroy: %s", snapName);
        else
            runCmd(format!"zfs destroy%s %s"(force ? " -f" : "", esfn(snapName)));

        return 0;
    }

    immutable datasetName = buildPath(poolInfo.beParent, toDestroy);
    enforce(poolInfo.rootFS != datasetName, format!"Error: %s is the active boot environment"(toDestroy));

    auto di = getDestroyInfo(poolInfo, toDestroy);

    if(dryRun)
    {
        if(!di.toPromote.empty)
        {
            writeln("Clones to be Promoted:");
            foreach(e; di.toPromote)
                writefln("  %s", e);
            writeln();
        }

        if(!di.origin.empty)
        {
            writeln("Origin Snapshot to be Destroyed:");
            writefln("  %s\n", di.origin);
        }

        writeln("Dataset (and its Snapshots) to be Destroyed:");
        writefln("  %s", di.dataset);
    }
    else
    {
        foreach(e; di.toPromote)
            runCmd(format!"zfs promote %s"(esfn(e)));
        runCmd(format!"zfs destroy%s -r %s"(force ? " -f" : "", esfn(di.dataset)));
        if(!di.origin.empty)
            runCmd(format!"zfs destroy%s %s"(force ? " -f" : "", esfn(di.origin)));
    }

    return 0;
}

private:

struct DestroyInfo
{
    string dataset;
    string origin;
    string[] toPromote;
}

// Dataset / Snapshot Info
struct DSInfo
{
    import std.datetime.date : DateTime;
    import std.typecons : Nullable;

    string name;
    string originName;
    DateTime creationTime;

    // Only for snapshots.
    string parent;
    string[] clones;

    enum listCmd = `zfs list -Hpt filesystem,snapshot ` ~
                   // These are the fields parsed in the constructor.
                   `-o name,creation,origin,clones -r %s`;

    this(string line)
    {
        import std.algorithm.iteration : filter, splitter;
        import std.array : array;
        import std.exception : enforce;
        import std.string : indexOf;

        import bemgr.util : parseDate;

        auto parts = line.splitter('\t');
        string next(bool last)
        {
            immutable retval = parts.front;
            parts.popFront();
            enforce(parts.empty == last,
                    `Error: The format from "zfs list" seems to have changed from what bemgr expects`);
            return retval;
        }
        this.name = next(false);
        this.creationTime = parseDate(next(false));
        this.originName = next(false);
        this.clones = next(true).splitter(',').filter!(a => a != "-")().array();

        immutable at = name.indexOf('@');
        if(at != -1)
            this.parent = name[0 .. at];
    }
}

DestroyInfo getDestroyInfo(PoolInfo poolInfo, string beName)
{
    import std.algorithm.iteration : filter, map, splitter;
    import std.algorithm.sorting : sort;
    import std.exception : enforce;
    import std.format : format;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.range : walkLength;
    import std.string : lineSplitter;

    import bemgr.util : runCmd;

    immutable datasetName = buildPath(poolInfo.beParent, beName);
    DSInfo dataset;
    DSInfo[] snapshots;

    {
        immutable result = runCmd(format!(DSInfo.listCmd)(esfn(datasetName)),
                                  "Error: Failed to get the list of datasets and snapshots");

        foreach(e; result.lineSplitter().map!DSInfo())
        {
            if(e.name == datasetName)
                dataset = e;
            else if(e.parent == datasetName)
                snapshots ~= e;
            else
                throw new Exception(format!"Error: %s has child datasets"(datasetName));
        }
    }

    snapshots.sort!((a, b) => a.creationTime > b.creationTime)();

    auto retval = DestroyInfo(dataset.name);

    if(dataset.originName != "-")
    {
        immutable result = runCmd(format!"zfs list -Ho clones %s"(esfn(dataset.originName)),
                                  "Error: Failed to get the list of clones");
        auto clones = result.splitter(',').filter!(a => a != "-")();
        immutable numClones = walkLength(clones);
        enforce(numClones > 0, "Error: Encountered logic bug getting information on clones");
        if(walkLength(clones) == 1)
            retval.origin = dataset.originName;
    }

    foreach(i, snap; snapshots)
    {
        if(!snap.clones.empty)
        {
            retval.toPromote ~= snap.clones.front;

            // Realistically, there should only be one snapshot with a given
            // creation time on a dataset, but AFAIK, that's not guaranteeed,
            // since snapshots are near instantaneous, and the resolution of
            // the creation time is one second. So, it is technically possible
            // that there will be multiple snapshots with the same creation
            // time which have clones, and if there are multiple snapshots with
            // clones which have the latest creation time out of any snapshots
            // with clones, then we have no way of knowing which one to promote
            // in order to move all of the snapshots related to clones from the
            // BE dataset that we're trying to destroy. So, we're just going to
            // promote all of them. This will probably never happen in
            // practice, but since it's technically possible, we're going to
            // account for it.
            immutable next = i + 1;
            if(next != snapshots.length && snapshots[next].creationTime == snap.creationTime)
            {
                auto clones = snapshots[next].clones;
                if(!clones.empty)
                    retval.toPromote ~= clones.front;
            }

            break;
        }
    }

    return retval;
}

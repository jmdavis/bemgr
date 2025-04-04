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

    import std.algorithm.searching : find;
    import std.exception : enforce;
    import std.format : format;
    import std.getopt : config, getopt;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.stdio : writeln;
    import std.string : indexOf, splitLines;
    import std.stdio : writefln;

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

        auto result = runCmd(format!`zfs list -Ht filesystem,volume -o name,origin -r %s`(esfn(poolInfo.pool)));
        auto found = result.splitLines().find!(a => a[a.indexOf('\t') + 1 .. $] == snapName)();
        enforce(found.empty,
                format!"Error: %s is the origin of %s"(snapName, found.front[0 .. found.front.indexOf('\t')]));

        if(dryRun)
            writefln("Snapshot to destroy: %s", snapName);
        else
            runCmd(format!"zfs destroy%s %s"(force ? " -f" : "", esfn(snapName)));

        return 0;
    }

    immutable datasetName = buildPath(poolInfo.beParent, toDestroy);
    enforce(poolInfo.rootFS != datasetName, format!"Error: %s is the active dataset"(datasetName));

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
    string parent; // for snapshots only

    enum listCmd = `zfs list -Hpt filesystem,snapshot,volume ` ~
                   // These are the fields parsed in the constructor.
                   `-o name,creation,origin -r %s`;

    this(string line)
    {
        import std.algorithm.iteration : splitter;
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
        this.originName = next(true);

        immutable at = name.indexOf('@');
        if(at != -1)
            this.parent = name[0 .. at];
    }
}

DestroyInfo getDestroyInfo(PoolInfo poolInfo, string beName)
{
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : find, startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.datetime.date : DateTime;
    import std.exception : enforce;
    import std.format : format;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;
    import std.string : representation, splitLines;

    import bemgr.util : runCmd;

    immutable result = runCmd(format!(DSInfo.listCmd)(esfn(poolInfo.pool)),
                              "Error: Failed to get the list of datasets and snapshots");
    immutable datasetName = buildPath(poolInfo.beParent, beName);
    immutable snapStart = datasetName ~ "@";
    immutable childStart = datasetName ~ "/";

    DSInfo dataset;
    DSInfo[] childSnapshots;
    DSInfo[] clones;

    foreach(e; result.splitLines().map!DSInfo().filter!(a => a.name != poolInfo.beParent)())
    {
        if(e.name == datasetName)
            dataset = e;
        else if(!e.parent.empty)
        {
            if(e.parent == datasetName)
                childSnapshots ~= e;
        }
        else if(e.name.representation.startsWith(childStart.representation))
            throw new Exception(format!"Error: %s has child datasets"(datasetName));
        else if(!e.originName.empty)
            clones ~= e;
    }

    enforce(dataset !is DSInfo.init, format!"Error: Boot environment does not exist: %s"(beName));

    immutable canDestroyOrigin = dataset.originName != "=" && clones.find!(a => a.originName == dataset.originName)().empty;
    immutable originToDestroy = canDestroyOrigin ? dataset.originName : "";
    auto clonesAtRisk = clones.filter!(a => a.originName.representation.startsWith(snapStart.representation))().array();

    if(clonesAtRisk.empty)
        return DestroyInfo(datasetName, originToDestroy);

    static struct CloneInfo
    {
        DSInfo clone;
        DateTime originCreationTime;
    }

    CloneInfo[] cloneInfos;

    foreach(e; childSnapshots)
    {
        auto found = clonesAtRisk.find!(a => a.originName == e.name)();
        if(found.empty)
            continue;
        cloneInfos ~= CloneInfo(found.front, e.creationTime);
    }

    // Realistically, there should only be one snapshot with a given creation
    // time on a dataset, but AFAIK, that's not guaranteeed, since snapshots
    // are near instantaneous, and the resolution of the creation time is one
    // second. So, it is technically possible that there will be multiple
    // snapshots with the same creation time which have clones, and if one no
    // newer snapshots have clones, then we have no way of knowing which one to
    // promote in order to move all of the snapshots related to clones from the
    // BE dataset that we're trying to destroy. So, we're just going to promote
    // all of them. This will probably never happen in practice, but since it's
    // technically possible, we're going to account for it.
    auto sorted = cloneInfos.sort!((a, b) => a.originCreationTime > b.originCreationTime)();
    auto latest = sorted.front.originCreationTime;
    string[] toPromote;

    foreach(e; sorted)
    {
        if(e.originCreationTime == latest)
            toPromote ~= e.clone.name;
        else
            break;
    }

    return DestroyInfo(datasetName, originToDestroy, toPromote);
}

// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module util;

import std.meta : allSatisfy;
import std.range.primitives;
import std.traits : isInstanceOf;

private enum isStringVal(alias sym) = is(typeof(sym) == string);

struct ListLine(props...)
    if(allSatisfy!(isStringVal, props))

{
    static foreach(prop; props)
        mixin("string " ~ prop ~ ";");

    static typeof(this) parse(string line)
    {
        import std.algorithm.iteration : splitter;
        import std.exception : enforce;

        auto parts = line.splitter('\t');

        typeof(this) retval;

        foreach(ref field; retval.tupleof)
        {
            enforce(!parts.empty, "zfs list appears to have given fewer fields than we asked for");
            field = parts.front;
            parts.popFront();
        }

        enforce(parts.empty, "zfs list appears to have given more fields than we asked for");

        return retval;
    }
}

auto zfsList(props...)(string dsName, bool recursive = true)
    if(allSatisfy!(isStringVal, props))
{
    import std.algorithm.iteration : map;
    import std.format : format;
    import std.process : esfn = escapeShellFileName;
    import std.range : only;
    import std.string : lineSplitter;


    auto result = runCmd(format!"zfs list -t all -Hpo %-(%s,%)%s %s"(only(props), recursive ? " -r" : "", esfn(dsName)));

    return result.lineSplitter().map!(ListLine!props.parse)();
}

auto zfsList(props...)(string dsName, string type, bool recursive = true)
    if(allSatisfy!(isStringVal, props))
{
    import std.algorithm.iteration : map;
    import std.format : format;
    import std.process : esfn = escapeShellFileName;
    import std.range : only;
    import std.string : lineSplitter;


    auto result = runCmd(format!"zfs list -t %s -Hpo %-(%s,%)%s %s"(type, only(props), recursive ? " -r" : "", esfn(dsName)));

    return result.lineSplitter().map!(ListLine!props.parse)();
}

string zpoolGet(string prop, string pool)
{
    import std.format : format;

    return runCmd(format!"zpool get -Ho value %s %s"(prop, pool));
}

string zfsGet(string prop, string dataset)
{
    import std.format : format;

    return runCmd(format!"zfs get -Ho value %s %s"(prop, dataset));
}

bool zfsHasSetU()
{
    return Version(runCmd("zfs --version")) >= Version(2, 2, 0);
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

string bemgr(string cmd, string args)
{
    import std.format : format;

    return runCmd(format!"../bemgr %s %s"(cmd, args));
}

void mountWithoutZFS(string dsName, string mountpoint)
{
    import std.format : format;
    import std.process : esfn = escapeShellFileName;

    version(FreeBSD)
        runCmd(format!"mount -t zfs %s %s"(esfn(dsName), esfn(mountpoint)));
    else version(linux)
    {
        import std.string : indexOf;

        // This is just dumb, but for some reason, on Linux, mount -t won't
        // work with datasets, requiring -o zfsutil, but -o zfsutil won't work
        // with snapshots.
        if(mountpoint.indexOf('@') != -1)
            runCmd(format!"mount -t zfs -o zfsutil %s %s"(esfn(dsName), esfn(mountpoint)));
        else
            runCmd(format!"mount -t zfs %s %s"(esfn(dsName), esfn(mountpoint)));
    }
    else
        static assert("Unsupported OS");
}

auto getCurrDSList()
{
    import std.algorithm.sorting : sort;
    import std.array : array;

    auto list = zfsList!"name"("zroot").array();
    list.sort!((a, b) => a.name < b.name)();
    return list;
}

struct Diff(T)
    if(isInstanceOf!(ListLine, T))
{
    T[] missing;
    T[] extra;
}

// assumes sorted
auto diffNameList(T)(const(T)[] prev, const(T)[] curr)
    if(isInstanceOf!(ListLine, T) && is(typeof(T.init.name)))
{
    Diff!T retval;

    while(!prev.empty)
    {
        if(curr.empty)
        {
            foreach(e; prev)
                retval.missing ~= e;
            break;
        }

        if(prev.front.name == curr.front.name)
        {
            prev.popFront();
            curr.popFront();
        }
        else if(prev.front.name < curr.front.name)
        {
            retval.missing ~= prev.front;
            prev.popFront();
        }
        else
        {
            retval.extra ~= curr.front;
            curr.popFront();
        }
    }

    foreach(e; curr)
        retval.extra ~= e;

    return retval;
}

unittest
{
    import core.exception : AssertError;
    import std.exception : enforce;
    import std.format : format;

    alias LL = ListLine!"name";

    void test(LL[] prev, LL[] curr, LL[] missing, LL[] extra, size_t line = __LINE__)
    {
        auto result = diffNameList(prev, curr);
        enforce!AssertError(result.missing == missing,
                            format!"missing not equal:\nE: %s\nA: %s"(missing, result.missing), __FILE__, line);
        enforce!AssertError(result.extra == extra,
                            format!"extra not equal:\nE: %s\nA: %s"(extra, result.extra), __FILE__, line);
    }

    test(null, null, null, null);
    test([LL("a")], [LL("a")], null, null);
    test([LL("a"), LL("b")], [LL("a"), LL("b")], null, null);
    test([LL("a"), LL("b"), LL("c")], [LL("a"), LL("b"), LL("c")], null, null);

    test([LL("a")], null, [LL("a")], null);
    test([LL("a"), LL("b")], null, [LL("a"), LL("b")], null);
    test([LL("a"), LL("b"), LL("c")], null, [LL("a"), LL("b"), LL("c")], null);

    test(null, [LL("a")], null, [LL("a")]);
    test(null, [LL("a"), LL("b")], null, [LL("a"), LL("b")]);
    test(null, [LL("a"), LL("b"), LL("c")], null, [LL("a"), LL("b"), LL("c")]);

    test([LL("a")], [LL("1")], [LL("a")], [LL("1")]);
    test([LL("a"), LL("b")], [LL("1"), LL("2")], [LL("a"), LL("b")], [LL("1"), LL("2")]);
    test([LL("a"), LL("b"), LL("c")], [LL("1"), LL("2"), LL("3")],
         [LL("a"), LL("b"), LL("c")], [LL("1"), LL("2"), LL("3")]);

    test([LL("1")], [LL("a")], [LL("1")], [LL("a")]);
    test([LL("1"), LL("2")], [LL("a"), LL("b")], [LL("1"), LL("2")], [LL("a"), LL("b")]);
    test([LL("1"), LL("2"), LL("3")], [LL("a"), LL("b"), LL("c")],
         [LL("1"), LL("2"), LL("3")], [LL("a"), LL("b"), LL("c")]);

    test([LL("a"), LL("c")], [LL("b")], [LL("a"), LL("c")], [LL("b")]);
    test([LL("b")], [LL("a"), LL("c")], [LL("b")], [LL("a"), LL("c")]);

    test([LL("a")], [LL("a"), LL("b"), LL("c")], null, [LL("b"), LL("c")]);
    test([LL("b")], [LL("a"), LL("b"), LL("c")], null, [LL("a"), LL("c")]);
    test([LL("c")], [LL("a"), LL("b"), LL("c")], null, [LL("a"), LL("b")]);

    test([LL("a"), LL("b"), LL("c")], [LL("a")], [LL("b"), LL("c")], null);
    test([LL("a"), LL("b"), LL("c")], [LL("b")], [LL("a"), LL("c")], null);
    test([LL("a"), LL("b"), LL("c")], [LL("c")], [LL("a"), LL("b")], null);

    test([LL("a"), LL("d")], [LL("a"), LL("b"), LL("c")], [LL("d")], [LL("b"), LL("c")]);
    test([LL("b"), LL("d")], [LL("a"), LL("b"), LL("c")], [LL("d")], [LL("a"), LL("c")]);
    test([LL("c"), LL("d")], [LL("a"), LL("b"), LL("c")], [LL("d")], [LL("a"), LL("b")]);

    test([LL("a"), LL("b"), LL("c")], [LL("a"), LL("d")], [LL("b"), LL("c")], [LL("d")]);
    test([LL("a"), LL("b"), LL("c")], [LL("b"), LL("d")], [LL("a"), LL("c")], [LL("d")]);
    test([LL("a"), LL("b"), LL("c")], [LL("c"), LL("d")], [LL("a"), LL("b")], [LL("d")]);
}

// This differs from the mountpoint property, since it's possible to use
// mount -t zfs to mount datasets and snapshots somewhere other than where
// their mountpoint property indicates.
string[string] getMountedDatasets()
{
    import std.algorithm.searching : find;
    import std.string : lineSplitter, representation, stripRight;

    string[string] retval;

    foreach(line; runCmd("zfs mount").lineSplitter())
    {
        auto found = line.representation.find("  /");

        auto dsName = line[0 .. $ - found.length].stripRight();
        auto mountpoint = cast(string)found[2 .. $];

        retval[dsName] = mountpoint;
    }

    return retval;
}

bool dsExists(string dsName)
{
    import std.format : format;
    import std.process : esfn = escapeShellFileName, executeShell;

    return executeShell(format!"zfs list %s"(esfn(dsName))).status == 0;
}

void checkActivated(string activated, string file, size_t line)
{
    checkActivated(activated, null, "default", true, file, line);
}

void checkActivated(string activated, bool checkMounted, string file = __FILE__, size_t line = __LINE__)
{
    checkActivated(activated, null, "default", checkMounted, file, line);
}

void checkActivated(string activated, string defaultName, string file = __FILE__, size_t line = __LINE__)
{
    checkActivated(activated, null, defaultName, true, file, line);
}

void checkActivated(string activated, string[] otherNotClones = null,
                    string defaultName = "default", bool checkMounted = true,
                    string file = __FILE__, size_t line = __LINE__)
{
    import core.exception : AssertError;
    import std.algorithm.searching : canFind;
    import std.exception : enforce;
    import std.format : format;
    import std.path : buildPath;
    import std.range : chain, only;

    immutable fullDN = buildPath("zroot/ROOT", defaultName);

    foreach(e; zfsList!("name", "origin", "canmount", "mountpoint")("zroot/ROOT", "filesystem"))
    {
        if(e.name == "zroot/ROOT")
            continue;

        if(chain(only(activated), otherNotClones).canFind(e.name["zroot/ROOT/".length .. $]))
            enforce!AssertError(e.origin == "-", format!"%s is a clone"(e.name), file, line);
        else
            enforce!AssertError(e.origin != "-", format!"%s is not a clone"(e.name), file, line);

        enforce!AssertError(e.canmount == "noauto", format!"%s has wrong canmount"(e.name), file, line);
        enforce!AssertError(e.mountpoint == "/", format!"%s has wrong mountpoint"(e.name), file, line);

        if(checkMounted)
        {
            auto mounted = getMountedDatasets();
            if(e.name == fullDN)
            {
                auto mountpoint = fullDN in mounted;
                enforce!AssertError(mountpoint !is null && *mountpoint == "/",
                                    format!"%s is not mounted on /"(fullDN), file, line);
            }
            else
                enforce!AssertError(e.name !in mounted, format!"%s is mounted"(e), file, line);
        }
    }

    immutable bootFS = zpoolGet("bootfs", "zroot");
    enforce!AssertError(bootFS == format!"zroot/ROOT/%s"(activated),
                        format!"wrong activated: %s"(bootFS), file, line);
}

private:

struct Version
{
    int major;
    int minor;
    int patch;

    int opCmp(Version rhs)
    {
        if(this.major < rhs.major)
            return -1;
        if(this.major > rhs.major)
            return 1;
        if(this.minor < rhs.minor)
            return -1;
        if(this.minor > rhs.minor)
            return 1;
        if(this.patch < rhs.patch)
            return -1;
        if(this.patch > rhs.patch)
            return 1;
        return 0;
    }

    this(int major, int minor, int patch)
    {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
    }

    this(string versionStr)
    {
        import std.algorithm.iteration : splitter;
        import std.conv : ConvException, to;
        import std.exception : enforce;
        import std.format : format;

        enum errorMsg = `The format of "zfs --version" is not what bemgr expects: %s`;

        try
        {
            enforce(versionStr.length >= "zfs-2.2.6".length, format!errorMsg(versionStr));

            auto parts = versionStr["zfs-".length .. "zfs-2.2.6".length].splitter('.');
            enforce(!parts.empty, format!errorMsg(versionStr));
            this.major = to!int(parts.front);

            parts.popFront();
            enforce(!parts.empty, format!errorMsg(versionStr));
            this.minor = to!int(parts.front);

            parts.popFront();
            enforce(!parts.empty, format!errorMsg(versionStr));
            this.patch = to!int(parts.front);

            parts.popFront();
            enforce(parts.empty, format!errorMsg(versionStr));
        }
        catch(ConvException)
            throw new Exception(format!errorMsg(versionStr));
    }
}

unittest
{
    assert(Version("zfs-1.0.0") > Version("zfs-0.0.0"));
    assert(Version("zfs-1.0.0") == Version("zfs-1.0.0"));
    assert(Version("zfs-1.0.0") < Version("zfs-2.0.0"));

    assert(Version(0, 1, 0) > Version(0, 0, 0));
    assert(Version(0, 1, 0) == Version(0, 1, 0));
    assert(Version(0, 1, 0) < Version(0, 2, 0));

    assert(Version(0, 0, 1) > Version(0, 0, 0));
    assert(Version(0, 0, 1) == Version(0, 0, 1));
    assert(Version(0, 0, 1) < Version(0, 0, 2));

    assert(Version(1, 6, 6) > Version(0, 7, 0));
    assert(Version(1, 6, 6) == Version(1, 6, 6));
    assert(Version(1, 6, 6) < Version(1, 7, 6));

    assert(Version(2, 6, 6) > Version(2, 6, 5));
    assert(Version(2, 6, 6) == Version(2, 6, 6));
    assert(Version(2, 6, 7) < Version(2, 7, 6));
}

// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module realapp;

import std.range.primitives;
import util;

void realMain()
{
    import std.stdio;

    writeln("\nRun dub test to build and run the integration tests.\n");
    writeln("WARNING: Read integration_tests/README.md for the expected setup.");
    writeln("         Do _NOT_ run these tests on a normal system.");
}

version(unittest) shared static this()
{
    import std.stdio : stderr, writeln;

    writeln("Clean bemgr...");
    runCmd("cd ..; dub clean");

    writeln("Build bemgr...");
    runCmd("cd ..; dub build");

    writeln("Running tests...");
}

version(unittest) immutable ListLine!"name"[] startList;

version(unittest) shared static this()
{
    import std.algorithm.searching : find, startsWith;
    import std.exception : enforce;

    startList = cast(immutable)getCurrDSList();

    enforce(!startList.find!(a => a.name == "zroot/ROOT")().empty,
            "zroot/ROOT does not exist. Read integration_tests/README.md!");

    enforce(!startList.find!(a => a.name == "zroot/ROOT/default")().empty,
            "zroot/ROOT/default does not exist. Read integration_tests/README.md!");

    auto found = getMounted().find!(a => a.mountpoint == "/")();
    enforce(!found.empty && found.front.dsName == "zroot/ROOT/default",
            "/ is not mounted on zroot/ROOT/default");

    enforce(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");

    enforce(startList.find!(a => a.name.startsWith("zroot/ROOT/default/")).empty,
            "zroot/ROOT/default has child datasets. Read integration_tests/README.md!");

    enforce(startList.find!(a => a.name.startsWith("zroot/ROOT/default@")).empty,
            "zroot/ROOT/default has snapshots. Read integration_tests/README.md!");
}

// basic functionality of bemgr list
unittest
{
    import core.exception : AssertError;
    import core.thread : Thread;
    import core.time : seconds;

    import std.algorithm.iteration : splitter;
    import std.array : array, split;
    import std.ascii : isDigit, isAlpha;
    import std.datetime.date : DateTime;
    import std.datetime.systime : Clock;
    import std.exception : enforce;
    import std.string : replace, splitLines, startsWith;

    static DateTime test(string[] lines, size_t i, string name, size_t line = __LINE__)
    {
        auto beFields = lines[i].splitter('\t').array();
        enforce!AssertError(beFields.length == 7, "wrong length", __FILE__, line);
        enforce!AssertError(beFields[0] == name, "wrong BE", __FILE__, line);
        enforce!AssertError(beFields[1] == (name == "default" ? "NR" : "-"), "wrong Active", __FILE__, line);
        enforce!AssertError(beFields[2] == (name == "default" ? "/" : "-"), "wrong Mountpoint", __FILE__, line);
        enforce!AssertError(beFields[3].length >= 2 && beFields[3].front.isDigit() && beFields[3].back.isAlpha(),
                            "wrong Space", __FILE__, line);
        enforce!AssertError(beFields[4].length >= 2 && beFields[4].front.isDigit() && beFields[4].back.isAlpha(),
                            "wrong Referenced", __FILE__, line);
        enforce!AssertError(beFields[5].length >= 2 && beFields[5].front.isDigit() && beFields[5].back.isAlpha(),
                            "wrong If Last", __FILE__, line);

        return DateTime.fromISOExtString(beFields[6].replace(" ", "T"));
    }

    {
        auto lines = bemgr("list", "").splitLines();
        assert(lines.length == 2);

        auto headers = lines[0].split();
        assert(headers.length == 8);
        assert(headers[0] == "BE");
        assert(headers[1] == "Active");
        assert(headers[2] == "Mountpoint");
        assert(headers[3] == "Space");
        assert(headers[4] == "Referenced");
        assert(headers[5] == "If");
        assert(headers[6] == "Last");
        assert(headers[7] == "Created");

        assert(lines[1].startsWith("default "));
    }
    {
        auto lines = bemgr("list", "-H").splitLines();
        assert(lines.length == 1);

        auto dt = test(lines, 0, "default");
        assert(dt.year > 2000);
        assert(dt < cast(DateTime)Clock.currTime);
    }
    {
        runCmd("zfs create -o canmount=off -o mountpoint=/ zroot/ROOT/foo");
        scope(exit) runCmd("zfs destroy zroot/ROOT/foo");

        // This is to make sure that they don't have the same creation time.
        Thread.sleep(seconds(1));

        runCmd("zfs create -o canmount=off -o mountpoint=/ zroot/ROOT/bar");
        scope(exit) runCmd("zfs destroy zroot/ROOT/bar");

        {
            auto lines = bemgr("list", "-H").splitLines();
            assert(lines.length == 3);

            auto default_ = test(lines, 0, "default");
            auto foo = test(lines, 1, "foo");
            auto bar = test(lines, 2, "bar");

            assert(default_ < foo);
            assert(foo < bar);
        }
    }
    {
        auto lines = bemgr("list", "-H").splitLines();
        assert(lines.length == 1);

        auto dt = test(lines, 0, "default");
        assert(dt.year > 2000);
        assert(dt < cast(DateTime)Clock.currTime);
    }
}

// basic functionality of bemgr create
unittest
{
    import std.algorithm.searching : startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.format : format;

    bemgr("create", "foo");
    {
        auto result = zfsList!("name", "origin", "clones")("zroot/ROOT").array();
        result.sort!((a, b) => a.name < b.name)();
        assert(result.length == 4);
        assert(result[0].name == "zroot/ROOT");
        assert(result[1].name == "zroot/ROOT/default");
        assert(result[2].name.startsWith("zroot/ROOT/default@"));
        assert(result[2].clones == "zroot/ROOT/foo");
        assert(result[3].name == "zroot/ROOT/foo");
        assert(result[3].origin == result[2].name);
    }

    bemgr("create", "bar");
    {
        auto result = zfsList!("name", "origin", "clones")("zroot/ROOT").array();
        result.sort!((a, b) => a.name < b.name)();
        assert(result.length == 6);
        assert(result[0].name == "zroot/ROOT");
        assert(result[1].name == "zroot/ROOT/bar");
        assert(result[1].origin == result[4].name);
        assert(result[2].name == "zroot/ROOT/default");
        assert(result[3].name.startsWith("zroot/ROOT/default@"));
        assert(result[3].clones == "zroot/ROOT/foo");
        assert(result[4].name.startsWith("zroot/ROOT/default@"));
        assert(result[4].clones == "zroot/ROOT/bar");
        assert(result[5].name == "zroot/ROOT/foo");
        assert(result[5].origin == result[3].name);
    }

    auto after = zfsList!"name"("zroot").array();
    after.sort!((a, b) => a.name < b.name)();

    auto diff = diffNameList(startList, after);

    assert(diff.missing.empty);
    assert(diff.extra[0].name == "zroot/ROOT/bar");
    assert(diff.extra[1].name.startsWith("zroot/ROOT/default@"));
    assert(diff.extra[2].name.startsWith("zroot/ROOT/default@"));
    assert(diff.extra[3].name == "zroot/ROOT/foo");

    runCmd("zfs destroy zroot/ROOT/bar");
    runCmd("zfs destroy zroot/ROOT/foo");
    runCmd(format!"zfs destroy %s"(diff.extra[1].name));
    runCmd(format!"zfs destroy %s"(diff.extra[2].name));
}

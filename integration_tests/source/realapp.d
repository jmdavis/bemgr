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
            "zroot/ROOT does not exist. Read integration_tests/README.md.");

    enforce(!startList.find!(a => a.name == "zroot/ROOT/default")().empty,
            "zroot/ROOT/default does not exist. Read integration_tests/README.md.");

    auto mounted = getMounted();
    auto defaultMount = "zroot/ROOT/default" in mounted;
    enforce(defaultMount !is null && *defaultMount == "/",
            "/ is not mounted on zroot/ROOT/default. Read integration_tests/README.md.");

    enforce(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default",
            "bootfs is not set to zroot/ROOT/default. Read integration_tests/README.md.");

    enforce(startList.find!(a => a.name.startsWith("zroot/ROOT/default/")).empty,
            "zroot/ROOT/default has child datasets. Read integration_tests/README.md.");

    enforce(startList.find!(a => a.name.startsWith("zroot/ROOT/default@")).empty,
            "zroot/ROOT/default has snapshots. Read integration_tests/README.md.");
}

// The tests are broken up into roughly three groups:
// 1. Testing the basic functionality of each command
// 2. Testing that each command handles bad input properly
// 3. Testing the commands with various corner cases (some of which shouldn't
//    happen in practice) to make sure that bemgr behaves sanely in unusual
//    and/or bad situations

// -----------------------------------------------------------------------------
// Tests for basic functionality
// -----------------------------------------------------------------------------

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

    checkActivated("default");

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

    checkActivated("default");

    {
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 4);
        assert(diff.extra[0].name == "zroot/ROOT/bar");
        assert(diff.extra[1].name.startsWith("zroot/ROOT/default@"));
        assert(diff.extra[2].name.startsWith("zroot/ROOT/default@"));
        assert(diff.extra[3].name == "zroot/ROOT/foo");

        runCmd("zfs destroy zroot/ROOT/bar");
        runCmd("zfs destroy zroot/ROOT/foo");
        runCmd(format!"zfs destroy %s"(diff.extra[1].name));
        runCmd(format!"zfs destroy %s"(diff.extra[2].name));
    }

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr create -e beName
unittest
{
    import std.algorithm.searching : startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.format : format;

    bemgr("create", "-e default foo");
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

    checkActivated("default");

    bemgr("create", "-e foo bar");
    {
        auto result = zfsList!("name", "origin", "clones")("zroot/ROOT").array();
        result.sort!((a, b) => a.name < b.name)();
        assert(result.length == 6);
        assert(result[0].name == "zroot/ROOT");
        assert(result[1].name == "zroot/ROOT/bar");
        assert(result[1].origin == result[5].name);
        assert(result[2].name == "zroot/ROOT/default");
        assert(result[3].name.startsWith("zroot/ROOT/default@"));
        assert(result[3].clones == "zroot/ROOT/foo");
        assert(result[4].name == "zroot/ROOT/foo");
        assert(result[4].origin == result[3].name);
        assert(result[5].name.startsWith("zroot/ROOT/foo@"));
        assert(result[5].clones == "zroot/ROOT/bar");
    }

    checkActivated("default");

    {
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 4);
        assert(diff.extra[0].name == "zroot/ROOT/bar");
        assert(diff.extra[1].name.startsWith("zroot/ROOT/default@"));
        assert(diff.extra[2].name == "zroot/ROOT/foo");
        assert(diff.extra[3].name.startsWith("zroot/ROOT/foo@"));

        runCmd("zfs destroy zroot/ROOT/bar");
        runCmd("zfs destroy -r zroot/ROOT/foo");
        runCmd(format!"zfs destroy %s"(diff.extra[1].name));
    }

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr create -e beName@snapshot
unittest
{
    import std.algorithm.searching : startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.format : format;

    string fooSnap;

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

        fooSnap = result[2].name["zroot/ROOT/".length .. $];
    }

    checkActivated("default");

    bemgr("create", format!"-e %s bar"(fooSnap));
    {
        auto result = zfsList!("name", "origin", "clones")("zroot/ROOT").array();
        result.sort!((a, b) => a.name < b.name)();
        assert(result.length == 5);
        assert(result[0].name == "zroot/ROOT");
        assert(result[1].name == "zroot/ROOT/bar");
        assert(result[1].origin == result[3].name);
        assert(result[2].name == "zroot/ROOT/default");
        assert(result[3].name.startsWith("zroot/ROOT/default@"));
        assert(result[3].clones == "zroot/ROOT/bar,zroot/ROOT/foo" ||
               result[3].clones == "zroot/ROOT/foo,zroot/ROOT/bar");
        assert(result[4].name == "zroot/ROOT/foo");
        assert(result[4].origin == result[3].name);
    }

    checkActivated("default");

    {
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 3);
        assert(diff.extra[0].name == "zroot/ROOT/bar");
        assert(diff.extra[1].name.startsWith("zroot/ROOT/default@"));
        assert(diff.extra[2].name == "zroot/ROOT/foo");

        runCmd("zfs destroy zroot/ROOT/bar");
        runCmd("zfs destroy zroot/ROOT/foo");
        runCmd(format!"zfs destroy %s"(diff.extra[1].name));
    }

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr create beName@snapshot
unittest
{
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.format : format;

    bemgr("create", "default@foo");
    {
        auto result = zfsList!("name", "clones")("zroot/ROOT").array();
        result.sort!((a, b) => a.name < b.name)();
        assert(result.length == 3);
        assert(result[0].name == "zroot/ROOT");
        assert(result[1].name == "zroot/ROOT/default");
        assert(result[2].name == "zroot/ROOT/default@foo");
        assert(result[2].clones == "-");
    }

    checkActivated("default");

    bemgr("create", "default@bar");
    {
        auto result = zfsList!("name", "clones")("zroot/ROOT").array();
        result.sort!((a, b) => a.name < b.name)();
        assert(result.length == 4);
        assert(result[0].name == "zroot/ROOT");
        assert(result[1].name == "zroot/ROOT/default");
        assert(result[2].name == "zroot/ROOT/default@bar");
        assert(result[2].clones == "-");
        assert(result[3].name == "zroot/ROOT/default@foo");
        assert(result[3].clones == "-");
    }

    checkActivated("default");

    {
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 2);
        assert(diff.extra[0].name == "zroot/ROOT/default@bar");
        assert(diff.extra[1].name == "zroot/ROOT/default@foo");
    }

    runCmd("zfs destroy zroot/ROOT/default@bar");
    runCmd("zfs destroy zroot/ROOT/default@foo");

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr destroy beName
unittest
{
    import std.algorithm.searching : startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.format : format;

    {
        bemgr("create", "foo");
        bemgr("destroy", "foo");

        checkActivated("default");
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty );
    }
    {
        bemgr("create", "foo");
        immutable origin = zfsGet("origin", "zroot/ROOT/foo");
        bemgr("destroy", "-k foo");

        {
            checkActivated("default");
            auto diff = diffNameList(startList, getCurrDSList());
            assert(diff.missing.empty);
            assert(diff.extra.length == 1);
            assert(diff.extra[0].name == origin);
        }

        runCmd(format!"zfs destroy %s"(origin));

        checkActivated("default");
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty );
    }
    {
        bemgr("create", "foo");
        auto withFoo = getCurrDSList();
        bemgr("destroy", "-n foo");

        {
            auto diff = diffNameList(withFoo, getCurrDSList());
            assert(diff.missing.empty);
            assert(diff.extra.empty );
        }

        bemgr("destroy", "foo");

        checkActivated("default");
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty );
    }
    {
        bemgr("create", "foo");
        bemgr("create", "bar");
        immutable barOrigin = zfsList!"origin"("zroot/ROOT/bar", false).front.origin;

        bemgr("destroy", "-F foo");

        {
            auto result = zfsList!("name", "origin", "clones")("zroot/ROOT").array();
            result.sort!((a, b) => a.name < b.name)();
            assert(result.length == 4);
            assert(result[0].name == "zroot/ROOT");
            assert(result[1].name == "zroot/ROOT/bar");
            assert(result[1].origin == barOrigin);
            assert(result[2].name == "zroot/ROOT/default");
            assert(result[3].name == barOrigin);
            assert(result[3].clones == "zroot/ROOT/bar");
        }

        checkActivated("default");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 2);
        assert(diff.extra[0].name == "zroot/ROOT/bar");
        assert(diff.extra[1].name == barOrigin);

        bemgr("destroy", "bar");
    }

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr destroy beName@snapshot
unittest
{
    import std.algorithm.searching : startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;

    {
        bemgr("create", "default@foo");
        bemgr("destroy", "default@foo");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty );
    }
    {
        bemgr("create", "default@foo");
        bemgr("create", "default@bar");
        bemgr("destroy", "default@foo");

        {
            auto result = zfsList!("name", "clones")("zroot/ROOT").array();
            result.sort!((a, b) => a.name < b.name)();
            assert(result.length == 3);
            assert(result[0].name == "zroot/ROOT");
            assert(result[1].name == "zroot/ROOT/default");
            assert(result[2].name == "zroot/ROOT/default@bar");
            assert(result[2].clones == "-");
        }

        checkActivated("default");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 1);
        assert(diff.extra[0].name == "zroot/ROOT/default@bar");

        bemgr("destroy", "-F default@bar");
    }

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr activate
unittest
{
    import core.exception : AssertError;
    import std.exception : enforce;
    import std.format : format;
    import std.path : buildPath;

    {
        bemgr("create", "foo");
        bemgr("create", "bar");
        bemgr("create", "baz");
        checkActivated("default");

        bemgr("activate", "foo");
        checkActivated("foo");

        bemgr("activate", "bar");
        checkActivated("bar");

        bemgr("activate", "baz");
        checkActivated("baz");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        bemgr("create", "bar");
        bemgr("create", "baz");
        checkActivated("default");

        bemgr("activate", "foo");
        checkActivated("foo");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("activate", "bar");
        checkActivated("bar");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("activate", "baz");
        checkActivated("baz");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        checkActivated("default");
        bemgr("activate", "foo");
        checkActivated("foo");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("create", "bar");
        checkActivated("default");
        bemgr("activate", "bar");
        checkActivated("bar");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("create", "baz");
        checkActivated("default");
        bemgr("activate", "baz");
        checkActivated("baz");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        checkActivated("default");
        bemgr("activate", "foo");
        checkActivated("foo");

        bemgr("create", "bar");
        checkActivated("foo");
        bemgr("activate", "bar");
        checkActivated("bar");

        bemgr("create", "baz");
        checkActivated("bar");
        bemgr("activate", "baz");
        checkActivated("baz");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        checkActivated("default");
        bemgr("activate", "foo");
        checkActivated("foo");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("create", "-e foo bar");
        checkActivated("default");
        bemgr("activate", "bar");
        checkActivated("bar");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("create", "baz -e bar");
        checkActivated("default");
        bemgr("activate", "baz");
        checkActivated("baz");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        checkActivated("default");
        bemgr("activate", "foo");
        checkActivated("foo");

        bemgr("create", "-e foo bar");
        checkActivated("foo");
        bemgr("activate", "bar");
        checkActivated("bar");

        bemgr("create", "baz -e bar");
        checkActivated("bar");
        bemgr("activate", "baz");
        checkActivated("baz");

        bemgr("activate", "default");
        checkActivated("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        checkActivated("default");
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
}

// basic functionality of bemgr rename
unittest
{
    import core.exception : AssertError;
    import std.algorithm.iteration : map;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.exception : enforce;
    import std.format : format;
    import std.path : buildPath;
    import std.range : chain, only;

    checkActivated("default");

    {
        bemgr("rename", "default unfault");

        auto list = zfsList!"name"("zroot/ROOT").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 2);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/unfault");

        checkActivated("unfault", "unfault");
    }
    {
        bemgr("rename", "unfault default");

        auto list = zfsList!"name"("zroot/ROOT").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 2);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/default");

        checkActivated("default");
    }
    {
        bemgr("create", "foo");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/default");
        assert(list[2].name == "zroot/ROOT/foo");

        checkActivated("default");
    }
    {
        bemgr("rename", "foo bar");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/bar");
        assert(list[2].name == "zroot/ROOT/default");

        checkActivated("default");
    }
    {
        bemgr("activate", "bar");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/bar");
        assert(list[2].name == "zroot/ROOT/default");

        checkActivated("bar");
    }
    {
        bemgr("rename", "bar foo");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/default");
        assert(list[2].name == "zroot/ROOT/foo");

        checkActivated("foo");
    }

    bemgr("activate", "default");
    checkActivated("default");

    bemgr("destroy", "foo");

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr mount beName and bemgr umount beName
unittest
{
    import std.file : dirEntries, exists, mkdirRecurse, rmdir, SpanMode, tempDir;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;

    immutable mnt = buildPath(tempDir, "bemgr");

    mkdirRecurse(mnt);
    scope(exit) rmdir(mnt);

    bemgr("create", "foo");
    bemgr("create", "bar");
    assert(dirEntries(mnt, SpanMode.shallow).empty);

    foreach(cmd; ["umount", "unmount"])
    {
        bemgr("mount", "foo " ~ esfn(mnt));

        {
            auto mounted = getMounted();

            {
                auto mountpoint = "zroot/ROOT/foo" in mounted;
                assert(mountpoint !is null && *mountpoint == mnt);
                assert(buildPath(mnt, "bin").exists);
            }
            {
                auto mountpoint = "zroot/ROOT/default" in mounted;
                assert(mountpoint !is null && *mountpoint == "/");
            }
            assert("zroot/ROOT/bar" !in mounted);
        }

        checkActivated("default", false);

        bemgr(cmd, "foo");
        assert(dirEntries(mnt, SpanMode.shallow).empty);

        checkActivated("default");
    }

    bemgr("destroy", "foo");
    bemgr("destroy", "bar");

    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// basic functionality of bemgr export and bemgr import
unittest
{
    import std.algorithm.searching : startsWith;
    import std.file : exists, mkdirRecurse, remove, rmdir, tempDir;
    import std.format : format;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;

    immutable exportFile = buildPath(tempDir, "bemgr_foo");
    immutable mnt = buildPath(tempDir, "bemgr_mount");

    mkdirRecurse(mnt);

    scope(exit)
    {
        if(exportFile.exists)
            remove(exportFile);
        rmdir(mnt);
    }

    {
        bemgr("export", "default > /dev/null");
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("export", "-k default > /dev/null");
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 1);
        assert(diff.extra[0].name.startsWith("zroot/ROOT/default@"));
        bemgr("destroy", diff.extra[0].name["zroot/ROOT/".length .. $]);
    }
    {
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("export", format!"default > %s"(exportFile));
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        runCmd(format!"cat %s | ../bemgr import foo"(exportFile));
        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 2);
        assert(diff.extra[0].name == "zroot/ROOT/foo");
        assert(diff.extra[1].name.startsWith("zroot/ROOT/foo@"));
    }

    checkActivated("default", ["foo"]);

    bemgr("mount", format!"foo %s"(esfn(mnt)));
    assert(buildPath(mnt, "bin").exists);
    bemgr("umount", "foo");

    checkActivated("default", ["foo"]);

    bemgr("destroy", "foo");

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// -----------------------------------------------------------------------------
// Tests for bad input
// -----------------------------------------------------------------------------

// Test various bad inputs for bemgr activate
unittest
{
    import std.exception : assertThrown;
    import std.format : format;
    import std.path : buildPath;

    bemgr("activate", "default");
    checkActivated("default");

    assertThrown(bemgr("activate", "default default"));
    checkActivated("default");

    assertThrown(bemgr("activate", "foo"));
    checkActivated("default");

    assertThrown(bemgr("activate", ""));

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// Test various bad inputs for bemgr create
unittest
{
    import core.exception : AssertError;
    import std.exception : assertThrown, enforce;

    static void check(size_t line = __LINE__)
    {
        checkActivated("default", __FILE__, line);
        auto diff = diffNameList(startList, getCurrDSList());
        enforce!AssertError(diff.missing.empty, "missing isn't empty", __FILE__, line);
        enforce!AssertError(diff.extra.empty, "extra isn't empty", __FILE__, line);
    }

    assertThrown(bemgr("create", "default"));
    check();
    assertThrown(bemgr("create", ""));
    check();
    assertThrown(bemgr("create", "-e default"));
    check();
    assertThrown(bemgr("create", "-e foo bar"));
    check();
    assertThrown(bemgr("create", "-e default@foo bar"));
    check();
    assertThrown(bemgr("create", "foo@bar"));
    check();
}

// Test various bad inputs for bemgr destroy
unittest
{
    import core.exception : AssertError;
    import std.algorithm.searching : countUntil, startsWith;
    import std.algorithm.sorting : sort;
    import std.exception : assertThrown, enforce;

    static void check(string activated, const typeof(getCurrDSList()) list, size_t line = __LINE__)
    {
        checkActivated(activated, __FILE__, line);
        auto diff = diffNameList(list, getCurrDSList());
        enforce!AssertError(diff.missing.empty, "missing isn't empty", __FILE__, line);
        enforce!AssertError(diff.extra.empty, "extra isn't empty", __FILE__, line);
    }

    static void test(string args, string activated, const typeof(getCurrDSList()) list, size_t line = __LINE__)
    {
        assertThrown(bemgr("destroy", args), "failed with no flags", __FILE__, line);
        check(activated, list, line);

        assertThrown(bemgr("destroy", "-n " ~ args), "failed with -n", __FILE__, line);
        check(activated, list, line);

        assertThrown(bemgr("destroy", "-F " ~ args), "failed with -F", __FILE__, line);
        check(activated, list, line);

        assertThrown(bemgr("destroy", "-n -F " ~ args), "failed with -n -F", __FILE__, line);
        check(activated, list, line);
    }

    test("", "default", startList);
    test("default", "default", startList);
    test("zroot/ROOT/default", "default", startList);

    {
        bemgr("create", "foo");
        bemgr("activate", "foo");
        auto withFoo = getCurrDSList();

        test("default", "foo", withFoo);
        test("foo", "foo", withFoo);
        test("zroot/ROOT/foo", "foo", withFoo);
        test("default@foo", "foo", withFoo);
        test("zroot/ROOT/default@foo", "foo", withFoo);

        immutable count = withFoo.countUntil!(a => a.name.startsWith("zroot/ROOT/foo@"))();
        auto origin = withFoo[count].name;
        test(origin["zroot/ROOT/".length .. $], "foo", withFoo);

        bemgr("activate", "default");
        origin = "zroot/ROOT/default@" ~ origin["zroot/ROOT/foo@".length .. $];
        withFoo[count].name = origin;
        withFoo.sort!((a, b) => a.name < b.name)();
        check("default", withFoo);

        test(origin["zroot/ROOT/".length .. $], "default", withFoo);
        test(origin, "default", withFoo);
        test("zroot/ROOT/foo", "default", withFoo);

        bemgr("destroy", "-n foo");
        check("default", withFoo);

        bemgr("destroy", "-n -k foo");
        check("default", withFoo);

        bemgr("destroy", "-n -F foo");
        check("default", withFoo);

        bemgr("destroy", "-n -k -F foo");
        check("default", withFoo);

        bemgr("destroy", "foo");
        check("default", startList);
    }

    bemgr("create", "foo");
    auto origin = zfsGet("origin", "zroot/ROOT/foo");
    bemgr("destroy", "-k -F foo");
    assert(dsExists(origin));
    origin = origin["zroot/ROOT/".length .. $];
    auto withOrigin = getCurrDSList();

    test("-k " ~ origin, "default", withOrigin);

    bemgr("destroy", "-F " ~ origin);
    check("default", startList);
}

// Test various bad inputs for bemgr export and bemgr import
unittest
{
    import core.exception : AssertError;
    import std.exception : assertThrown, enforce;
    import std.file : exists, remove, tempDir;
    import std.format : format;
    import std.path : buildPath;

    static void check(size_t line = __LINE__)
    {
        checkActivated("default", __FILE__, line);
        auto diff = diffNameList(startList, getCurrDSList());
        enforce!AssertError(diff.missing.empty, "missing isn't empty", __FILE__, line);
        enforce!AssertError(diff.extra.empty, "extra isn't empty", __FILE__, line);
    }

    immutable exportFile = buildPath(tempDir, "bemgr_foo");

    scope(exit)
    {
        if(exportFile.exists)
            remove(exportFile);
    }

    assertThrown(bemgr("export", "foo"));
    check();

    bemgr("export", format!"-v default > %s"(exportFile));
    check();

    assertThrown(runCmd(format!"cat %s | ../bemgr import"(exportFile)));
    check();

    assertThrown(runCmd(format!"cat %s | ../bemgr -v import"(exportFile)));
    check();

    assertThrown(runCmd(format!"cat %s | ../bemgr import default"(exportFile)));
    check();

    assertThrown(runCmd(format!"cat %s | ../bemgr import -v default"(exportFile)));
    check();

    runCmd(format!"cat %s | ../bemgr import -v foo"(exportFile));
    assert(dsExists("zroot/ROOT/foo"));
    checkActivated("default", ["foo"]);

    bemgr("destroy", "foo");
    check();
}

// Test various bad inputs for bemgr list
unittest
{
    import std.exception : assertThrown;

    assertThrown(bemgr("list", "default"));
    assertThrown(bemgr("list", "-a default"));
    assertThrown(bemgr("list", "-as default"));
    assertThrown(bemgr("list", "-H default"));
}

// Test various bad inputs for bemgr mount and bemgr umount
unittest
{
    import core.exception : AssertError;
    import std.exception : assertThrown, enforce;
    import std.file : exists, mkdirRecurse, rmdir, tempDir;
    import std.format : format;
    import std.path : buildPath;
    import std.process : esfn = escapeShellFileName;

    immutable mnt = buildPath(tempDir, "bemgr");

    void check(bool isMounted, size_t line = __LINE__)
    {
        auto mounted = getMounted();

        auto default_ = "zroot/ROOT/default" in mounted;
        enforce!AssertError(default_ !is null && *default_ == "/", "default not mounted properly", __FILE__, line);

        auto foo = "zroot/ROOT/foo" in mounted;

        if(isMounted)
            enforce!AssertError(foo !is null && *foo == mnt, "foo not mounted properly", __FILE__, line);
        else
            enforce!AssertError(foo is null, "foo mounted improperly", __FILE__, line);
    }

    mkdirRecurse(mnt);
    scope(exit) rmdir(mnt);

    assertThrown(bemgr("mount", format!"default %s"(esfn(mnt))));
    check(false);
    bemgr("create", "foo");
    check(false);
    bemgr("mount", format!"foo %s"(esfn(mnt)));
    check(true);
    bemgr("umount", "foo");
    check(false);

    version(FreeBSD)
    {
        bemgr("mount", format!"foo %s"(esfn(mnt)));
        check(true);
        bemgr("umount", "-f foo");
        check(false);
        bemgr("mount", format!"foo %s"(esfn(mnt)));
        check(true);
        bemgr("unmount", "-f foo");
        check(false);
    }
    else version(linux)
    {
        bemgr("mount", format!"foo %s"(esfn(mnt)));
        check(true);
        assertThrown(bemgr("umount", "-f foo"));
        check(true);
        assertThrown(bemgr("unmount", "-f foo"));
        check(true);
        bemgr("unmount", "foo");
        check(false);
    }
    else
        static assert(false, "Unsupported OS");

    assert(!exists("/foobar_sally"));
    assertThrown(bemgr("mount", "foo /foobar_sally"));
    check(false);

    assertThrown(bemgr("mount", format!"/foo %s"(esfn(mnt))));
    check(false);
    assertThrown(bemgr("mount", "foo"));
    check(false);
    assertThrown(bemgr("mount", ""));
    check(false);

    bemgr("mount", format!"foo %s"(esfn(mnt)));
    check(true);
    assertThrown(bemgr("umount", ""));
    check(true);
    assertThrown(bemgr("umount", "default"));
    check(true);
    assertThrown(bemgr("umount", "bar"));
    check(true);
    assertThrown(bemgr("umount", "/foo"));
    check(true);

    bemgr("umount", "foo");
    check(false);

    checkActivated("default");
    bemgr("destroy", "foo");

    checkActivated("default");
    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

// Test various bad inputs for bemgr rename
unittest
{
}

// -----------------------------------------------------------------------------
// Tests for corner cases
// -----------------------------------------------------------------------------

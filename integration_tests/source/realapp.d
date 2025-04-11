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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");

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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/bar") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/bar") == "/");

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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");

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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/bar") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/bar") == "/");

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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");

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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/bar") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/bar") == "/");

    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.length == 3);
    assert(diff.extra[0].name == "zroot/ROOT/bar");
    assert(diff.extra[1].name.startsWith("zroot/ROOT/default@"));
    assert(diff.extra[2].name == "zroot/ROOT/foo");

    runCmd("zfs destroy zroot/ROOT/bar");
    runCmd("zfs destroy zroot/ROOT/foo");
    runCmd(format!"zfs destroy %s"(diff.extra[1].name));

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");

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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");

    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.length == 2);
    assert(diff.extra[0].name == "zroot/ROOT/default@bar");
    assert(diff.extra[1].name == "zroot/ROOT/default@foo");

    runCmd("zfs destroy zroot/ROOT/default@bar");
    runCmd("zfs destroy zroot/ROOT/default@foo");

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
}

// basic functionality of bemgr destroy beName
unittest
{
    import std.algorithm.searching : startsWith;
    import std.algorithm.sorting : sort;
    import std.array : array;

    {
        bemgr("create", "foo");
        bemgr("destroy", "foo");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty );
    }
    {
        bemgr("create", "foo");
        bemgr("create", "bar");
        immutable barOrigin = zfsList!"origin"("zroot/ROOT/bar", false).front.origin;

        bemgr("destroy", "foo");

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

        assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
        assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
        assert(zfsGet("canmount", "zroot/ROOT/bar") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/bar") == "/");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 2);
        assert(diff.extra[0].name == "zroot/ROOT/bar");
        assert(diff.extra[1].name == barOrigin);

        bemgr("destroy", "bar");
    }

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");

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

        assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
        assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.length == 1);
        assert(diff.extra[0].name == "zroot/ROOT/default@bar");

        bemgr("destroy", "default@bar");
    }

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");

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

    static void test(string activated, size_t line = __LINE__)
    {
        foreach(e; zfsList!("name", "origin", "canmount", "mountpoint")("zroot/ROOT", "filesystem"))
        {
            if(e.name == "zroot/ROOT")
                continue;

            if(e.name == buildPath("zroot/ROOT", activated))
                enforce!AssertError(e.origin == "-", format!"%s is a clone"(e.name), __FILE__, line);
            else
                enforce!AssertError(e.origin != "-", format!"%s is not a clone"(e.name), __FILE__, line);

            enforce!AssertError(e.canmount == "noauto", format!"%s has wrong canmount"(e.name), __FILE__, line);
            enforce!AssertError(e.mountpoint == "/", format!"%s has wrong mountpoint"(e.name), __FILE__, line);

            auto mounted = getMounted();
            if(e.name == "zroot/ROOT/default")
            {
                auto mountpoint = "zroot/ROOT/default" in mounted;
                enforce!AssertError(mountpoint !is null && *mountpoint == "/",
                                    "zroot/ROOT/default is not mounted on /", __FILE__, line);
            }
            else
                enforce!AssertError(e.name !in mounted, format!"%s is mounted"(e), __FILE__, line);
        }

        immutable bootFS = zpoolGet("bootfs", "zroot");
        enforce!AssertError(bootFS == format!"zroot/ROOT/%s"(activated),
                            format!"wrong activated: %s"(bootFS), __FILE__, line);
    }

    {
        bemgr("create", "foo");
        bemgr("create", "bar");
        bemgr("create", "baz");
        test("default");

        bemgr("activate", "foo");
        test("foo");

        bemgr("activate", "bar");
        test("bar");

        bemgr("activate", "baz");
        test("baz");

        bemgr("activate", "default");
        test("default");

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
        test("default");

        bemgr("activate", "foo");
        test("foo");

        bemgr("activate", "default");
        test("default");

        bemgr("activate", "bar");
        test("bar");

        bemgr("activate", "default");
        test("default");

        bemgr("activate", "baz");
        test("baz");

        bemgr("activate", "default");
        test("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        test("default");
        bemgr("activate", "foo");
        test("foo");

        bemgr("activate", "default");
        test("default");

        bemgr("create", "bar");
        test("default");
        bemgr("activate", "bar");
        test("bar");

        bemgr("activate", "default");
        test("default");

        bemgr("create", "baz");
        test("default");
        bemgr("activate", "baz");
        test("baz");

        bemgr("activate", "default");
        test("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        test("default");
        bemgr("activate", "foo");
        test("foo");

        bemgr("create", "bar");
        test("foo");
        bemgr("activate", "bar");
        test("bar");

        bemgr("create", "baz");
        test("bar");
        bemgr("activate", "baz");
        test("baz");

        bemgr("activate", "default");
        test("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        test("default");
        bemgr("activate", "foo");
        test("foo");

        bemgr("activate", "default");
        test("default");

        bemgr("create", "-e foo bar");
        test("default");
        bemgr("activate", "bar");
        test("bar");

        bemgr("activate", "default");
        test("default");

        bemgr("create", "baz -e bar");
        test("default");
        bemgr("activate", "baz");
        test("baz");

        bemgr("activate", "default");
        test("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

        auto diff = diffNameList(startList, getCurrDSList());
        assert(diff.missing.empty);
        assert(diff.extra.empty);
    }
    {
        bemgr("create", "foo");
        test("default");
        bemgr("activate", "foo");
        test("foo");

        bemgr("create", "-e foo bar");
        test("foo");
        bemgr("activate", "bar");
        test("bar");

        bemgr("create", "baz -e bar");
        test("bar");
        bemgr("activate", "baz");
        test("baz");

        bemgr("activate", "default");
        test("default");

        bemgr("destroy", "foo");
        bemgr("destroy", "bar");
        bemgr("destroy", "baz");

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

    static void test(string defaultName, string active, string[] others, size_t line = __LINE__)
    {
        auto mounted = getMounted();

        foreach(e; chain(only(defaultName), others).map!(a => buildPath("zroot/ROOT", a))())
        {
            if(e["zroot/ROOT/".length .. $] == defaultName)
            {
                auto mountpoint = e in mounted;
                enforce!AssertError(mountpoint !is null && *mountpoint == "/",
                                    format!"%s is not mounted on /"(e), __FILE__, line);
            }
            else
                enforce!AssertError(e !in mounted, format!"%s is mounted"(e), __FILE__, line);

            enforce!AssertError(zfsGet("canmount", e) == "noauto",
                                format!"%s has wrong canmount"(e), __FILE__, line);
            enforce!AssertError(zfsGet("mountpoint", e) == "/",
                                format!"%s has wrong mountpoint"(e), __FILE__, line);
        }

        enforce!AssertError(zpoolGet("bootfs", "zroot") == buildPath("zroot/ROOT", active),
                            "The bootfs property is wrong", __FILE__, line);
    }

    test("default", "default", []);

    {
        bemgr("rename", "default unfault");

        auto list = zfsList!"name"("zroot/ROOT").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 2);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/unfault");

        test("unfault", "unfault", []);
    }
    {
        bemgr("rename", "unfault default");

        auto list = zfsList!"name"("zroot/ROOT").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 2);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/default");

        test("default", "default", []);
    }
    {
        bemgr("create", "foo");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/default");
        assert(list[2].name == "zroot/ROOT/foo");

        test("default", "default", ["foo"]);
    }
    {
        bemgr("rename", "foo bar");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/bar");
        assert(list[2].name == "zroot/ROOT/default");

        test("default", "default", ["bar"]);
    }
    {
        bemgr("activate", "bar");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/bar");
        assert(list[2].name == "zroot/ROOT/default");

        test("default", "bar", ["bar"]);
    }
    {
        bemgr("rename", "bar foo");

        auto list = zfsList!"name"("zroot/ROOT", "filesystem").array();
        list.sort!((a, b) => a.name < b.name)();
        assert(list.length == 3);
        assert(list[0].name == "zroot/ROOT");
        assert(list[1].name == "zroot/ROOT/default");
        assert(list[2].name == "zroot/ROOT/foo");

        test("default", "foo", ["foo"]);
    }

    bemgr("activate", "default");
    bemgr("destroy", "foo");

    test("default", "default", []);

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

        assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
        assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
        assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");
        assert(zfsGet("canmount", "zroot/ROOT/bar") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/bar") == "/");

        bemgr(cmd, "foo");
        assert(dirEntries(mnt, SpanMode.shallow).empty);

        auto mounted = getMounted();
        auto mountpoint = "zroot/ROOT/default" in mounted;
        assert(mountpoint !is null && *mountpoint == "/");
        assert("zroot/ROOT/foo" !in mounted);
        assert("zroot/ROOT/bar" !in mounted);

        assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
        assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
        assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");
        assert(zfsGet("canmount", "zroot/ROOT/bar") == "noauto");
        assert(zfsGet("mountpoint", "zroot/ROOT/bar") == "/");
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

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");
    assert("zroot/ROOT/foo" !in getMounted());

    bemgr("mount", format!"foo %s"(esfn(mnt)));
    assert(buildPath(mnt, "bin").exists);
    bemgr("umount", "foo");

    assert(zpoolGet("bootfs", "zroot") == "zroot/ROOT/default");
    assert(zfsGet("canmount", "zroot/ROOT/default") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/default") == "/");
    assert(zfsGet("canmount", "zroot/ROOT/foo") == "noauto");
    assert(zfsGet("mountpoint", "zroot/ROOT/foo") == "/");

    bemgr("destroy", "foo");

    auto diff = diffNameList(startList, getCurrDSList());
    assert(diff.missing.empty);
    assert(diff.extra.empty);
}

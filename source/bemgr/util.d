// Written in the D programming language

/++
    Copyright: Copyright 2025.
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis)
  +/
module bemgr.util;

import std.bigint : BigInt;
import std.datetime : DateTime, Month;
import std.range.primitives;

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

BigInt parseSize(string size, string fieldName)
{
    import std.bigint : BigInt;
    import std.format : format;

    try
        return BigInt(size);
    catch(Exception)
        throw new Exception(format!`Error: The %s field of zfs list has an unexpected format: %s`(fieldName, size));
}

unittest
{
    import std.exception : assertThrown;
    import std.math : pow;

    assert(parseSize("0", "") == BigInt(0));
    assert(parseSize("123", "") == BigInt(123));
    assert(parseSize("123456789", "") == BigInt(123456789));
    assert(parseSize("123456789012345678901234567890", "") == BigInt("123456789012345678901234567890"));

    assertThrown(parseSize("12M", ""));
    assertThrown(parseSize("123 ", ""));
    assertThrown(parseSize(" 123", ""));
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

DateTime parseDate(string str)
{
    import std.conv : ConvException, to;
    import std.datetime.systime : SysTime;
    import std.format : format;

    try
        return cast(DateTime)SysTime.fromUnixTime(to!ulong(str));
    catch(ConvException)
        throw new Exception(format!`Error: The creation field of zfs list has an unexpected format: %s`(str));
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

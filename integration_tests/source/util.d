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


    auto result = runCmd(format!"zfs list -t all -Hpo %-(%s,%)%s %s"(only(props), recursive ? " -r" : "", dsName));

    return result.lineSplitter().map!(ListLine!props.parse)();
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
auto diffNameList(T)(T[] prev, T[] curr)
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

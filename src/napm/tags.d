/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.tags;

import std.range;
import std.regex;
import std.typecons : nullable, Nullable, tuple;
import std.traits : isSomeString;
import std.conv : to;

@safe:

struct Tag
{
    string name;
    Nullable!uint ver;
    ubyte length = 20;

    enum Encoding
    {
        base64,
        alphanumeric
    }
    auto type = Encoding.base64;
}

auto parseOpt(R)(R rawOpt) pure
if (isSomeString!R)
{
    import std.array : split;
    auto opt = Tag.init.tupleof[1 .. $];
    auto tokens = rawOpt.split;
    auto isSet = tuple!(bool, "ver", bool, "length", bool, "type");
    while (!tokens.empty)
    {
        enum rOpt = ctRegex!`^v(\d+)$|^(\d+)$|^(a)$`;
        auto c = matchFirst(tokens.front, rOpt);
        if (c.empty)
            throw new Exception("Invalid option");

        if (c[1] && isSet.ver || c[2] && isSet.length || c[3] && isSet.type)
            throw new Exception("Duplicate option");

        if (c[1])
        {
            opt[0] = c[1].to!uint;
            isSet.ver = true;
        }
        else if (c[2])
        {
            opt[1] = cast(ubyte) c[2].to!uint;
            isSet.length = true;
        }
        else if (c[3])
        {
            opt[2] = Tag.Encoding.alphanumeric;
            isSet.type = true;
        }

        tokens.popFront();
    }
    return tuple(opt);
}

@("empty")
unittest
{
    assert(Tag("a") == Tag("a", parseOpt("").expand));
}

@("version")
unittest
{
    assert(Tag("foo", nullable(2u)) == Tag("foo", parseOpt("v2").expand));
}

@("length")
unittest
{
    auto expect = Tag("foo");
    expect.length = 16;
    assert(expect == Tag("foo", parseOpt("16").expand));
}

@("alphanumeric option")
unittest
{
    auto expect = Tag("foo");
    expect.type = Tag.Encoding.alphanumeric;
    assert(expect == Tag("foo", parseOpt("a").expand));
}

@("multiple options")
unittest
{
    const expect = Tag("foo", nullable(0u), 32, Tag.Encoding.alphanumeric);
    assert(expect == Tag("foo", parseOpt("v0 32 a").expand));
}

@("option order is irrelevant")
unittest
{
    const expect = Tag("foo", nullable(0u), 32, Tag.Encoding.alphanumeric);
    assert(expect == Tag("foo", parseOpt("a v0 32").expand));
}

@("throws")
unittest
{
    import std.exception : assertThrown;
    // invalid option
    assertThrown(parseOpt("x"));

    // duplicate version
    assertThrown(parseOpt("v2 v2"));

    // duplicate length
    assertThrown(parseOpt("20 v1 20"));

    // dupliacate encoding option
    assertThrown(parseOpt("a v1 16 a"));

    // version truncated
    assertThrown(parseOpt("v 20"));
}

@("ignores whitespace")
unittest
{
    const expect = Tag("foo", nullable(0u), 32, Tag.Encoding.alphanumeric);
    assert(expect == Tag("foo", parseOpt("\tv0  \t  \t 32\t\ta    ").expand));
}

Nullable!Tag findTag(R)(R lines, string tagName) @trusted
if (isSomeString!(ElementType!R))
{
    import std.string : strip;
    enum rTag = ctRegex!`^\W*@\W*([^\W]+)`;
    tagName = tagName.strip;
    foreach (ref line; lines)
    {
        auto c = line.matchFirst(rTag);
        if (c[1] == tagName)
            return nullable(Tag(tagName, c.post.parseOpt.expand));
        // TODO add line number on exception
    }
    return Nullable!Tag();
}

@("empty")
unittest
{
    assert(findTag([""], "foo").isNull);
}

@("single tag")
unittest
{
    assert(Tag("foo") == findTag(["@foo"], "foo"));
}

@("single tag with options")
unittest
{
    const expect = Tag("foo", nullable(3u), 16, Tag.Encoding.alphanumeric);
    assert(expect == findTag(["@foo 16 a v3"], "foo"));
}

@("different tag")
unittest
{
    assert(findTag(["@foo"], "fo").isNull);
}

@("tag name as comment")
unittest
{
    assert(findTag(["foo"], "foo").isNull);
}

@("first matches")
unittest
{
    const lines = ["@foo v3", "@bar 16"];
    assert(Tag("foo", nullable(3u)) == findTag(lines, "foo"));
}

@("last matches")
unittest
{
    const lines = ["@foo v3", "@bar 16"];
    assert(Tag("bar", Nullable!uint(), 16) == findTag(lines, "bar"));
}

@("mid matches")
unittest
{
    const lines = ["@foo", "@bar v1 16", "@fun a"];
    assert(Tag("bar", nullable(1u), 16) == findTag(lines, "bar"));
}

@("comments are ignored")
unittest
{
    const lines = ["@foo", "foo comment", "another", "@bar v1", "bar comment"];
    assert(Tag("bar", nullable(1u)) == findTag(lines, "bar"));
}

@("whitespace is ignored")
unittest
{
    const lines = ["info", " @\t foo", "info", "\t  @  \t bar   \t v2  "];
    assert(Tag("bar", nullable(2u)) == findTag(lines, "bar"));
}

@("whitespace is stripped from name")
unittest
{
    assert(Tag("foo") == findTag(["@foo"], "\n\tfoo   \n"));
}

string toLine(Tag tag) pure nothrow
{
    import std.array : Appender;
    Appender!string opt;
    if (tag.ver != Tag.init.ver)
    {
        opt ~= 'v';
        opt ~= tag.ver.get().to!string;
        opt ~= ' ';
    }
    if (tag.length != Tag.init.length)
    {
        opt ~= tag.length.to!string;
        opt ~= ' ';
    }
    if (tag.type != Tag.init.type)
        opt ~= 'a';

    auto name = "@ " ~ tag.name;
    return opt.data ? name ~ ' ' ~ opt.data : name;
}

@("full tag")
unittest
{
    assert("@ foo v1 16 a" == toLine(Tag("foo", nullable(1u), 16, Tag.Encoding.alphanumeric)));
}

@("default values are not written")
unittest
{
    assert("@ foo" == toLine(Tag("foo")));
}

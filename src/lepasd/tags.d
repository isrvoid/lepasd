/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.tags;

import std.array : Appender;
import std.range;
import std.regex;
import std.traits : isSomeString;
import std.conv : to;
import std.typecons : tuple, Nullable;

@safe:

struct Tag
{
    string name;
    uint ver;
    uint length = 24;

    enum Type
    {
        numeric,
        alphanumeric,
        requiresMix,
        density
    }
    auto type = Type.alphanumeric;
}

struct TagTypeConv
{
pure: nothrow:
    static char toChar(Tag.Type type)
    {
        enum lut = [Tag.Type.numeric: 'n', Tag.Type.alphanumeric: 'a',
                 Tag.Type.requiresMix: 'r', Tag.Type.density: 'd'];
        return lut[type];
    }

    static auto fromChar(char c)
    {
        enum lut = ['n': Tag.Type.numeric, 'a': Tag.Type.alphanumeric,
                 'r': Tag.Type.requiresMix, 'd': Tag.Type.density];
        return lut[c];
    }
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
        enum rOpt = ctRegex!`^v(\d+)$|^(\d+)$|^([adnr])$`;
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
            opt[1] = c[2].to!uint;
            isSet.length = true;
        }
        else if (c[3])
        {
            opt[2] = TagTypeConv.fromChar(c[3][0]);
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
    assert(Tag("foo", 2) == Tag("foo", parseOpt("v2").expand));
}

@("length")
unittest
{
    auto expect = Tag("foo");
    expect.length = 16;
    assert(expect == Tag("foo", parseOpt("16").expand));
}

@("encoding")
unittest
{
    auto expect = Tag("foo");

    expect.type = Tag.Type.numeric;
    assert(expect == Tag("foo", parseOpt("n").expand));

    expect.type = Tag.Type.alphanumeric;
    assert(expect == Tag("foo", parseOpt("a").expand));

    expect.type = Tag.Type.requiresMix;
    assert(expect == Tag("foo", parseOpt("r").expand));

    expect.type = Tag.Type.density;
    assert(expect == Tag("foo", parseOpt("d").expand));
}

@("multiple options")
unittest
{
    const expect = Tag("foo", 0, 32, Tag.Type.alphanumeric);
    assert(expect == Tag("foo", parseOpt("v0 32 a").expand));
}

@("option order is irrelevant")
unittest
{
    const expect = Tag("foo", 0, 32, Tag.Type.alphanumeric);
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

    // negative length
    assertThrown(parseOpt("-1"));

    // length above length.max
    assertThrown(parseOpt(to!string(Tag.length.max + 1uL)));
}

@("ignores whitespace")
unittest
{
    const expect = Tag("foo", 0, 32, Tag.Type.alphanumeric);
    assert(expect == Tag("foo", parseOpt("\tv0  \t  \t 32\t\ta    ").expand));
}

Nullable!Tag findTag(R)(R lines, string tagName) @trusted
if (isSomeString!(ElementType!R))
{
    import std.string : strip;
    import std.typecons : nullable;
    enum rTag = ctRegex!`^\s*@\s*(\S+)`;
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
    const expect = Tag("foo", 3, 16, Tag.Type.alphanumeric);
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
    assert(Tag("foo", 3) == findTag(lines, "foo"));
}

@("last matches")
unittest
{
    const lines = ["@foo v3", "@bar 16"];
    assert(Tag("bar", 0, 16) == findTag(lines, "bar"));
}

@("mid matches")
unittest
{
    const lines = ["@foo", "@bar v1 16", "@fun a"];
    assert(Tag("bar", 1, 16) == findTag(lines, "bar"));
}

@("comments are ignored")
unittest
{
    const lines = ["@foo", "foo comment", "another", "@bar v1", "bar comment"];
    assert(Tag("bar", 1) == findTag(lines, "bar"));
}

@("whitespace is ignored")
unittest
{
    const lines = ["info", " @\t foo", "info", "\t  @  \t bar   \t v2  "];
    assert(Tag("bar", 2) == findTag(lines, "bar"));
}

@("whitespace is stripped from name")
unittest
{
    assert(Tag("foo") == findTag(["@foo"], "\n\tfoo   \n"));
}

@("tag with non word characters")
unittest
{
    // middle
    assert(Tag("foo.com") == findTag(["@ foo.com"], "foo.com"));
    // start
    assert(Tag("-foo") == findTag(["@-foo"], "-foo"));
    // end
    assert(Tag("foo+") == findTag(["@ foo+"], "foo+"));
    // multiple
    assert(Tag("foo.bar/i.h") == findTag(["@foo.bar/i.h"], "foo.bar/i.h"));
}

string toLine(Tag tag) pure nothrow
{
    Appender!string opt;
    if (tag.ver != Tag.init.ver)
    {
        opt ~= ' ';
        opt ~= 'v';
        opt ~= tag.ver.to!string;
    }
    if (tag.length != Tag.init.length)
    {
        opt ~= ' ';
        opt ~= tag.length.to!string;
    }
    if (tag.type != Tag.init.type)
    {
        opt ~= ' ';
        opt ~= TagTypeConv.toChar(tag.type);
    }
    return "@ " ~ tag.name ~ opt.data;
}

@("full tag")
unittest
{
    assert("@ foo v1 16 n" == toLine(Tag("foo", 1, 16, Tag.Type.numeric)));
}

@("default values are not written")
unittest
{
    assert("@ foo" == toLine(Tag("foo")));
}

@("non default type options")
unittest
{
    assert("@ foo 16 n" == toLine(Tag("foo", 0, 16, Tag.Type.numeric)));
    assert("@ foo 16 r" == toLine(Tag("foo", 0, 16, Tag.Type.requiresMix)));
    assert("@ foo 16 d" == toLine(Tag("foo", 0, 16, Tag.Type.density)));
}

@("version has no trailing space")
unittest
{
    assert("@ foo v42" == toLine(Tag("foo", 42)));
}

@("length has no trailing space")
unittest
{
    assert("@ foo 8" == toLine(Tag("foo", 0, 8)));
}

void[] versionedTag(string name, uint ver) pure nothrow
{
    import std.bitmanip : nativeToBigEndian;
    import std.algorithm : find;
    Appender!(ubyte[]) app;
    app ~= cast(const ubyte[]) name;
    app ~= nativeToBigEndian(ver)[].find!"a != 0";
    return app.data;
}

@("v0 has no effect")
unittest
{
    assert("foo" == versionedTag("foo", 0));
}

@("non 0")
unittest
{
    const ubyte[] expect = ['f', 'o', 'o', 1];
    assert(expect == versionedTag("foo", 1));
}

@("max single byte version")
unittest
{
    const ubyte[] expect = ['a', 0xff];
    assert(expect == versionedTag("a", 0xff));
}

@("network byte order")
unittest
{
    const ubyte[] expect = ['a', 0xaa, 0x55];
    assert(expect == versionedTag("a", 0xaa55));
}

@("variable length")
unittest
{
    ubyte[] expect = ['a', 1, 2, 3];
    assert(expect == versionedTag("a", 0x010203));

    expect = ['a', 0xf0, 0xe0, 0xd0, 0xc0];
    assert(expect == versionedTag("a", 0xf0e0d0c0));
}

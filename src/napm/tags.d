module napm.tags;

import std.range;
import std.typecons : nullable, Nullable, tuple;

@safe:

struct Tag
{
    string name;
    Nullable!uint version_;
    ubyte length = 20;

    enum Encoding
    {
        base64,
        alphanumeric
    }
    auto type = Encoding.base64;
}

auto parseOpt(string rawOpt) pure
{
    import std.regex;
    import std.array : split;
    import std.conv : to;

    auto opt = Tag.init.tupleof[1 .. $];
    auto tokens = rawOpt.split;
    auto isSet = tuple!(bool, "version_", bool, "length", bool, "type");
    while (!tokens.empty)
    {
        enum rOpt = ctRegex!`^v(\d+)$|^(\d+)$|^(a)$`;
        auto c = matchFirst(tokens.front, rOpt);
        if (c.empty)
            throw new Exception("Invalid option");

        if (c[1] && isSet.version_ || c[2] && isSet.length || c[3] && isSet.type)
            throw new Exception("Duplicate option");

        if (c[1])
        {
            opt[0] = c[1].to!uint;
            isSet.version_ = true;
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
}

@("ignores whitespace")
unittest
{
    const expect = Tag("foo", nullable(0u), 32, Tag.Encoding.alphanumeric);
    assert(expect == Tag("foo", parseOpt("\tv0  \t  \t 32\t\ta    ").expand));
}

/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.encoding;

import std.range;
import std.utf : byChar;

@safe:


struct SpecialChar
{
    enum length = Lut.specialLength - 26 * 2 - 10 * 2;
    enum set = "!#$%'()+,-:?@[]^_`{}~";
    static assert(set.length == length);
    enum restrictedSet = "#$%?@^_";
    enum restricted = restrictedSet.repeat(3).join;
    static assert(restricted.length == length);
}

struct Lut
{
    enum base10 = iota('0', char('9' + 1));
    enum string base62 = chain(iota('A', char('Z' + 1)), iota('a', char('z' + 1)), base10).array;
    static assert(base62.length == 62);
    enum specialLength = 93;
    enum string special = chain(base62.byChar, SpecialChar.set.byChar, base10).array;
    static assert(special.length == specialLength);
    enum string restrictedSpecial = chain(base62.byChar, SpecialChar.restricted.byChar, base10).array;
    static assert(restrictedSpecial.length == specialLength);
}

uint bitWindow(in ubyte[] a, size_t pos, size_t width) pure nothrow
in (width && width <= uint.sizeof * 8)
{
    ulong clipBytes()
    {
        import std.bitmanip : bigEndianToNative;
        const start = pos / 8;
        const end = (pos + width - 1) / 8 + 1;
        ubyte[8] clip;
        clip[$ - (end - start) .. $] = a[start .. end];
        return bigEndianToNative!ulong(clip);
    }
    const uint mask = cast(uint) (1UL << width) - 1;
    const lastPos = pos + width - 1;
    const byteLastPos = 7 - lastPos % 8;
    return clipBytes >> byteLastPos & mask;
}

@("single bit")
unittest
{
    assert(0 == bitWindow([0], 0, 1));
    assert(1 == bitWindow([0x80], 0, 1));
}

@("bit at non 0 position")
unittest
{
    assert(1 == bitWindow([0x40], 1, 1));
    assert(1 == bitWindow([0x2], 6, 1));
    assert(1 == bitWindow([0x1], 7, 1));
}

@("bit in second byte")
unittest
{
    assert(1 == bitWindow([0, 0x80], 8, 1));
}

@("2 bits")
unittest
{
    assert(0 == bitWindow([0], 0, 2));
    assert(1 == bitWindow([0x40], 0, 2));
    assert(2 == bitWindow([0x80], 0, 2));
    assert(3 == bitWindow([0xc0], 0, 2));
}

@("2 bits at end")
unittest
{
    assert(0 == bitWindow([0], 6, 2));
    assert(1 == bitWindow([0x01], 6, 2));
    assert(2 == bitWindow([0x02], 6, 2));
    assert(3 == bitWindow([0x03], 6, 2));
}

@("2 bits over byte boundary")
unittest
{
    assert(0 == bitWindow([0x00, 0x00], 7, 2));
    assert(1 == bitWindow([0x00, 0x80], 7, 2));
    assert(2 == bitWindow([0x01, 0x00], 7, 2));
    assert(3 == bitWindow([0x01, 0x80], 7, 2));
}

@("out of window bits are ignored")
unittest
{
    assert(0b1011 == bitWindow([0b11011111], 1, 4));
}

@("uint width")
unittest
{
    assert(0 == bitWindow([0, 0, 0, 0], 0, 32));
    assert(0x80000001 == bitWindow([0x80, 0, 0, 1], 0, 32));
    assert(0x40000001 == bitWindow([0x40, 0, 0, 1], 0, 32));
    assert(0x80000002 == bitWindow([0x80, 0, 0, 2], 0, 32));
}

@("uint width unaligned")
unittest
{
    assert(0x40000001 == bitWindow([0x20, 0, 0, 0, 0x80], 1, 32));
    assert(0x80000002 == bitWindow([1, 0, 0, 0, 4], 7, 32));
}

struct Bits
{
    this(in ubyte[] _a, size_t _stepWidth)
    in (_stepWidth && _stepWidth <= uint.sizeof * 8)
    {
        a = _a.dup;
        posEnd = a.length * 8;
        stepWidth = _stepWidth;
    }

    uint front() pure nothrow const
    {
        return bitWindow(a, pos, stepWidth);
    }

    void popFront() pure nothrow
    in (!empty)
    {
        pos += stepWidth;

    }

    bool empty() pure nothrow const
    {
        return posEnd - pos < stepWidth;
    }

private:
    size_t pos, posEnd, stepWidth;
    ubyte[] a;
}

@("single bit")
unittest
{
    auto bits = Bits([0], 1);
    assert(0 == bits.front);

    bits = Bits([0x80], 1);
    assert(1 == bits.front);
}

@("two bits")
unittest
{
    // first bit
    auto bits = Bits([0x80], 1);
    assert(1 == bits.front);
    bits.popFront();
    assert(0 == bits.front);
    // second bit
    bits = Bits([0x40], 1);
    assert(0 == bits.front);
    bits.popFront();
    assert(1 == bits.front);
}

@("empty")
unittest
{
    auto bits = Bits([], 1);
    assert(bits.empty);
}

@("empty step width 1")
unittest
{
    auto bits = Bits([0], 1);
    bits.popFrontN(7);
    assert(!bits.empty);
    bits.popFront();
    assert(bits.empty);
}

@("width with 1 bit is empty")
unittest
{
    auto bits = Bits([0, 0], 3);
    bits.popFrontN(4);
    assert(!bits.empty);
    bits.popFront();
    assert(bits.empty);
}

@("width missing 1 bit is empty")
unittest
{
    auto bits = Bits([0], 3);
    bits.popFront();
    assert(!bits.empty);
    bits.popFront();
    assert(bits.empty);
}

@("step width 2")
unittest
{
    auto bits = Bits([0b11100100], 2);
    assert(3 == bits.front);
    bits.popFront();
    assert(2 == bits.front);
    bits.popFront();
    assert(1 == bits.front);
    bits.popFront();
    assert(0 == bits.front);
}

@("step width 3")
unittest
{
    auto bits = Bits([0b00000101, 0b00111001, 0b01110111], 3);
    int i = 0;
    while (!bits.empty)
    {
        assert(i == bits.front);
        bits.popFront();
        ++i;
    }
    assert(i == 8);
}

@("uint width")
unittest
{
    auto bits = Bits([0x80, 0, 0, 1], 32);
    assert(0x80000001 == bits.front);
    bits.popFront();
    assert(bits.empty);

    bits = Bits([0x40, 0, 0, 1], 32);
    assert(0x40000001 == bits.front);

    bits = Bits([0x80, 0, 0, 2], 32);
    assert(0x80000002 == bits.front);
}

@("width 10")
unittest
{
    auto bits = Bits([0x80, 0x90, 0x15, 0xa8], 10);
    assert(0x202 == bits.front);
    bits.popFront();
    assert(0x101 == bits.front);
    bits.popFront();
    assert(0x5a8 >> 2 == bits.front());
}

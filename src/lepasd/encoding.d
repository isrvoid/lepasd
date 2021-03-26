/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.encoding;

import std.range;
import std.utf : byChar;

@safe:

enum lutLength = 93;
enum specialCount = lutLength - 26 * 2 - 10 * 2;
enum special = "!#$%'()+,-:?@[]^_`{}~";
static assert(special.length == specialCount);
enum restrictedSpecial = "#$%?@^_".repeat(3).join;
static assert(restrictedSpecial.length == specialCount);
enum base10 = iota('0', char('9' + 1));
enum base62 = chain(iota('A', char('Z' + 1)), iota('a', char('z' + 1)), base10);

enum string lut = chain(base62, special.byChar, base10).array;
static assert(lut.length == lutLength);
enum string restrictedLut = chain(base62, restrictedSpecial.byChar, base10).array;
static assert(restrictedLut.length == lutLength);

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
        // TODO refactor to use bit window
        const stepEnd = pos + stepWidth;
        uint result;
        for (size_t i = 0; i < stepWidth; ++i)
        {
            const iPos = stepEnd - 1 - i;
            const bool isSet = (a[iPos / 8] & 1 << 7 - iPos % 8) != 0;
            result |= isSet << i;
        }
        return result;
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

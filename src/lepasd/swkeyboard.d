/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.swkeyboard;

import std.exception : enforce;

extern (C) @nogc
{
    bool lepasd_kbdCanInit();
    int lepasd_kbdInit();
    int lepasd_kbdWrite(int, const char*, size_t);
    int lepasd_kbdClose(int);
}

struct SwKeyboard
{
    static bool canCreate()
    {
        return lepasd_kbdCanInit();
    }

    this() @disable;

    this(int)
    {
        ctx = lepasd_kbdInit();
        enforce(ctx != -1, "Failed to initialize software keyboard");
    }

    ~this()
    {
        if (ctx != -1)
            lepasd_kbdClose(ctx);
    }

    void write(in char[] s) const
    {
        const err = lepasd_kbdWrite(ctx, &s[0], s.length);
        enforce(err != -1, "Software keyboard write error");
    }

    private int ctx = -1;
}

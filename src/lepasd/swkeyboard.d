/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.swkeyboard;

import std.exception : enforce;

extern (C)
{
    int lepasd_swKeyboardInit() @nogc;
    int lepasd_swKeyboardWrite(int, const char*, size_t) @nogc;
    int close(int) @nogc;
}

struct SwKeyboard
{
    static bool canCreate()
    {
        import std.file : exists;
        import std.stdio : File;
        enum path = "/dev/uinput";
        try
            return path.exists && File(path, "wb").isOpen;
        catch (Exception)
            return false;
    }

    this() @disable;

    this(int)
    {
        fd = lepasd_swKeyboardInit();
        enforce(fd != -1, "Failed to initialize software keyboard");
    }

    ~this()
    {
        if (fd != -1)
            close(fd);
    }

    void write(in char[] s) const
    {
        const err = lepasd_swKeyboardWrite(fd, &s[0], s.length);
        enforce(err != -1, "Software keyboard write error");
    }

    private int fd = -1;
}

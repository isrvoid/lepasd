/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module lepasd.hashgen;

extern (C)
{
    enum LEPASD_CONTEXT_SIZE = 216;
    enum LEPASD_HASH_SIZE = 64;

    void lepasd_init(void* password, uint length, void* contextOut) @nogc;
    void lepasd_hash(const void* context, const void* tag, size_t tagLength, void* hashOut) @nogc;
}

@safe:

struct HashGen
{
@nogc:
    this() @disable;

    this(char[] password) @trusted
    {
        lepasd_init(&password[0], cast(uint) password.length, &c[0]);
    }

    ~this()
    {
        c[] = 0;
    }

    auto hash(const void[] tag) const @trusted
    {
        ubyte[LEPASD_HASH_SIZE] h;
        lepasd_hash(&c[0], &tag[0], tag.length, &h[0]);
        return h;
    }

    private ubyte[LEPASD_CONTEXT_SIZE] c;
}

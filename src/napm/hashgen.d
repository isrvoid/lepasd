/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

module napm.hashgen;

extern (C)
{
    enum NAPM_CONTEXT_SIZE = 216;
    enum NAPM_HASH_SIZE = 64;

    void napm_init(void* password, uint length, void* contextOut) @nogc;
    void napm_hash(const void* context, const void* tag, size_t tagLength, void* hashOut) @nogc;
}

@safe:

struct HashGen
{
    this() @disable;

    this(char[] password) @trusted @nogc
    {
        napm_init(&password[0], cast(uint) password.length, &c[0]);
    }

    ~this() @nogc
    {
        c[] = 0;
    }

    auto hash(const void[] tag) @trusted @nogc
    {
        ubyte[NAPM_HASH_SIZE] h;
        napm_hash(&c[0], &tag[0], tag.length, &h[0]);
        return h;
    }

    private ubyte[NAPM_CONTEXT_SIZE] c;
}

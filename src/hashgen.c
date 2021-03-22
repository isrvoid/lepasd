/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#include "hashgen.h"

#include <assert.h>
#include <string.h>

#include <argon2.h>
#include <sha3.h>

static void setDummySalt(void* salt) {
    // There is no salt, because no password is ever stored. The fixed value avoids zeros.
    const char s[] = "lepasd dummy salt";
    sha3(s, sizeof s - 1, salt, LEPASD_HASH_SIZE);
}

static argon2_context argon2ContextTemplate(void) {
    argon2_context c = {
        // .out = NULL,
        .outlen = LEPASD_HASH_SIZE,
        // .pwd = NULL,
        // .pwdlen = 0,
        // .salt = NULL,
        .saltlen = LEPASD_HASH_SIZE,
        .secret = NULL, .secretlen = 0,
        .ad = NULL, .adlen = 0,
        .t_cost = 8, // passes
        .m_cost = 1 << 19, // memory in KB (512 MB)
        .lanes = 2, .threads = 2,
        .version = ARGON2_VERSION_13,
        .allocate_cbk = NULL, .free_cbk = NULL,
        .flags = ARGON2_FLAG_CLEAR_PASSWORD
    };
    return c;
}

void lepasd_init(void* password, uint32_t length, void* contextOut) {
    uint8_t salt[LEPASD_HASH_SIZE];
    setDummySalt(salt);
    uint8_t hash[LEPASD_HASH_SIZE];
    argon2_context ac = argon2ContextTemplate();
    ac.out = hash;
    ac.pwd = password;
    ac.pwdlen = length;
    ac.salt = salt;
    if (argon2id_ctx(&ac) != ARGON2_OK) {
        memset(password, 0, length);
        assert(0);
    }
    // password has been wiped (.flags in argon2_context)

    sha3_ctx_t sc;
    sha3_init(&sc, LEPASD_HASH_SIZE);
    sha3_update(&sc, hash, sizeof hash);
    memset(hash, 0, sizeof hash);
    _Static_assert(LEPASD_CONTEXT_SIZE == sizeof(sha3_ctx_t), "Invalid LEPASD_CONTEXT_SIZE");
    *(sha3_ctx_t*)contextOut = sc;
    memset(&sc, 0, sizeof sc);
}

void lepasd_hash(const void* context, const void* tag, size_t tagLength, void* hashOut) {
    sha3_ctx_t c = *(const sha3_ctx_t*)context;
    sha3_update(&c, tag, tagLength);
    sha3_final(hashOut, &c);
    memset(&c, 0, sizeof c);
}

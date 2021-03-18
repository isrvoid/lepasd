/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#include "generator.h"

#include <assert.h>
#include <string.h>

#include <argon2.h>
#include <sha3.h>

// the SHA3 implementation can,t fail for controlled lengths; its return values are ignored

static sha3_ctx_t shaContext;
static uint8_t isInitialized;

static void setDummySalt(void* salt) {
    // There is no salt, because no password is ever stored. The fixed value avoids zeros.
    const char s[] = "napm dummy salt";
    sha3(s, sizeof s - 1, salt, NAPM_HASH_LENGTH);
}

static argon2_context argon2ContextTemplate(void) {
    argon2_context c = {
        .outlen = NAPM_HASH_LENGTH,
        .saltlen = NAPM_HASH_LENGTH,
        .secret = NULL, .secretlen = 0,
        .ad = NULL, .adlen = 0,
        .t_cost = 8, // passes
        .m_cost = 1 << 19, // memory in KB (512 MB)
        .lanes = 2, .threads = 2,
        .version = ARGON2_VERSION_13,
        .allocate_cbk = NULL, .free_cbk = NULL,
        .flags = ARGON2_FLAG_CLEAR_PASSWORD
    };
    // values to set:
    // out, pwd, pwdlen, salt
    return c;
}

void napm_init(void* password, uint32_t length) {
    uint8_t salt[NAPM_HASH_LENGTH];
    setDummySalt(salt);
    uint8_t hash[NAPM_HASH_LENGTH];
    argon2_context c = argon2ContextTemplate();
    c.out = hash;
    c.pwd = password;
    c.pwdlen = length;
    c.salt = salt;
    if (argon2id_ctx(&c) != ARGON2_OK) {
        memset(password, 0, length);
        memset(hash, 0, sizeof hash);
        assert(0);
    }
    // password was wiped (.flags in argon2_context)

    sha3_init(&shaContext, NAPM_HASH_LENGTH);
    sha3_update(&shaContext, hash, sizeof hash);
    memset(hash, 0, sizeof hash);
    isInitialized = 1;
}

void napm_hash(const void* tag, size_t tagLength, void* hashOut) {
    assert(isInitialized);
    sha3_ctx_t c = shaContext;
    sha3_update(&c, tag, tagLength);
    sha3_final(hashOut, &c);
    memset(&c, 0, sizeof c);
}

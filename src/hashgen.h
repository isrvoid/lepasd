/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#define LEPASD_CONTEXT_SIZE 216
#define LEPASD_HASH_SIZE 64

// password is wiped by argon2
// contextOut shall have at least LEPASD_CONTEXT_SIZE bytes
void lepasd_init(void* password, uint32_t length, void* contextOut);

// context should be initialized by lepasd_init() before lepasd_hash() calls
// skipping lepasd_init() or writing to the context results in bogus hashOut
// hashOut shall have at least LEPASD_HASH_SIZE bytes
void lepasd_hash(const void* context, const void* tag, size_t tagLength, void* hashOut);

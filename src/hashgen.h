/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#define NAPM_CONTEXT_SIZE 216
#define NAPM_HASH_SIZE 64

// password is wiped by argon2
// contextOut shall have at least NAPM_CONTEXT_SIZE bytes
void napm_init(void* password, uint32_t length, void* contextOut);

// context should be initialized by napm_init() before napm_hash() calls
// skipping napm_init() or writing to the context results in bogus hashOut
// hashOut shall have at least NAPM_HASH_SIZE bytes
void napm_hash(const void* context, const void* tag, size_t tagLength, void* hashOut);

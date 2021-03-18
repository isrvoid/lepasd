/*
 * Copyright (c) 2021 Johannes Teichrieb
 * MIT License
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#define NAPM_HASH_LENGTH 64U

// password is wiped by argon2
void napm_init(void* password, uint32_t length);

// napm_init() shall be called before any calls to napm_hash()
// hashOut shall have at least NAPM_HASH_LENGTH bytes
void napm_hash(const void* tag, size_t tagLength, void* hashOut);

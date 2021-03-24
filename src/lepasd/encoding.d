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
enum restrictedSpecial = "!#$%@^_".repeat(3).join;
static assert(restrictedSpecial.length == specialCount);
enum base10 = iota('0', char('9' + 1));
enum base62 = chain(iota('A', char('Z' + 1)), iota('a', char('z' + 1)), base10);

enum string lut = chain(base62, special.byChar, base10).array;
static assert(lut.length == lutLength);
enum string restrictedLut = chain(base62, restrictedSpecial.byChar, base10).array;
static assert(restrictedLut.length == lutLength);

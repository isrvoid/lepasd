ifeq ($(DEBUG),1)
	DFLAGS := -debug
	CFLAGS := -O1 -std=c11
else
	DFLAGS := -release -O
	CFLAGS := -O3 -std=c11 -DNDEBUG
endif

ifndef DC
	DC := dmd
endif

VPATH := src

UNITTESTSRC := lepasd/encoding.d lepasd/tags.d
LEPASDSRC := lepasd/app.d lepasd/encoding.d lepasd/hashgen.d lepasd/swkeyboard.d lepasd/tags.d

ARGON2DIR := third_party/argon2
ARGON2TARGET := libargon2.a
ARGON2 := $(ARGON2DIR)/$(ARGON2TARGET)

SHA3DIR := third_party/tiny_sha3
SHA3 := $(SHA3DIR)/sha3.o

all: bin bin/lepasd bin/unittest

bin/lepasd: bin/hashgen.o bin/swkeyboard.o bin/util.o $(ARGON2) $(SHA3) $(LEPASDSRC)
	@$(DC) $(DFLAGS) -Jsrc/lepasd $^ -of$@

bin/unittest: $(UNITTESTSRC)
	@$(DC) $(DFLAGS) -unittest -main $^ -of$@

CINCLUDES := -I$(SHA3DIR) -I$(ARGON2DIR)/include
CWARNINGS := -Wall -Wextra -Wpedantic
bin/hashgen.o: hashgen.c
	@$(CC) -c $(CFLAGS) $(CWARNINGS) $(CINCLUDES) $^ -o $@

bin/swkeyboard.o: swkeyboard.c
	@$(CC) -c $(CFLAGS) $(CWARNINGS) $^ -o $@

bin/util.o: util.c
	@$(CC) -c $(CFLAGS) $(CWARNINGS) $^ -o $@

bin:
	@mkdir -p $@

$(ARGON2):
	@$(MAKE) -C $(ARGON2DIR) $(ARGON2TARGET)

$(SHA3):
	@$(MAKE) -C $(SHA3DIR)

clean:
	-@$(RM) $(wildcard bin/*)
	@$(MAKE) -C $(ARGON2DIR) clean
	@$(MAKE) -C $(SHA3DIR) clean

.PHONY: all bin clean

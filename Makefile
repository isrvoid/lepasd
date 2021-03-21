ifeq ($(RELEASE),1)
	DFLAGS := -release -O
	CFLAGS := -O3 -std=c11 -Wall -DNDEBUG
else
	DFLAGS := -debug
	CFLAGS := -O1 -std=c11 -Wall
endif

VPATH := src

UNITTESTSRC := napm/tags.d
NAPMSRC := napm/app.d napm/hashgen.d napm/tags.d

ARGON2DIR := third_party/argon2
ARGON2TARGET := libargon2.a
ARGON2 := $(ARGON2DIR)/$(ARGON2TARGET)

SHA3DIR := third_party/tiny_sha3
SHA3 := $(SHA3DIR)/sha3.o

bin/napm: bin/hashgen.o bin/util.o $(ARGON2) $(SHA3) $(NAPMSRC)
	@dmd $(DFLAGS) -Jsrc/napm $^ -of$@

bin/unittest: $(UNITTESTSRC)
	@dmd $(DFLAGS) -unittest -main $^ -of$@

CINCLUDES := -I$(SHA3DIR) -I$(ARGON2DIR)/include
CDONTWARN := -Wno-missing-prototypes -Wno-documentation-unknown-command -Wno-padded \
	-Wno-compare-distinct-pointer-types -Wno-reserved-id-macro
bin/hashgen.o: hashgen.c
	@clang -c $(CFLAGS) -Weverything $(CDONTWARN) $(CINCLUDES) $^ -o $@

bin/util.o: util.c
	@clang -c $(CFLAGS) -Weverything $(CDONTWARN) $^ -o $@

$(ARGON2):
	@$(MAKE) -C $(ARGON2DIR) $(ARGON2TARGET)

$(SHA3):
	@$(MAKE) -C $(SHA3DIR)

clean:
	-@$(RM) $(wildcard bin/*)
	@$(MAKE) -C $(ARGON2DIR) clean
	@$(MAKE) -C $(SHA3DIR) clean

.PHONY: clean

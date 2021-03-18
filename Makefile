DFLAGS_RELEASE := -release -O
DFLAGS_DEBUG := -debug

ifeq ($(RELEASE),1)
	DFLAGS := $(DFLAGS_RELEASE)
else
	DFLAGS := $(DFLAGS_DEBUG)
endif

UNITTESTSRC := src/napm/tags.d
NAPMSRC := src/napm/app.d

ARGON2DIR := third_party/argon2
ARGON2TARGET := libargon2.a
ARGON2 := $(ARGON2DIR)/$(ARGON2TARGET)

SHA3DIR := third_party/tiny_sha3
SHA3 := $(SHA3DIR)/sha3.o

bin/napm: bin/generator.o $(ARGON2) $(SHA3) $(NAPMSRC)
	@dmd $(DFLAGS) $^ -of$@

bin/unittest: $(UNITTESTSRC)
	@dmd $(DFLAGS) -unittest -main $^ -of$@

# FIXME $(CC), -O3, warnings
DISABLE_WARNING := -Wno-missing-prototypes -Wno-documentation-unknown-command -Wno-padded
CINCLUDES := -I$(SHA3DIR) -I$(ARGON2DIR)/include
CSRC := src/generator.c
bin/generator.o: $(CSRC)
	@clang -c -O1 -std=c11 -Weverything $(DISABLE_WARNING) $(CINCLUDES) $(CSRC) -o $@

$(ARGON2):
	@$(MAKE) -C $(ARGON2DIR) $(ARGON2TARGET)

$(SHA3):
	@$(MAKE) -C $(SHA3DIR)

clean:
	-@$(RM) $(wildcard bin/*)
	@$(MAKE) -C $(ARGON2DIR) clean
	@$(MAKE) -C $(SHA3DIR) clean

.PHONY: clean

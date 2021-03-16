DFLAGS_RELEASE := -release -O
DFLAGS_DEBUG := -debug

ifeq ($(RELEASE),1)
	DFLAGS := $(DFLAGS_RELEASE)
else
	DFLAGS := $(DFLAGS_DEBUG)
endif

VPATH := src

#UNITTESTSRC := $(shell find -type f -name "*\.d")
UNITTESTSRC := napm/tags.d

bin/unittest: $(UNITTESTSRC)
	@dmd $(DFLAGS) -unittest -main $^ -of$@

clean:
	-@$(RM) $(wildcard bin/*)

.PHONY: clean

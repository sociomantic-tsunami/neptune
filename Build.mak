# Set of flags required to compile vibe.d without dub
override DFLAGS += -version=VibeLibeventDriver -version=Have_openssl \
	-I./submodules/vibed/source -I./submodules/libevent -I./submodules/openssl

# Compile all vibe.d as a single static library because rdmd can't track
# all imported dependencies correctly in this case. Static library approach
# instead of compiling all sources in one go was chosen to reduce recompilation
# time for actual apps in this repo.
$O/libvibed.a: $(shell find $C/submodules/vibed/source -type f -name '*.d')
	$(call exec, dmd $(DFLAGS) -lib -of$@ $?)

################################################################################

$B/overview: $O/libvibed.a
$B/overview: $C/src/overview/main.d
$B/overview: override LDFLAGS += -L$O -lvibed -levent -lssl -lcrypto

all += $B/overview

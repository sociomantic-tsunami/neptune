# Configuration

ifeq ($(DIST),bionic)
	SSLFIX := --override-config vibe-d:tls/openssl-1.1
else
	SSLFIX :=
endif

# Binaries and packaging

tools := overview release autopr dfm

# Generate short aliases for the tools targets so one can use `make <tool>`
define makealias =
$1: $B/neptune-$1
endef
$(foreach tool,${tools},$(eval $(call makealias,$(tool))))

tool_binaries := $(patsubst %,$B/neptune-%,$(tools))
all += $(tool_binaries)
$O/pkg-neptune.stamp: $(tool_binaries)

$B/neptune-%:
	dub build -q :$* $(SSLFIX)

# Wrapper for dub test to be used from CI

dub-unittest: $(patsubst %,$O/test-%.stamp,$(tools))

$O/test-%.stamp:
	dub test -q :$* $(SSLFIX)

# Wrapper for higher level tests to be used from CI

tests = first_release prerelease patch_release preview_release

dub-inttest: all $(patsubst %,$O/inttest-%.stamp,$(tests))

$O/inttest-%.stamp:
	dub run -q :tests -c $* $(SSLFIX) -- --vverbose --debug --tmp=$O --bin=$B

# Test entry point used by CI

dub-test: dub-unittest dub-inttest

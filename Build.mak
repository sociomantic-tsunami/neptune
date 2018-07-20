# Binaries and packaging

tools := overview release autopr

tool_binaries := $(patsubst %,$B/neptune-%,$(tools))
all += $(tool_binaries)
$O/pkg-neptune.stamp: $(tool_binaries)

$B/neptune-%:
	dub build -q :$*

# Wrapper for dub test to be used from CI

dub-unittest: $(patsubst %,$O/test-%.stamp,$(tools))

$O/test-%.stamp:
	dub test -q :$*

# Wrapper for higher level tests to be used from CI

tests = first_release prerelease patch_release preview_release

dub-inttest: all $(patsubst %,$O/inttest-%.stamp,$(tests))

$O/inttest-%.stamp:
	dub run -q :tests -c $* -- --tmp=$O --bin=$B

# Test entry point used by CI

dub-test: dub-unittest dub-inttest

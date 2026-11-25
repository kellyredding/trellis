.PHONY: build install clean test lint format check dev

TRELLIS_ROOT ?= $(HOME)/.trellis
BINDIR       ?= $(TRELLIS_ROOT)/bin
LINKDIR      ?= $(HOME)/.local/bin
BUILDDIR     ?= build

# The linker takes the binary's minimum macOS from this. Unset, it is the
# building Mac's own version, and older Macs refuse to start the CLI.
export MACOSX_DEPLOYMENT_TARGET = 15.0

test:
	crystal spec

lint:
	crystal tool format --check src spec

format:
	crystal tool format src spec

# `dev` before `test`: the integration specs run the built binary as a
# subprocess, so they have nothing to run until it exists.
check: lint dev test

dev:
	@mkdir -p $(BUILDDIR)
	crystal build -o $(BUILDDIR)/trellis src/trellis.cr

# Universal: Apple Silicon natively, then Intel cross-compiled. Crystal only
# compiles the Intel object and prints the link command, so it is run with
# `-arch x86_64` added; Crystal's bundled static libraries hold both.
build:
	@mkdir -p $(BUILDDIR)
	crystal build --release --no-debug -o $(BUILDDIR)/trellis-arm64 src/trellis.cr
	crystal build --release --no-debug --cross-compile --target x86_64-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) \
	  -o $(BUILDDIR)/trellis-x86_64 src/trellis.cr > $(BUILDDIR)/link-x86_64.sh
	sh -c "$$(sed 's/^cc /cc -arch x86_64 /' $(BUILDDIR)/link-x86_64.sh)"
	lipo -create -output $(BUILDDIR)/trellis $(BUILDDIR)/trellis-arm64 $(BUILDDIR)/trellis-x86_64

# Two compilations on purpose: `check` runs the specs against the dev binary,
# `build` produces the optimized one that is installed.
install: check build
	install -d $(BINDIR) $(LINKDIR)
	install -m 755 $(BUILDDIR)/trellis $(BINDIR)/trellis
	ln -sfn $(BINDIR)/trellis $(LINKDIR)/trellis
	@echo "installed $(BINDIR)/trellis"
	@echo "linked    $(LINKDIR)/trellis"

clean:
	rm -rf $(BUILDDIR) lib .shards

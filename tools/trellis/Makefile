.PHONY: build install clean test lint format check dev

TRELLIS_ROOT ?= $(HOME)/.trellis
BINDIR       ?= $(TRELLIS_ROOT)/bin
LINKDIR      ?= $(HOME)/.local/bin
BUILDDIR     ?= build

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

build:
	@mkdir -p $(BUILDDIR)
	crystal build --release --no-debug -o $(BUILDDIR)/trellis src/trellis.cr

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

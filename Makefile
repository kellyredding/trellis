.PHONY: all check build dev test lint format clean icon \
        cli-build cli-check cli-dev cli-test cli-lint cli-format cli-install cli-clean \
        app-build app-smoke app-check app-release app-clean

all: cli-build

# --- Crystal CLI ---

cli-build:   ; $(MAKE) -C tools/trellis build
cli-check:   ; $(MAKE) -C tools/trellis check
cli-dev:     ; $(MAKE) -C tools/trellis dev
cli-test:    ; $(MAKE) -C tools/trellis test
cli-lint:    ; $(MAKE) -C tools/trellis lint
cli-format:  ; $(MAKE) -C tools/trellis format
cli-install: ; $(MAKE) -C tools/trellis install
cli-clean:   ; $(MAKE) -C tools/trellis clean

# --- Swift app ---

app-build:   ; $(MAKE) -C TrellisApp build
app-smoke:   ; $(MAKE) -C TrellisApp smoke
app-check:   ; $(MAKE) -C TrellisApp check
app-release: ; $(MAKE) -C TrellisApp release
app-clean:   ; $(MAKE) -C TrellisApp clean
icon:        ; $(MAKE) -C TrellisApp icon

# --- Aggregates ---

build: cli-build app-build
clean: cli-clean app-clean

# `check` is the CLI's gate and `app-check` the app's; a change touching both
# sides needs both. Delegated rather than restated, so the steps cannot drift.
check:  cli-check
dev:    cli-dev
test:   cli-test
lint:   cli-lint
format: cli-format

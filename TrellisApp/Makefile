SCHEME         := Trellis
DERIVED_DATA   := build
CONFIG_DEBUG   := Debug
CONFIG_RELEASE := Release

APP_NAME       := Trellis
VERSION        := $(shell cat ../VERSION)
LSREGISTER     := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

FIXTURE        := $(abspath ../fixtures/export.json)
ICON_SET       := TrellisApp/Assets.xcassets/AppIcon.appiconset

XCODEBUILD     = xcodebuild -project TrellisApp.xcodeproj -derivedDataPath $(DERIVED_DATA) \
                   MARKETING_VERSION=$(VERSION)

.PHONY: all generate build smoke check release clean icon

all: build

generate:
	xcodegen generate

# Builds unregister their own product, which Xcode registers with Launch
# Services, so a development build never shadows the installed app.
build: generate
	$(XCODEBUILD) -scheme $(SCHEME) -configuration $(CONFIG_DEBUG) build
	@$(LSREGISTER) -u "$(CURDIR)/$(DERIVED_DATA)/Build/Products/$(CONFIG_DEBUG)/$(APP_NAME).app" 2>/dev/null || true

# A Codable type compiles whether or not its keys match the CLI's export, so
# the build proves nothing about decoding; this does.
smoke: generate
	$(XCODEBUILD) -scheme TrellisSmoke -configuration $(CONFIG_DEBUG) build
	"$(DERIVED_DATA)/Build/Products/$(CONFIG_DEBUG)/TrellisSmoke" "$(FIXTURE)"

check: build smoke

# Universal, so one release serves Apple Silicon and Intel Macs.
release: generate
	$(XCODEBUILD) -scheme $(SCHEME) -configuration $(CONFIG_RELEASE) \
	  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
	@$(LSREGISTER) -u "$(CURDIR)/$(DERIVED_DATA)/Build/Products/$(CONFIG_RELEASE)/$(APP_NAME).app" 2>/dev/null || true

# Draws every size of the app icon from the lattice geometry.
icon:
	swift Icon/trellis-icon.swift "$(ICON_SET)"
	@echo "Drew $(ICON_SET)"

clean:
	rm -rf $(DERIVED_DATA)

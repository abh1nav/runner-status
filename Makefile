APP_NAME  := Runner Status
VERSION   := $(shell cat VERSION)
# Build number is a UTC timestamp: monotonic without needing git. Override with `make build BUILD=n`.
BUILD     := $(shell date -u +%Y%m%d%H%M)
MACOS_MIN := 14.0
TARGET    := $(shell uname -m)-apple-macosx$(MACOS_MIN)
# SDK to compile against; empty means the active default. Auto-detected (see scripts/detect-sdk.sh)
# because macOS 27+ SDKs can't build SwiftUI @State without Xcode. Override with `make build SDK=path`.
SDK       ?= $(shell scripts/detect-sdk.sh $(TARGET))

APP   := dist/$(APP_NAME).app
PLIST := $(APP)/Contents/Info.plist
ZIP   := dist/RunnerStatus-$(VERSION).zip

.PHONY: build clean install

build: clean
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp LICENSE THIRD_PARTY_NOTICES "$(APP)/Contents/Resources/"
	swiftc $(if $(SDK),-sdk "$(SDK)") -O -swift-version 5 -target $(TARGET) -parse-as-library \
		Sources/*.swift -o "$(APP)/Contents/MacOS/RunnerStatus"
	cp Info.plist "$(PLIST)"
	plutil -insert CFBundleShortVersionString -string "$(VERSION)" "$(PLIST)"
	plutil -insert CFBundleVersion -string "$(BUILD)" "$(PLIST)"
	plutil -insert LSMinimumSystemVersion -string "$(MACOS_MIN)" "$(PLIST)"
	codesign --force --sign - "$(APP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	@echo "Built $(APP) $(VERSION) ($(BUILD)) and $(ZIP)"

install: build
	pkill -x RunnerStatus || true
	rm -rf "/Applications/$(APP_NAME).app"
	ditto "$(APP)" "/Applications/$(APP_NAME).app"
	open "/Applications/$(APP_NAME).app"

clean:
	rm -rf dist

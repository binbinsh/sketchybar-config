all: app

# Build a minimal background app wrapper so TCC grants permission to the app
# itself rather than the launching terminal. The app will print JSON to stdout.
APP_NAME=SketchyBarNetworkInfoHelper
APP_BUNDLE=bin/$(APP_NAME).app
APP_CONTENTS=$(APP_BUNDLE)/Contents
APP_MACOS=$(APP_CONTENTS)/MacOS
APP_INFO=$(APP_CONTENTS)/Info.plist
CODESIGN_ID ?= -
ifeq ($(CODESIGN_ID),-)
CODESIGN_FLAGS=
else
CODESIGN_FLAGS=--options runtime
endif

# Build universal binary for arm64 and x86_64, target macOS 11+
ARCHES=-arch arm64 -arch x86_64
MINVER=-mmacosx-version-min=11.0

app: $(APP_BUNDLE)

$(APP_BUNDLE): network_info.m App-Info.plist
	@mkdir -p $(APP_MACOS)
	clang $(ARCHES) network_info.m -fobjc-arc $(MINVER) -framework Foundation -framework SystemConfiguration -framework CoreWLAN \
	  -o $(APP_MACOS)/$(APP_NAME) \
	  -Wl,-sectcreate,__TEXT,__info_plist,App-Info.plist
	@cp App-Info.plist $(APP_INFO)
	codesign --force --deep --sign "$(CODESIGN_ID)" $(CODESIGN_FLAGS) "$(APP_BUNDLE)"

run-app: app
	open -W "$(CURDIR)/$(APP_BUNDLE)"

clean:
	rm -rf bin

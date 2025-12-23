APP_NAME=now_playing
BIN=bin/$(APP_NAME)

ARCHES=-arch arm64 -arch x86_64
MINVER=-mmacosx-version-min=11.0

all: $(BIN)

$(BIN): now_playing.m ../sketchybar.h | bin
	clang $(ARCHES) -fobjc-arc now_playing.m $(MINVER) \
	  -framework Foundation \
	  -o $(BIN)

bin:
	mkdir -p bin

clean:
	rm -rf bin



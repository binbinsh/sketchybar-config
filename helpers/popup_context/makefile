bin/popup_context: popup_context.c ../sketchybar.h | bin
	clang -std=c99 -O3 $< -o $@ \
	  -framework ApplicationServices \
	  -F /System/Library/PrivateFrameworks -framework SkyLight

bin:
	mkdir -p bin



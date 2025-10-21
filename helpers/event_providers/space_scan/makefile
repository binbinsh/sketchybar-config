bin/space_scan: space_scan.c ../sketchybar.h | bin
	clang -std=c99 -O3 $< -o $@ \
	  -framework ApplicationServices \
	  -F /System/Library/PrivateFrameworks -framework SkyLight

bin:
	mkdir -p bin



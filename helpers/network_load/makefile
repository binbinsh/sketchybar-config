bin/network_load: network_load.c network.h ../sketchybar.h | bin
	clang -std=c99 -O3 $< -o $@ -framework SystemConfiguration -framework CoreFoundation

bin:
	mkdir bin

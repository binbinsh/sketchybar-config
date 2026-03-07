bin/network_load: network_load.c network.h ../sketchybar.h ../network_interface_resolver.c ../network_interface_resolver.h | bin
	clang -std=c99 -O3 network_load.c ../network_interface_resolver.c -o $@ -framework SystemConfiguration -framework CoreFoundation

bin:
	mkdir bin

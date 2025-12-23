bin/system_stats: system_stats.c cpu.h ../sketchybar.h | bin
	clang -std=c99 -O3 $< -o $@ -framework IOKit -framework CoreFoundation

bin:
	mkdir -p bin

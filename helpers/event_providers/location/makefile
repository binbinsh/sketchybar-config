all: bin/location

bin/location: location.m Info.plist
	@mkdir -p bin
	clang location.m -fobjc-arc -framework Foundation -framework CoreLocation -o bin/location \
	  -Wl,-sectcreate,__TEXT,__info_plist,Info.plist

clean:
	rm -rf bin



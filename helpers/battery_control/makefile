# Battery Control Helper
CC = clang
CFLAGS = -O3 -fobjc-arc -Wall -Wextra
FRAMEWORKS = -framework IOKit -framework Foundation
TARGET = battery_control
BINDIR = bin
SUDOERS_FILE = /private/etc/sudoers.d/battery_control

.PHONY: all clean install setup uninstall

all: $(BINDIR)/$(TARGET)

$(BINDIR)/$(TARGET): battery_control.m smc.h | $(BINDIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) -o $@ $<

$(BINDIR):
	mkdir -p $(BINDIR)

install: $(BINDIR)/$(TARGET)
	@echo "Binary installed at $(BINDIR)/$(TARGET)"

setup: install
	@echo "Configuring sudoers for passwordless access..."
	@FULL_PATH="$$(cd $(BINDIR) && pwd)/$(TARGET)"; \
	echo "ALL ALL = NOPASSWD: $$FULL_PATH" | sudo tee $(SUDOERS_FILE) > /dev/null
	@sudo chmod 440 $(SUDOERS_FILE)
	@echo "Done! You can now use: sudo $(BINDIR)/$(TARGET) without password"

uninstall:
	rm -rf $(BINDIR)
	sudo rm -f $(SUDOERS_FILE)
	@echo "Uninstalled battery_control and removed sudoers entry"

clean:
	rm -rf $(BINDIR)

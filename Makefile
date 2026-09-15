CARGO ?= cargo
BIN_DIR = bin
TARGET = $(BIN_DIR)/caelestia-daemon
DAEMON_DIR = daemon

.PHONY: all build release debug test test-rust test-qml run stop restore clean install help

all: build

help:
	@echo "Caelestia KDE Management Makefile"
	@echo "  make build       - Build optimized release daemon to $(TARGET)"
	@echo "  make debug       - Build debug daemon"
	@echo "  make test        - Run all tests (Rust unit tests + QML integration tests)"
	@echo "  make test-rust   - Run only Rust unit tests"
	@echo "  make test-qml    - Run only QML test suites"
	@echo "  make run         - Run theme (auto-restores original top panel on exit)"
	@echo "  make stop        - Stop theme and restore original top panel"
	@echo "  make restore     - Restore original KDE Plasma top panel"
	@echo "  make clean       - Clean build artifacts"

build: release

release:
	@mkdir -p $(BIN_DIR)
	$(CARGO) build --release --manifest-path $(DAEMON_DIR)/Cargo.toml
	install -m 755 $(DAEMON_DIR)/target/release/caelestia-daemon $(TARGET)
	ln -sf caelestia-daemon $(BIN_DIR)/caelestia
	@echo "Built: $(TARGET) and $(BIN_DIR)/caelestia"

debug:
	@mkdir -p $(BIN_DIR)
	$(CARGO) build --manifest-path $(DAEMON_DIR)/Cargo.toml
	install -m 755 $(DAEMON_DIR)/target/debug/caelestia-daemon $(TARGET)
	ln -sf caelestia-daemon $(BIN_DIR)/caelestia
	@echo "Built debug: $(TARGET)"

test: test-rust test-qml

test-rust:
	$(CARGO) test --manifest-path $(DAEMON_DIR)/Cargo.toml

test-qml:
	bash tests/run_qml_tests.sh

run: build
	@trap './bin/caelestia plasma restore' EXIT INT TERM; \
	./bin/caelestia run

stop:
	@pkill -9 -x quickshell 2>/dev/null || true
	@pkill -9 -f "caelestia-daemon" 2>/dev/null || true
	@./bin/caelestia plasma restore

restore:
	@./bin/caelestia plasma restore

clean:
	$(CARGO) clean --manifest-path $(DAEMON_DIR)/Cargo.toml
	rm -rf $(BIN_DIR)

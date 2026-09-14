CARGO ?= cargo
BIN_DIR = bin
TARGET = $(BIN_DIR)/caelestia-daemon
DAEMON_DIR = daemon

.PHONY: all build release debug test test-rust test-qml run clean install help

all: build

help:
	@echo "Caelestia KDE Management Makefile"
	@echo "  make build       - Build optimized release daemon to $(TARGET)"
	@echo "  make debug       - Build debug daemon"
	@echo "  make test        - Run all tests (Rust unit tests + QML integration tests)"
	@echo "  make test-rust   - Run only Rust unit tests"
	@echo "  make test-qml    - Run only QML test suites"
	@echo "  make run         - Reload/start quickshell with current configuration"
	@echo "  make clean       - Clean build artifacts"

build: release

release:
	@mkdir -p $(BIN_DIR)
	$(CARGO) build --release --manifest-path $(DAEMON_DIR)/Cargo.toml
	install -m 755 $(DAEMON_DIR)/target/release/caelestia-daemon $(TARGET)
	@echo "Built: $(TARGET)"

debug:
	@mkdir -p $(BIN_DIR)
	$(CARGO) build --manifest-path $(DAEMON_DIR)/Cargo.toml
	install -m 755 $(DAEMON_DIR)/target/debug/caelestia-daemon $(TARGET)
	@echo "Built debug: $(TARGET)"

test: test-rust test-qml

test-rust:
	$(CARGO) test --manifest-path $(DAEMON_DIR)/Cargo.toml

test-qml:
	python3 tests/run_tests.py

run: build
	quickshell -p .

clean:
	$(CARGO) clean --manifest-path $(DAEMON_DIR)/Cargo.toml
	rm -rf $(BIN_DIR)

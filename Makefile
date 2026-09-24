CARGO ?= cargo
BIN_DIR = bin
TARGET = $(BIN_DIR)/astral-plasma
DAEMON_DIR = daemon

.PHONY: all build release debug test test-rust test-qml doctor run stop restore clean install changelog release-tag help

all: build

help:
	@echo "Astral Plasma Management Makefile"
	@echo "  make build       - Build single self-contained binary to $(TARGET)"
	@echo "  make debug       - Build debug single binary"
	@echo "  make doctor      - Check dependencies and system compatibility"
	@echo "  make test        - Run all tests (Rust unit tests + QML integration tests)"
	@echo "  make test-rust   - Run only Rust unit tests"
	@echo "  make test-qml    - Run only QML test suites"
	@echo "  make changelog   - Generate changelog preview from git history"
	@echo "  make release-tag - Trigger automated release (e.g. make release-tag VERSION=0.2.0)"
	@echo "  make run         - Run theme (auto-restores original top panel on exit)"
	@echo "  make stop        - Stop theme and restore original top panel"
	@echo "  make restore     - Restore original KDE Plasma top panel"
	@echo "  make clean       - Clean build artifacts"

build: release

release:
	@mkdir -p $(BIN_DIR)
	$(CARGO) build --release --manifest-path $(DAEMON_DIR)/Cargo.toml
	install -m 755 $(DAEMON_DIR)/target/release/astral-plasma $(TARGET)
	@echo "Built single self-contained binary: $(TARGET)"

debug:
	@mkdir -p $(BIN_DIR)
	$(CARGO) build --manifest-path $(DAEMON_DIR)/Cargo.toml
	install -m 755 $(DAEMON_DIR)/target/debug/astral-plasma $(TARGET)
	@echo "Built debug: $(TARGET)"

test: test-rust test-qml

test-rust:
	$(CARGO) test --manifest-path $(DAEMON_DIR)/Cargo.toml

test-qml:
	bash tests/run_qml_tests.sh

changelog:
	@bash scripts/generate_changelog.sh

release-tag:
	@bash scripts/release.sh $(VERSION)

doctor: build
	./$(TARGET) doctor

run: build
	@trap './bin/astral-plasma desktop cleanup 2>/dev/null || true; ./bin/astral-plasma plasma restore' EXIT INT TERM; \
	./bin/astral-plasma run

stop:
	@pkill -9 -x quickshell 2>/dev/null || true
	@pkill -9 -f "astral-plasma" 2>/dev/null || true
	@./bin/astral-plasma desktop cleanup 2>/dev/null || true
	@./bin/astral-plasma plasma restore

restore:
	@./bin/astral-plasma desktop cleanup 2>/dev/null || true
	@./bin/astral-plasma plasma restore

clean:
	$(CARGO) clean --manifest-path $(DAEMON_DIR)/Cargo.toml
	rm -rf $(BIN_DIR)

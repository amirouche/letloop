.PHONY: help build-scheme build-go build-rust build-fastapi build-flask build-js build-gleam bench bench-perf clean

help:
	@echo "Benchmark Suite - Counter Application"
	@echo ""
	@echo "Build:"
	@echo "  make build-scheme   - Build Scheme (picotransparenturing) server"
	@echo "  make build-go       - Build Go implementation"
	@echo "  make build-js       - Check Node.js availability"
	@echo "  make build-rust     - Build Rust implementation (release mode)"
	@echo "  make build-gleam    - Build Gleam implementation"
	@echo "  make build-fastapi  - Setup FastAPI venv and dependencies"
	@echo "  make build-flask    - Setup Flask venv and dependencies"
	@echo ""
	@echo "Benchmarking:"
	@echo "  make bench          - Run scaling benchmark"
	@echo "  make bench-perf     - Run perf-profiled benchmark (Scheme)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean          - Clean all build artifacts"

build-scheme:
	@echo "Building Scheme implementation..."
	@mkdir -p bin
	@cd .. && ./local/bin/letloop compile --optimize-level=3 ./examples ./examples/picotransparenturing-example.scm main 2>&1 | tail -1 && mv a.out benchmarks/bin/scheme-pico-server
	@echo "✓ Scheme (pico) built"

build-go:
	@echo "Building Go implementation..."
	@mkdir -p bin
	@cd go && go build -o ../bin/go-server main.go
	@echo "✓ Go built"

build-js:
	@if command -v node >/dev/null 2>&1; then \
		echo "✓ Node.js available"; \
	else \
		echo "✗ Node.js not found"; exit 1; \
	fi

build-gleam:
	@echo "Building Gleam implementation..."
	@cd gleam && gleam build 2>&1 | tail -1
	@echo "✓ Gleam built"

build-rust:
	@echo "Building Rust implementation..."
	@cd rust && cargo build --release 2>&1 | grep -v "Compiling\|Finished" || true
	@echo "✓ Rust built"

build-fastapi:
	@echo "Setting up FastAPI environment..."
	@cd fastapi && python3 -m venv venv && . venv/bin/activate && pip install -q -r requirements.txt
	@echo "✓ FastAPI ready"

build-flask:
	@echo "Setting up Flask environment..."
	@cd flask && python3 -m venv venv && . venv/bin/activate && pip install -q -r requirements.txt
	@echo "✓ Flask ready"

bench:
	@bash bench.sh

bench-perf:
	@echo "Running perf-profiled benchmark..."
	@bash bench-perf.sh

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf bin results
	@rm -rf rust/target rust/Cargo.lock
	@rm -rf gleam/build
	@rm -rf fastapi/venv flask/venv
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -delete
	@echo "✓ Clean complete"

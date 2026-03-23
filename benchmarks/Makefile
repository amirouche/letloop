.PHONY: help build-scheme build-go build-rust build-fastapi build-flask build-js build-gleam build-h2o bench bench-perf clean

ROOT := $(shell cd .. && pwd)

help:
	@echo "Benchmark Suite - Counter Application"
	@echo ""
	@echo "Build:"
	@echo "  make build-scheme   - Build Scheme (picotransparenturing) server"
	@echo "  make build-go       - Build Go implementation"
	@echo "  make build-js       - Check Node.js availability"
	@echo "  make build-rust     - Build Rust implementation (release mode)"
	@echo "  make build-gleam    - Build Gleam implementation"
	@echo "  make build-h2o      - Build C/h2o implementation (clones h2o, builds libh2o-evloop)"
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

build-h2o:
	@echo "Building C/h2o implementation..."
	@mkdir -p bin h2o-dep
	@if [ ! -d h2o-dep/src ]; then \
		cd h2o-dep && git clone --depth 1 https://github.com/h2o/h2o.git src; \
	fi
	@if [ ! -f h2o-dep/src/build/libh2o-evloop.so ]; then \
		mkdir -p h2o-dep/src/build && cd h2o-dep/src/build && \
		cmake .. -DCMAKE_INSTALL_PREFIX=$(ROOT)/local -DBUILD_SHARED_LIBS=ON -DWITH_MRUBY=OFF -DWITH_DTRACE=OFF && \
		$(MAKE) libh2o-evloop; \
	fi
	@cp h2o-dep/src/build/libh2o-evloop.so $(ROOT)/local/lib/libh2o-evloop.so
	@ln -sf libh2o-evloop.so $(ROOT)/local/lib/libh2o-evloop.so.0.16
	@ln -sf /usr/lib/x86_64-linux-gnu/libbrotlienc.so.1 $(ROOT)/local/lib/libbrotlienc.so
	@ln -sf /usr/lib/x86_64-linux-gnu/libbrotlidec.so.1 $(ROOT)/local/lib/libbrotlidec.so
	@ln -sf /usr/lib/x86_64-linux-gnu/libbrotlicommon.so.1 $(ROOT)/local/lib/libbrotlicommon.so
	@gcc -O3 -DH2O_USE_LIBUV=0 -o bin/h2o-server h2o/server.c \
		-Ih2o-dep/src/include -Ih2o-dep/src/deps/picohttpparser -Ih2o-dep/src/deps/yoml \
		-Ih2o-dep/src/deps/cloexec -Ih2o-dep/src/deps/picotls/include \
		-Ih2o-dep/src/deps/quicly/include -Ih2o-dep/src/deps/picotest -Ih2o-dep/src/deps/klib \
		-L$(ROOT)/local/lib -lh2o-evloop -lssl -lcrypto -lpthread -lz \
		-lbrotlienc -lbrotlidec -lbrotlicommon \
		-Wl,-rpath,$(ROOT)/local/lib
	@echo "✓ C/h2o built"

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
	@rm -rf h2o-dep
	@rm -rf fastapi/venv flask/venv
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -delete
	@echo "✓ Clean complete"

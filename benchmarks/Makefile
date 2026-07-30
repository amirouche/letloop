.PHONY: help build-scheme build-go build-rust build-bun-canary build-fastapi build-flask build-js build-gleam build-h2o build-cl build-ruby build-java-loom build-java-vertx bench bench-perf report clean

ROOT := $(shell cd .. && pwd)

help:
	@echo "Benchmark Suite - HTTP Counter Application"
	@echo ""
	@echo "Build targets:"
	@echo "  make build-scheme   Build letloop server (my-web-library over io_uring, requires ./venv)"
	@echo "  make build-go       Build Go server (net/http stdlib)"
	@echo "  make build-rust     Build Rust server (axum + tokio, release mode)"
	@echo "  make build-bun-canary Check bun-canary binary availability"
	@echo "  make build-h2o      Build C server (clones h2o, builds libh2o-evloop, installs to local/lib)"
	@echo "  make build-gleam    Build Gleam server (mist + gleam_otp on BEAM)"
	@echo "  make build-cl       Build Common Lisp server (Hunchentoot, SBCL standalone binary)"
	@echo "  make build-ruby     Check Ruby and Falcon gem availability"
	@echo "  make build-java-loom  Build Java virtual threads server (JDK stdlib, zero deps)"
	@echo "  make build-java-vertx Build Java Vert.x server (Maven fat jar)"
	@echo "  make build-js       Check Node.js is available (interpreted, no build step)"
	@echo "  make build-fastapi  Setup Python venv and install FastAPI + uvicorn"
	@echo "  make build-flask    Setup Python venv and install Flask + gunicorn"
	@echo ""
	@echo "Run:"
	@echo "  make bench          Run scaling benchmark (all detected implementations)"
	@echo "  make bench-perf     Run perf-profiled benchmark (Scheme only)"
	@echo "  make report         Generate HTML report from CSV results"
	@echo ""
	@echo "Other:"
	@echo "  make clean          Remove bin/, results/, and all build artifacts"
	@echo "  make help           Show this help"

build-scheme:
	@echo "Building letloop implementation..."
	@mkdir -p bin
	@# No `| tail -1`: letloop reports by name any library it could not
	@# fold into the program, and that has to be seen, not swallowed.
	cd .. && ./local/bin/letloop compile --optimize-level=3 ./examples ./benchmarks/scheme ./benchmarks/scheme/bench-server.scm main
	mv ../a.out bin/letloop-server
	@echo "✓ letloop built"

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

build-cl:
	@echo "Building Common Lisp implementation..."
	@mkdir -p bin
	@sbcl --noinform --non-interactive \
		--load /mnt/quicklisp/setup.lisp \
		--eval '(ql:quickload "hunchentoot" :silent t)' \
		--load cl/server.lisp \
		--eval '(sb-ext:save-lisp-and-die "bin/cl-server" :toplevel (function main) :executable t)'
	@echo "✓ Common Lisp (Hunchentoot) built"

build-ruby:
	@if command -v ruby >/dev/null 2>&1 && ruby -e 'require "falcon"' 2>/dev/null; then \
		echo "✓ Ruby + Falcon available"; \
	else \
		echo "✗ Ruby or Falcon gem not found (gem install falcon)"; exit 1; \
	fi

build-java-loom:
	@echo "Building Java virtual threads implementation..."
	@cd java-loom && javac Server.java
	@echo "✓ Java (Loom) built"

build-java-vertx:
	@echo "Building Java Vert.x implementation..."
	@cd java-vertx && mvn package -q
	@echo "✓ Java (Vert.x) built"

build-rust:
	@echo "Building Rust implementation..."
	@cd rust && cargo build --release 2>&1 | grep -v "Compiling\|Finished" || true
	@echo "✓ Rust built"

build-bun-canary:
	@if command -v bun-canary >/dev/null 2>&1; then \
		echo "✓ bun-canary available: $$(bun-canary --version)"; \
	else \
		echo "✗ bun-canary not found"; exit 1; \
	fi

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

report:
	@bash gen-report.sh

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf bin results
	@rm -rf rust/target rust/Cargo.lock
	@rm -rf gleam/build
	@rm -rf h2o-dep
	@rm -f java-loom/*.class
	@rm -rf java-vertx/target
	@rm -rf fastapi/venv flask/venv
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -delete
	@echo "✓ Clean complete"

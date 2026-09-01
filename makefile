.PHONY: help letloop letloop-libraries argon2 blake3 sodium oprf opaque liburing picohttpparser dependencies check shaders font-bundle

SCHEME=$(shell which scheme)
PWD=$(shell pwd)
LETLOOP=$(shell which letloop)
SHELL=/bin/bash
PREFIX=$(PWD)/local

# Which ChezScheme to build. There is no v10.5.0 tag upstream: main carries
# scheme-version #x0a050001, i.e. 10.5.0-pre-release.1, while the latest
# release tag is v10.4.1. Pin this to a tag when one lands.
CHEZ_REF=main

help: ## Help!...
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

./local/bin/scheme: chezscheme

chezscheme: ## Compile chezscheme $(CHEZ_REF) into $(PREFIX)
	rm -rf $(PREFIX)/src/chezscheme
	mkdir -p $(PREFIX)/src
	cd $(PREFIX)/src && git clone https://github.com/cisco/chezscheme
	cd $(PREFIX)/src/chezscheme && git checkout $(CHEZ_REF)
	cd $(PREFIX)/src/chezscheme && ./configure --threads --disable-x11 --disable-curses --kernelobj --installprefix=$(PREFIX)/
	cd $(PREFIX)/src/chezscheme && make -j$(shell nproc --ignore 1)
	cd $(PREFIX)/src/chezscheme && make install

letloop: clean src/letloop-main.c src/letloop-usage.md src/letloop/base.scm ## Produce the letloop binary from letloop/base.scm's letloop-main, and install it
	echo $(SCHEME)
	$(SCHEME) --version
	echo '(source-directories (list "./src/")) (generate-wpo-files #t)(import (letloop base)) (letloop-compile (list "./src/" "src/letloop/base.scm" "letloop-main"))' | $(SCHEME) --quiet --libdirs ./src/ --compile-imported-libraries
	@# The ./a.out written here is built on upstream scheme, whose main
	@# knows nothing of the appended payload -- only its boot file is any
	@# use to us, and the binary is assembled below.
	test -s a.out.boot
	rm -f a.out
	@# letloop ships the way Chez itself does: the scheme executable under
	@# another name, which makes it load the boot file that goes by that
	@# name. The boot image is amalgamated and holds nothing but the CLI --
	@# (letloop base) imports no letloop library, it resolves them at run
	@# time from $(PREFIX)/lib/letloop instead. That keeps startup at the
	@# bare Chez floor, 33ms rather than 69ms, and leaves every library
	@# name free for a user program to import.
	@# letloop is one self-contained file: src/letloop-main.c, then the
	@# boot image, then a 16-byte trailer giving its length. That main
	@# parses NO arguments -- Chez's own would claim --help, --version,
	@# --optimize-level, --libdirs and a dozen more before any Scheme
	@# ran, at any position on the line -- and it finds its boot by
	@# reading the trailer from /proc/self/exe, so the binary needs
	@# nothing beside it. letloop.boot is installed too: it is what
	@# --visible-libraries folds into a program.
	@#
	@# The same shape is what `letloop compile` produces, by copying its
	@# own host and appending a different boot. No C compiler runs there.
	BOOT=$$(dirname $$(readlink -f $(SCHEME))); \
	  STATIC_FLAG=""; \
	  case "$$(cc -dumpmachine)" in *musl*) STATIC_FLAG="-static" ;; esac; \
	  cc -I"$$BOOT" src/letloop-main.c "$$BOOT/kernel.o" \
	     -o "$$BOOT/letloop-host" $$STATIC_FLAG -ldl -lm -lpthread; \
	  install -m 644 a.out.boot "$$BOOT/letloop.boot"; \
	  { cat "$$BOOT/letloop-host" a.out.boot; \
	    n=$$(stat -c%s a.out.boot); i=0; \
	    while [ $$i -lt 8 ]; do \
	      printf "\\$$(printf '%03o' $$((n % 256)))"; \
	      n=$$((n / 256)); i=$$((i + 1)); \
	    done; \
	    printf 'LETLOOP\1'; } > "$$BOOT/letloop.tmp"; \
	  chmod 755 "$$BOOT/letloop.tmp"; \
	  mv -f "$$BOOT/letloop.tmp" "$$BOOT/letloop"; \
	  rm -f a.out.boot; \
	  mkdir -p $(PREFIX)/bin; \
	  ln -srf "$$BOOT/letloop" $(PREFIX)/bin/letloop; \
	  echo "Installed $$BOOT/letloop and $(PREFIX)/bin/letloop"
	$(MAKE) letloop-libraries
	@echo What is done is not to be done!

# Optimize levels to prime the object cache for. 0 is what `letloop
# compile` defaults to, 3 is what the benchmarks ask for. Any other level
# is compiled on demand, into its own cache directory, the first time a
# program is built at it.
CACHE_LEVELS=0 3

letloop-libraries: ## Install letloop's sources and their per-level .wpo cache into $(PREFIX)/lib/letloop
	rm -rf $(PREFIX)/lib/letloop
	mkdir -p $(PREFIX)/lib/letloop/src
	cp -a src/letloop $(PREFIX)/lib/letloop/src/
	@# One pass per level, and one pass only: .wpo files from separate
	@# compilations disagree ("does not define expected compilation
	@# instance of library").
	for level in $(CACHE_LEVELS); do \
	  $(SCHEME) --quiet --script scripts/library-cache.ss \
	    $(PREFIX)/lib/letloop/src $(PREFIX)/lib/letloop/obj/$$level $$level || exit 1; \
	done
	$(SCHEME) --version > $(PREFIX)/lib/letloop/STAMP

font-bundle: ## Regenerate font-bundled.scm from FullCyrAsia-DejaVu30x16.psf.gz (PSF2, ~32K, ASCII coverage)
	@command -v gunzip >/dev/null || { echo "gunzip required"; exit 1; }
	@FONT=/usr/share/consolefonts/FullCyrAsia-DejaVu30x16.psf.gz; \
	  test -e "$$FONT" || { echo "$$FONT not found — install console-setup-linux"; exit 1; }; \
	  gunzip -c "$$FONT" > /tmp/letloop-bundled.psf
	python3 scripts/psf-to-scheme.py /tmp/letloop-bundled.psf bundled-psf2 \
	  > src/letloop/desktop/font-bundled.scm
	@echo "Regenerated src/letloop/desktop/font-bundled.scm"

shaders: ## Recompile desktop SPIR-V from GLSL into shader.scm (needs glslangValidator)
	@command -v glslangValidator >/dev/null || { \
	  echo "glslangValidator not found — install glslang-tools or download from https://github.com/KhronosGroup/glslang/releases"; \
	  exit 1; \
	}
	glslangValidator -V src/letloop/desktop/shaders/text.vert -o /tmp/text.vert.spv
	glslangValidator -V src/letloop/desktop/shaders/text.frag -o /tmp/text.frag.spv
	@printf '%s\n' \
	  ';; SPIR-V bytecode for the text-rendering pipeline.' \
	  ';;' \
	  ';; Generated by `make shaders` from src/letloop/desktop/shaders/' \
	  ';; {text.vert,text.frag}. The bytevectors are checked in so a clean' \
	  ';; build does not need a SPIR-V compiler.' \
	  '(library (letloop desktop shader)' \
	  '  (export text-vertex-spirv text-fragment-spirv)' \
	  '  (import (chezscheme))' \
	  '' > src/letloop/desktop/shader.scm
	python3 scripts/spv-to-scheme.py /tmp/text.vert.spv text-vertex-spirv >> src/letloop/desktop/shader.scm
	python3 scripts/spv-to-scheme.py /tmp/text.frag.spv text-fragment-spirv >> src/letloop/desktop/shader.scm
	@echo ')' >> src/letloop/desktop/shader.scm
	@echo "Regenerated src/letloop/desktop/shader.scm"

todo: ## So say we all!
	@grep -nR --color=always -B 2 -A 2 TODO src/

xxx: ## For those born under the eye of a wandering star...
	@grep -nR --color=always -B 2 -A 2 XXX src/


liburing:  ## Build liburing from source (skips if $(PREFIX)/lib/liburing.a already exists)
	@if [ -e $(PREFIX)/lib/liburing.a ]; then \
		echo "liburing: $(PREFIX)/lib/liburing.a exists, skipping"; \
	else \
		rm -rf $(PREFIX)/src/liburing && \
		mkdir -p $(PREFIX)/src && \
		cd $(PREFIX)/src && git clone https://github.com/axboe/liburing && \
		cd $(PREFIX)/src/liburing && git checkout liburing-2.14 && \
		cd $(PREFIX)/src/liburing && ./configure --prefix=$(PREFIX)/ && \
		cd $(PREFIX)/src/liburing && make -j$(shell nproc --ignore 1) && \
		cd $(PREFIX)/src/liburing && make liburing.pc && \
		cd $(PREFIX)/src/liburing && make install; \
	fi

argon2: ## Build libargon2 from source (skips if $(PREFIX)/lib/libargon2.so.1 already exists)
	@if [ -e $(PREFIX)/lib/libargon2.so.1 ]; then \
		echo "argon2: $(PREFIX)/lib/libargon2.so.1 exists, skipping"; \
	else \
		rm -rf $(PREFIX)/src/argon2 && \
		mkdir -p $(PREFIX)/src && \
		cd $(PREFIX)/src && git clone https://github.com/P-H-C/phc-winner-argon2 argon2 && \
		cd $(PREFIX)/src/argon2 && git checkout 20190702 && \
		cd $(PREFIX)/src/argon2 && make -j$(shell nproc --ignore 1) && \
		cp $(PREFIX)/src/argon2/libargon2.so.1 $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/argon2/libargon2.a $(PREFIX)/lib/; \
	fi

blake3: ## Build libblake3 from source (skips if $(PREFIX)/lib/libblake3.so already exists)
	@if [ -e $(PREFIX)/lib/libblake3.so ]; then \
		echo "blake3: $(PREFIX)/lib/libblake3.so exists, skipping"; \
	else \
		rm -rf $(PREFIX)/src/blake3 && \
		mkdir -p $(PREFIX)/src && \
		cd $(PREFIX)/src && git clone https://github.com/BLAKE3-team/BLAKE3 blake3 && \
		cd $(PREFIX)/src/blake3 && git checkout 1.8.3 && \
		cd $(PREFIX)/src/blake3/c && \
		if [ "$$(uname -m)" = "x86_64" ]; then \
			BLAKE3_SRC="blake3.c blake3_dispatch.c blake3_portable.c blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S"; \
		else \
			BLAKE3_SRC="blake3.c blake3_dispatch.c blake3_portable.c blake3_neon.c"; \
		fi && \
		gcc -shared -O3 -o libblake3.so -fPIC $$BLAKE3_SRC && \
		gcc -c -O3 -fPIC $$BLAKE3_SRC && \
		ar rcs libblake3.a *.o && \
		cp $(PREFIX)/src/blake3/c/libblake3.so $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/blake3/c/libblake3.a $(PREFIX)/lib/; \
	fi

picohttpparser: ## Build libpicohttpparser from source (skips if $(PWD)/local/lib/libpicohttpparser.so already exists)
	@if [ -e $(PWD)/local/lib/libpicohttpparser.so ]; then \
		echo "picohttpparser: $(PWD)/local/lib/libpicohttpparser.so exists, skipping"; \
	else \
		rm -rf $(PWD)/local/src/picohttpparser && \
		mkdir -p $(PWD)/local/src $(PWD)/local/lib && \
		cd $(PWD)/local/src && git clone https://github.com/h2o/picohttpparser && \
		cp $(PWD)/src/letloop/picohttpparser_wrapper.c $(PWD)/local/src/picohttpparser/ && \
		cd $(PWD)/local/src/picohttpparser && gcc -shared -O3 -o libpicohttpparser.so -fPIC picohttpparser_wrapper.c && \
		cd $(PWD)/local/src/picohttpparser && gcc -c -O3 -fPIC picohttpparser_wrapper.c && ar rcs libpicohttpparser.a picohttpparser_wrapper.o && \
		cp $(PWD)/local/src/picohttpparser/libpicohttpparser.so $(PWD)/local/lib/ && \
		cp $(PWD)/local/src/picohttpparser/libpicohttpparser.a $(PWD)/local/lib/; \
	fi

sodium: ## Build libsodium from source (skips if $(PREFIX)/lib/libsodium.so already exists)
	@if [ -e $(PREFIX)/lib/libsodium.so ]; then \
		echo "sodium: $(PREFIX)/lib/libsodium.so exists, skipping"; \
	else \
		rm -rf $(PREFIX)/src/libsodium && \
		mkdir -p $(PREFIX)/src && \
		cd $(PREFIX)/src && git clone --branch 1.0.22-RELEASE https://github.com/jedisct1/libsodium && \
		cd $(PREFIX)/src/libsodium && ./configure --prefix=$(PREFIX) && \
		cd $(PREFIX)/src/libsodium && make -j$(shell nproc --ignore 1) && \
		cd $(PREFIX)/src/libsodium && make install; \
	fi

oprf: sodium ## Build liboprf from source (skips if $(PREFIX)/lib/liboprf.so already exists)
	@if [ -e $(PREFIX)/lib/liboprf.so ]; then \
		echo "oprf: $(PREFIX)/lib/liboprf.so exists, skipping"; \
	else \
		rm -rf $(PREFIX)/src/liboprf && \
		mkdir -p $(PREFIX)/src && \
		cd $(PREFIX)/src && git clone --branch v0.9.4 https://github.com/stef/liboprf && \
		cd $(PREFIX)/src/liboprf/src && make -C noise_xk all CFLAGS="-Wall -O2 -g -fpic -I$(PREFIX)/include" LDFLAGS="-L$(PREFIX)/lib" && \
		cd $(PREFIX)/src/liboprf/src && $(CC) -Wall -O2 -g -fpic -DHAVE_SODIUM_HKDF=1 -I$(PREFIX)/include -Inoise_xk/include -Inoise_xk/include/karmel -Inoise_xk/include/karmel/minimal -c oprf.c toprf.c dkg.c dkg-vss.c utils.c tp-dkg.c mpmult.c stp-dkg.c toprf-update.c && \
		cd $(PREFIX)/src/liboprf/src && $(LD) -r -o liboprf_merged.o oprf.o toprf.o dkg.o dkg-vss.o utils.o tp-dkg.o mpmult.o stp-dkg.o toprf-update.o && \
		cd $(PREFIX)/src/liboprf/src && $(CC) -Wall -O2 -g -fpic -shared -Wl,-soname,liboprf.so.0 -o liboprf.so liboprf_merged.o -L$(PREFIX)/lib -lsodium -loprf-noiseXK -Lnoise_xk && \
		cd $(PREFIX)/src/liboprf/src && ar rcs liboprf.a oprf.o toprf.o dkg.o dkg-vss.o utils.o tp-dkg.o mpmult.o stp-dkg.o toprf-update.o && \
		mkdir -p $(PREFIX)/lib $(PREFIX)/include/oprf && \
		cp $(PREFIX)/src/liboprf/src/liboprf.so $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/liboprf/src/liboprf.a $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/liboprf/src/noise_xk/liboprf-noiseXK.so $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/liboprf/src/noise_xk/liboprf-noiseXK.a $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/liboprf/src/oprf.h $(PREFIX)/include/oprf/ && \
		cp $(PREFIX)/src/liboprf/src/toprf.h $(PREFIX)/include/oprf/ && \
		cp $(PREFIX)/src/liboprf/src/toprf-update.h $(PREFIX)/include/oprf/ && \
		cp $(PREFIX)/src/liboprf/src/dkg.h $(PREFIX)/include/oprf/ && \
		cp $(PREFIX)/src/liboprf/src/tp-dkg.h $(PREFIX)/include/oprf/ && \
		cp $(PREFIX)/src/liboprf/src/stp-dkg.h $(PREFIX)/include/oprf/ && \
		cp $(PREFIX)/src/liboprf/src/utils.h $(PREFIX)/include/oprf/; \
	fi

opaque: oprf ## Build libopaque from source (skips if $(PREFIX)/lib/libopaque.so already exists)
	@if [ -e $(PREFIX)/lib/libopaque.so ]; then \
		echo "opaque: $(PREFIX)/lib/libopaque.so exists, skipping"; \
	else \
		rm -rf $(PREFIX)/src/libopaque && \
		mkdir -p $(PREFIX)/src && \
		cd $(PREFIX)/src && git clone https://github.com/stef/libopaque && cd libopaque && git checkout 98f6a6e && \
		cd $(PREFIX)/src/libopaque/src && make -j$(shell nproc --ignore 1) libopaque.so libopaque.a PREFIX=$(PREFIX) OPRFINCDIR=$(PREFIX)/include SODIUM_NEWER_THAN_1_0_18=0 CFLAGS="-Wall -O2 -g -fpic -I$(PREFIX)/include -DHAVE_SODIUM_HKDF=1" LDFLAGS="-L$(PREFIX)/lib -lsodium -loprf" && \
		cp $(PREFIX)/src/libopaque/src/libopaque.so $(PREFIX)/lib/ && \
		cp $(PREFIX)/src/libopaque/src/libopaque.a $(PREFIX)/lib/; \
	fi

dependencies: liburing argon2 blake3 picohttpparser opaque ## Build every optional FFI shared-object dependency from source (liburing, argon2, blake3, picohttpparser, sodium, oprf, opaque); each skips if already built

check: dependencies letloop-check.sh clean ## Hit the ground running!
	echo '(source-directories (list "./src/")) (guard (ex (else (exit 1))) (eval (quote (import (letloop base))) (interaction-environment)) (eval (quote (letloop-check (list "./src/"))) (interaction-environment)) (exit 0))' | LD_LIBRARY_PATH=$(PREFIX)/lib/ $(SCHEME) --quiet --libdirs ./src/
	SCHEME=$(SCHEME) LD_LIBRARY_PATH=$(PREFIX)/lib/ LETLOOP=$(LETLOOP) sh letloop-check.sh
	LETLOOP=$(LETLOOP) bash checks/letloop/srp.sh
	LD_LIBRARY_PATH=$(PREFIX)/lib/ LETLOOP=$(LETLOOP) bash checks/check-transparenturing.sh

check-integration: dependencies ## Run the checks that want live services (PostgreSQL at 127.0.0.1:5432); they SKIP-pass without one
	LD_LIBRARY_PATH=$(PREFIX)/lib/ $(LETLOOP) check src/ src/letloop/postgresql/base.scm

stress: clean ## check stress implementations
	LD_LIBRARY_PATH=$(PREFIX)/lib/ LETLOOP=$(LETLOOP) sh checks/stress-transparenturing.sh

check-fail-fast: dependencies letloop-check.sh clean ## Hit the ground running!
	echo '(source-directories (list "./src/")) (guard (ex (else (exit 1))) (eval (quote (import (letloop base))) (interaction-environment)) (eval (quote (letloop-check (list "./src/" "--fail-fast"))) (interaction-environment)) (exit 0))' | LD_LIBRARY_PATH=$(PREFIX)/lib/ $(SCHEME) --quiet --libdirs ./src/
	SCHEME=$(SCHEME) LD_LIBRARY_PATH=$(PREFIX)/lib/ LETLOOP=$(LETLOOP) sh letloop-check.sh
	LETLOOP=$(LETLOOP) bash checks/letloop/srp.sh
	LD_LIBRARY_PATH=$(PREFIX)/lib/ LETLOOP=$(LETLOOP) bash checks/check-transparenturing.sh
	LD_LIBRARY_PATH=$(PREFIX)/lib/ LETLOOP=$(LETLOOP) sh checks/stress-transparenturing.sh

clean:
	$(shell find src/ -name "*.so" | xargs rm -f)
	$(shell find src/ -name "*.wpo" | xargs rm -f)
	$(shell find examples/ -name "*.so" | xargs rm -f)
	$(shell find examples/ -name "*.wpo" | xargs rm -f)
	$(shell find benchmarks/ -name "*.so" | xargs rm -f)
	$(shell find benchmarks/ -name "*.wpo" | xargs rm -f)
	rm -rf /tmp/letloop/

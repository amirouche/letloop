.PHONY: help letloop argon2 blake3 sodium oprf opaque check

SCHEME=$(shell which scheme)
PWD=$(shell pwd)
LETLOOP=$(shell which letloop)
SHELL=/bin/bash

help: ## Help!...
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

./local/bin/scheme: chezscheme

chezscheme: ## Compile latest chezscheme
	rm -rf $(PWD)/local/src/chezscheme
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone https://github.com/cisco/chezscheme
	cd $(PWD)/local/src/chezscheme && git checkout main
	cd $(PWD)/local/src/chezscheme && ./configure --threads  --disable-x11 --disable-curses --kernelobj --installprefix=$(PWD)/local/
	cd $(PWD)/local/src/chezscheme && make -j$(shell nproc --ignore 1)
	cd $(PWD)/local/src/chezscheme && make install

letloop: clean src/letloop-program.c src/letloop-usage.md src/letloop/base.scm ## Produce a.out from letloop/base.scm's procedure called letloop-main
	echo $(SCHEME)
	$(SCHEME) --version
	echo '(generate-wpo-files #t)(import (letloop base)) (letloop-compile (list "./src/" "src/letloop/base.scm" "letloop-main"))' | $(SCHEME) --quiet --libdirs ./src/ --compile-imported-libraries
	cp a.out local/bin/letloop
	@echo What is done is not to be done!

todo: ## So say we all!
	@grep -nR --color=always -B 2 -A 2 TODO src/

xxx: ## For those born under the eye of a wandering star...
	@grep -nR --color=always -B 2 -A 2 XXX src/

argon2: ## Build libargon2 from source
	rm -rf $(PWD)/local/src/argon2
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone https://github.com/P-H-C/phc-winner-argon2 argon2
	cd $(PWD)/local/src/argon2 && make -j$(shell nproc --ignore 1)
	cp $(PWD)/local/src/argon2/libargon2.so.1 $(PWD)/local/lib/
	cp $(PWD)/local/src/argon2/libargon2.a $(PWD)/local/lib/

blake3: ## Build libblake3 from source
	rm -rf $(PWD)/local/src/blake3
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone https://github.com/BLAKE3-team/BLAKE3 blake3
	cd $(PWD)/local/src/blake3/c && gcc -shared -O3 -o libblake3.so -fPIC blake3.c blake3_dispatch.c blake3_portable.c blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S
	cd $(PWD)/local/src/blake3/c && gcc -c -O3 -fPIC blake3.c blake3_dispatch.c blake3_portable.c blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S && ar rcs libblake3.a blake3.o blake3_dispatch.o blake3_portable.o blake3_sse2_x86-64_unix.o blake3_sse41_x86-64_unix.o blake3_avx2_x86-64_unix.o blake3_avx512_x86-64_unix.o
	cp $(PWD)/local/src/blake3/c/libblake3.so $(PWD)/local/lib/
	cp $(PWD)/local/src/blake3/c/libblake3.a $(PWD)/local/lib/

sodium: ## Build libsodium from source
	rm -rf $(PWD)/local/src/libsodium
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone --branch 1.0.21-RELEASE https://github.com/jedisct1/libsodium
	cd $(PWD)/local/src/libsodium && ./configure --prefix=$(PWD)/local
	cd $(PWD)/local/src/libsodium && make -j$(shell nproc --ignore 1)
	cd $(PWD)/local/src/libsodium && make install

oprf: sodium ## Build liboprf from source
	rm -rf $(PWD)/local/src/liboprf
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone --branch v0.9.4 https://github.com/stef/liboprf
	cd $(PWD)/local/src/liboprf/src && make -C noise_xk all CFLAGS="-Wall -O2 -g -fpic -I$(PWD)/local/include" LDFLAGS="-L$(PWD)/local/lib"
	cd $(PWD)/local/src/liboprf/src && $(CC) -Wall -O2 -g -fpic -DHAVE_SODIUM_HKDF=1 -I$(PWD)/local/include -Inoise_xk/include -Inoise_xk/include/karmel -Inoise_xk/include/karmel/minimal -c oprf.c toprf.c dkg.c dkg-vss.c utils.c tp-dkg.c mpmult.c stp-dkg.c toprf-update.c
	cd $(PWD)/local/src/liboprf/src && $(LD) -r -o liboprf_merged.o oprf.o toprf.o dkg.o dkg-vss.o utils.o tp-dkg.o mpmult.o stp-dkg.o toprf-update.o
	cd $(PWD)/local/src/liboprf/src && $(CC) -Wall -O2 -g -fpic -shared -Wl,-soname,liboprf.so.0 -o liboprf.so liboprf_merged.o -L$(PWD)/local/lib -lsodium -loprf-noiseXK -Lnoise_xk
	cd $(PWD)/local/src/liboprf/src && ar rcs liboprf.a oprf.o toprf.o dkg.o dkg-vss.o utils.o tp-dkg.o mpmult.o stp-dkg.o toprf-update.o
	mkdir -p $(PWD)/local/lib $(PWD)/local/include/oprf
	cp $(PWD)/local/src/liboprf/src/liboprf.so $(PWD)/local/lib/
	cp $(PWD)/local/src/liboprf/src/liboprf.a $(PWD)/local/lib/
	cp $(PWD)/local/src/liboprf/src/noise_xk/liboprf-noiseXK.so $(PWD)/local/lib/
	cp $(PWD)/local/src/liboprf/src/noise_xk/liboprf-noiseXK.a $(PWD)/local/lib/
	cp $(PWD)/local/src/liboprf/src/oprf.h $(PWD)/local/include/oprf/
	cp $(PWD)/local/src/liboprf/src/toprf.h $(PWD)/local/include/oprf/
	cp $(PWD)/local/src/liboprf/src/toprf-update.h $(PWD)/local/include/oprf/
	cp $(PWD)/local/src/liboprf/src/dkg.h $(PWD)/local/include/oprf/
	cp $(PWD)/local/src/liboprf/src/tp-dkg.h $(PWD)/local/include/oprf/
	cp $(PWD)/local/src/liboprf/src/stp-dkg.h $(PWD)/local/include/oprf/
	cp $(PWD)/local/src/liboprf/src/utils.h $(PWD)/local/include/oprf/

opaque: oprf ## Build libopaque from source
	rm -rf $(PWD)/local/src/libopaque
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone https://github.com/stef/libopaque && cd libopaque && git checkout 98f6a6e
	cd $(PWD)/local/src/libopaque/src && make -j$(shell nproc --ignore 1) libopaque.so libopaque.a PREFIX=$(PWD)/local OPRFINCDIR=$(PWD)/local/include SODIUM_NEWER_THAN_1_0_18=0 CFLAGS="-Wall -O2 -g -fpic -I$(PWD)/local/include -DHAVE_SODIUM_HKDF=1" LDFLAGS="-L$(PWD)/local/lib -lsodium -loprf"
	cp $(PWD)/local/src/libopaque/src/libopaque.so $(PWD)/local/lib/
	cp $(PWD)/local/src/libopaque/src/libopaque.a $(PWD)/local/lib/

check: argon2 blake3 opaque letloop-check.sh ## Hit the ground running!
	SCHEME=$(SCHEME) LD_LIBRARY_PATH=$(PWD)/local/lib/ LETLOOP=$(LETLOOP) sh letloop-check.sh
	$(LETLOOP) check src/
	sh checks/stress-transparenturing.sh

clean:
	$(shell find src/ -name "*.so" | xargs rm -f)
	$(shell find src/ -name "*.wpo" | xargs rm -f)
	$(shell find examples/ -name "*.so" | xargs rm -f)
	$(shell find examples/ -name "*.wpo" | xargs rm -f)
	rm -rf /tmp/letloop/

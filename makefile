.PHONY: help letloop argon2 blake3 check

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

blake3: ## Build libblake3 from source
	rm -rf $(PWD)/local/src/blake3
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone https://github.com/BLAKE3-team/BLAKE3 blake3
	cd $(PWD)/local/src/blake3/c && gcc -shared -O3 -o libblake3.so -fPIC blake3.c blake3_dispatch.c blake3_portable.c blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S
	cp $(PWD)/local/src/blake3/c/libblake3.so $(PWD)/local/lib/

check: argon2 blake3 letloop-check.sh ## Hit the ground running!
	SCHEME=$(SCHEME) LD_LIBRARY_PATH=$(PWD)/local/lib/ LETLOOP=$(LETLOOP) sh letloop-check.sh

clean:
	$(shell find src/ -name "*.so" | xargs rm -f)
	$(shell find src/ -name "*.wpo" | xargs rm -f)
	$(shell find examples/ -name "*.so" | xargs rm -f)
	$(shell find examples/ -name "*.wpo" | xargs rm -f)
	rm -rf /tmp/letloop/

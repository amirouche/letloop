.PHONY: help binink

SCHEME=$(shell which scheme)
PWD=$(shell pwd)
BININK=$(shell which binink)
SHELL=/bin/bash

help: ## Help!...
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

./local/bin/scheme: chezscheme

chezscheme: ## Compile latest chezscheme
	rm -rf $(PWD)/local/src/chezscheme
	mkdir -p $(PWD)/local/src
	cd $(PWD)/local/src && git clone --filter=blob:none --depth=1 https://github.com/cisco/chezscheme
	cd $(PWD)/local/src/chezscheme && ./configure --threads  --disable-x11 --disable-curses --kernelobj --installprefix=$(PWD)/local/
	cd $(PWD)/local/src/chezscheme && make -j$(shell nproc --ignore 1)
	cd $(PWD)/local/src/chezscheme && make install

binink: src/binink-program.c src/binink-usage.md src/binink/base.scm ## Produce a.out from binink/base.scm's procedure called binink-main
	echo $(SCHEME)
	$(SCHEME) --version
	echo '(generate-wpo-files #t)(import (binink base)) (binink-compile (list "./src/" "src/binink/base.scm" "binink-main"))' | $(SCHEME) --quiet --libdirs ./src/ --compile-imported-libraries
	@echo What is done is not to be done!

todo: ## So say we all!
	@grep -nR --color=always -B 2 -A 2 TODO binink/

xxx: ## For those born under the eye of a wandering star...
	@grep -nR --color=always -B 2 -A 2 XXX binink/

check: binink-check.sh ## Hit the ground running!
	SCHEME=$(SCHEME) LD_LIBRARY_PATH=$(PWD)/local/lib/ BININK=$(BININK) sh binink-check.sh

clean:
	rm -rf /tmp/binink/

.PHONY: help letloop

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
	cd $(PWD)/local/src/chezscheme && git checkout v10.3.0
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

check: letloop-check.sh ## Hit the ground running!
	SCHEME=$(SCHEME) LD_LIBRARY_PATH=$(PWD)/local/lib/ LETLOOP=$(LETLOOP) sh letloop-check.sh

clean:
	$(shell find src/ -name "*.so" | xargs rm -f)
	$(shell find src/ -name "*.wpo" | xargs rm -f)
	rm -rf /tmp/letloop/

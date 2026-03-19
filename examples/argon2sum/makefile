build:
	letloop compile . argon2sum.scm main -- -rdynamic -Wl,-Bstatic -largon2 -Wl,-Bdynamic

check: build
	./a.out verify $$(./a.out encode mypassword) mypassword
	@echo "check passed"

clean:
	rm -f a.out *.so *.wpo

.PHONY: build check clean

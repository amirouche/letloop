#!/usr/bin/sh

set -x

# XXX: Illegal according to github actions.
# set +o pipefail

ROOT=$(pwd)

echo '(scheme-version)' | $LETLOOP repl

# Check that check that is erroring exit with a non-zero code
$LETLOOP check checks/check/ checks/check/check-error.scm
if [ $? -eq 0 ]; then
  exit 1
fi

# Check that check that is failure exit with a non-zero code
$LETLOOP check checks/check/ checks/check/check-fail.scm
if [ $? -eq 0 ]; then
  exit 1
fi

# Check that check that empty checks exit with a non-zero code
$LETLOOP check checks/check/ checks/check/check-empty.scm
if [ $? -eq 0 ]; then
  exit 1
fi

# Check that check that one successfull check exit with zero exit code
$LETLOOP check checks/check/ checks/check/check-success.scm
if [ $? -eq 0 ]; then
  echo success
else
  exit 1
fi

# Check that the output is what is expected
EXPECTED="b4907e17e91609ea83394b6079794395"
GIVEN=$($LETLOOP check --dry-run checks/check/ checks/check/check-success.scm | md5sum | cut -d " " -f1)
if [ "x$GIVEN" = "x$EXPECTED" ]; then
  echo "success!"
else
  echo "failure..."
  exit 1
fi


# Testing compiling a library into a program without dependencies

# check compilation succeed
$LETLOOP compile checks/ checks/example.scm main
if [ $? -eq 0 ]; then
  echo example compile success
else
  exit 1
fi

# check execution succeed
./a.out
if [ $? -eq 0 ]; then
  echo success
  rm a.out
else
  exit 1
fi

# Testing letoop compile, and libraries embedding

# executing the procedure code-usage at checks/codex/base.scm works
$LETLOOP exec checks/ checks/codex/base.scm codex-usage
if [ $? -eq 0 ]; then
  echo codex execute success
else
  exit 1
fi

# compilation succeed
$LETLOOP compile checks/ checks/codex/base.scm codex-usage
if [ $? -eq 0 ]; then
  echo codex compile success
else
  exit 1
fi

# compiled artifact works
./a.out
if [ $? -eq 0 ]; then
  echo codex compiled exec success
  rm a.out
else
  exit 1
fi

# a program linking a C static library: the archive is a positional
# argument recognised by its .a suffix, and its symbols resolve through
# plain foreign-procedure with no shared object anywhere
cc -c checks/staticlib/arith.c -o /tmp/letloop-check-arith.o
if [ $? -ne 0 ]; then
  echo "cannot compile the static library fixture"
  exit 1
fi
ar rcs /tmp/letloop-check-libarith.a /tmp/letloop-check-arith.o
if [ $? -ne 0 ]; then
  echo "cannot archive the static library fixture"
  exit 1
fi

# deliberately before the procedure name: position must not matter
$LETLOOP compile checks/ checks/staticlib/base.scm /tmp/letloop-check-libarith.a staticlib-usage
if [ $? -eq 0 ]; then
  echo staticlib compile success
else
  exit 1
fi

./a.out | grep -q "static library add: 42"
if [ $? -eq 0 ]; then
  echo staticlib compiled exec success
else
  echo "the static library program did not produce the expected output"
  exit 1
fi

# and it is relocatable: nothing beside it, run from somewhere else
STATICLIB_ELSEWHERE=$(mktemp -d)
cp a.out "$STATICLIB_ELSEWHERE/a.out"
"$STATICLIB_ELSEWHERE/a.out" | grep -q "static library add: 42"
if [ $? -eq 0 ]; then
  echo staticlib relocated exec success
  rm -rf "$STATICLIB_ELSEWHERE"
  rm -f a.out a.out.boot /tmp/letloop-check-arith.o /tmp/letloop-check-libarith.a
else
  echo "the static library program does not run relocated"
  exit 1
fi

echo win

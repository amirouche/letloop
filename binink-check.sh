#!/usr/bin/sh

set -x

# XXX: Illegal according to github actions.
# set +o pipefail

ROOT=$(pwd)

echo '(scheme-version)' | $BININK repl

# Check that check that is erroring exit with a non-zero code
$BININK check checks/check/ checks/check/check-error.scm
if [ $? -eq 0 ]; then
  exit 1
fi

# Check that check that is failure exit with a non-zero code
$BININK check checks/check/ checks/check/check-fail.scm
if [ $? -eq 0 ]; then
  exit 1
fi

# Check that check that empty checks exit with a non-zero code
$BININK check checks/check/ checks/check/check-empty.scm
if [ $? -eq 0 ]; then
  exit 1
fi

# Check that check that one successfull check exit with zero exit code
$BININK check checks/check/ checks/check/check-success.scm
if [ $? -eq 0 ]; then
  echo success
else
  exit 1
fi

# Check that the output is what is expected
EXPECTED="b4907e17e91609ea83394b6079794395"
GIVEN=$($BININK check --dry-run checks/check/ checks/check/check-success.scm | md5sum | cut -d " " -f1)
if [ "x$GIVEN" = "x$EXPECTED" ]; then
  echo "success!"
else
  echo "failure..."
  exit 1
fi


# Testing compiling a library into a program without dependencies

# check compilation succeed
$BININK compile checks/ checks/example.scm main
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
$BININK exec checks/ checks/codex/base.scm codex-usage
if [ $? -eq 0 ]; then
  echo codex execute success
else
  exit 1
fi

# compilation succeed
$BININK compile checks/ checks/codex/base.scm codex-usage
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

echo win

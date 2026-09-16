#!/usr/bin/env bash
# The checks, on three targets, because a target is where this library breaks.
#
#   ./test/run.sh
#
# `--interp` is the fast one. `-cpp` is a static target with dynamic arrays.
# `-hl` is compiled and run only when a HashLink runtime is at hand: it is the
# target where an `Array<Null<Float>>` is genuinely not an `Array<Float>`, and
# where the Farceur session's first icon brought the process down.

set -u
cd "$(dirname "$0")/.."
work=$(mktemp -d)
failures=0

echo "nui — interpreted"
haxe -cp src -cp test -lib rui -main Check --interp || failures=1

echo ""
echo "nui — compiled (hxcpp)"
haxe -cp src -cp test -lib rui -main Check -cpp "$work/cpp" > /dev/null || failures=1
"$work/cpp/Check" || failures=1

echo ""
echo "nui — HashLink"
if haxe -cp src -cp test -lib rui -main Check -hl "$work/check.hl" > /dev/null; then
	if command -v hl > /dev/null; then
		hl "$work/check.hl" || failures=1
	else
		echo "     compiles; no hl runtime here to run it with"
	fi
else
	failures=1
fi

rm -rf "$work"
exit "$failures"

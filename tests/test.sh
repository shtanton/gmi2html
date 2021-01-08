#!/usr/bin/sh
if cat tests/source.gmi | zig build run | diff -q tests/target.html - >/dev/null
then
    echo "ALL TESTS PASSED"
else
    echo "FAIL: translated tests/source.gmi did not match tests/target.html"
fi

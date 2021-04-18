#!/usr/bin/sh
zig build
if ./zig-cache/bin/gmi2html < tests/source.gmi | diff -q tests/target.html - >/dev/null
then
    :
else
    echo "FAIL: translated tests/source.gmi did not match tests/target.html"
    exit 1
fi

if ./zig-cache/bin/gmi2html --inline-images < tests/source.gmi | diff -q tests/image_target.html - >/dev/null
then
    :
else
    echo "FAIL: translation with inlined images did not match tests/image_target.html"
    exit 1
fi

if ./zig-cache/bin/gmi2html --inline-video < tests/source.gmi | diff -q tests/video_target.html - >/dev/null
then
    :
else
    echo "FAIL: translation with inlined video did not match tests/video_target.html"
    exit 1
fi

if ./zig-cache/bin/gmi2html --inline-audio < tests/source.gmi | diff -q tests/audio_target.html - >/dev/null
then
    :
else
    echo "FAIL: translation with inlined audio did not match tests/audio_target.html"
    exit 1
fi

if ./zig-cache/bin/gmi2html --inline-all < tests/source.gmi | diff -q tests/inlined_target.html - >/dev/null
then
    :
else
    echo "FAIL: translation with inlined everything did not match tests/inlined_target.html"
    exit 1
fi

echo "ALL TESTS PASSED"

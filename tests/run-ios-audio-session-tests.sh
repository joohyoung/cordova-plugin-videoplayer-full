#!/bin/sh
set -eu

test_output_dir=$(mktemp -d)
trap 'rm -rf "$test_output_dir"' EXIT HUP INT TERM

xcrun clang \
    -fobjc-arc \
    -framework Foundation \
    -Isrc/ios \
    src/ios/VideoPlayerAudioSessionManager.m \
    tests/ios/VideoPlayerAudioSessionManagerTests.m \
    -o "$test_output_dir/VideoPlayerAudioSessionManagerTests"

"$test_output_dir/VideoPlayerAudioSessionManagerTests"

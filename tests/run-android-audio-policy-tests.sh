#!/bin/sh
set -eu

test_output_dir="$(mktemp -d)"
trap 'rm -rf "$test_output_dir"' EXIT HUP INT TERM

javac \
    -d "$test_output_dir" \
    src/android/VideoPlayerAudioPolicy.java \
    tests/android/VideoPlayerAudioPolicyTests.java

java -cp "$test_output_dir" com.joohyoung.cordova.videoplayer.VideoPlayerAudioPolicyTests

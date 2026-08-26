var assert = require("assert");
var fs = require("fs");
var path = require("path");

var source = fs.readFileSync(
    path.join(__dirname, "../src/ios/VideoPlayer.m"),
    "utf8"
);

function methodBody(startMarker, endMarker) {
    var start = source.indexOf(startMarker);
    var end = source.indexOf(endMarker, start + startMarker.length);

    assert.notStrictEqual(start, -1, "missing method: " + startMarker);
    assert.notStrictEqual(end, -1, "missing method boundary: " + endMarker);
    return source.slice(start, end);
}

var playMethod = methodBody(
    "- (void)play:(CDVInvokedUrlCommand*)command\n{",
    "- (void)close:(CDVInvokedUrlCommand*)command;\n{"
);
assert(
    playMethod.indexOf("NSString *mediaUrl") <
        playMethod.indexOf("captureAudioSessionBeforePlayback"),
    "media URL must be validated before changing the audio session"
);
assert(playMethod.includes("AVAudioSessionCategoryAmbient"));
assert(playMethod.includes("AVAudioSessionCategoryPlayback"));
assert(playMethod.includes("capturePlaybackAudioSessionConfiguration"));
assert(playMethod.includes("restoreAudioSessionIfNeeded"));

var snapshotMethod = methodBody(
    "- (void)captureAudioSessionBeforePlayback:(AVAudioSession *)audioSession\n{",
    "- (void)capturePlaybackAudioSessionConfiguration:(AVAudioSession *)audioSession\n{"
);
assert(snapshotMethod.includes("audioSessionMatchesPlaybackConfiguration"));
assert(snapshotMethod.includes("discardAudioSessionSnapshot"));
[
    "audioSession.category",
    "audioSession.mode",
    "audioSession.categoryOptions",
    "audioSession.routeSharingPolicy"
].forEach(function (value) {
    assert(snapshotMethod.includes(value), "snapshot must include " + value);
});

var ownershipMethod = methodBody(
    "- (BOOL)audioSessionMatchesPlaybackConfiguration:(AVAudioSession *)audioSession\n{",
    "- (void)restoreAudioSessionIfNeeded\n{"
);
[
    "audioSessionCategoryForPlayback",
    "audioSessionModeForPlayback",
    "audioSessionOptionsForPlayback",
    "audioSessionRouteSharingPolicyForPlayback"
].forEach(function (value) {
    assert(ownershipMethod.includes(value), "ownership check must include " + value);
});

var restoreMethod = methodBody(
    "- (void)restoreAudioSessionIfNeeded\n{",
    "- (void)discardAudioSessionSnapshot\n{"
);
assert(restoreMethod.includes("audioSessionMatchesPlaybackConfiguration"));
assert(restoreMethod.includes("routeSharingPolicy:audioSessionRouteSharingPolicyBeforePlayback"));
assert(restoreMethod.includes("options:audioSessionOptionsBeforePlayback"));
assert(restoreMethod.includes("AVAudioSession restore configuration error"));

var restoreCalls = source.match(/\[self restoreAudioSessionIfNeeded\]/g) || [];
assert.strictEqual(
    restoreCalls.length,
    4,
    "restore must run for activation failure, close, completion, and tap"
);

console.log("iOS audio session source contract tests passed");

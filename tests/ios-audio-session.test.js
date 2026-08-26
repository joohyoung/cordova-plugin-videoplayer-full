var assert = require("assert");
var fs = require("fs");
var path = require("path");

var source = fs.readFileSync(
    path.join(__dirname, "../src/ios/VideoPlayer.m"),
    "utf8"
);
var pluginXml = fs.readFileSync(path.join(__dirname, "../plugin.xml"), "utf8");

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
        playMethod.indexOf("captureBeforePlayback"),
    "media URL must be validated before changing the audio session"
);
assert(playMethod.includes("AVAudioSessionCategoryAmbient"));
assert(playMethod.includes("AVAudioSessionCategoryPlayback"));
assert(playMethod.includes("capturePlaybackConfiguration"));
assert(playMethod.includes("restoreAudioSessionIfNeeded"));

var restoreMethod = methodBody(
    "- (void)restoreAudioSessionIfNeeded\n{",
    "- (VideoPlayerAudioSessionManager *)audioSessionManager\n{"
);
assert(restoreMethod.includes("restoreSessionIfNeeded"));
assert(restoreMethod.includes("AVAudioSession restore configuration error"));

var restoreCalls = source.match(/\[self restoreAudioSessionIfNeeded\]/g) || [];
assert.strictEqual(
    restoreCalls.length,
    4,
    "restore must run for activation failure, close, completion, and tap"
);

assert(pluginXml.includes('src="src/ios/VideoPlayerAudioSessionManager.h"'));
assert(pluginXml.includes('src="src/ios/VideoPlayerAudioSessionManager.m"'));

console.log("iOS audio session source contract tests passed");

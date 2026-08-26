var assert = require("assert");
var Module = require("module");

function loadVideoPlayer() {
    var calls = [];
    var originalLoad = Module._load;

    Module._load = function (request, parent, isMain) {
        if (request === "cordova/exec") {
            return function () {
                calls.push(Array.prototype.slice.call(arguments));
            };
        }

        return originalLoad.call(this, request, parent, isMain);
    };

    var modulePath = require.resolve("../www/videoplayer");
    delete require.cache[modulePath];

    try {
        return {
            calls: calls,
            videoPlayer: require(modulePath)
        };
    } finally {
        Module._load = originalLoad;
    }
}

function playOptionsFor(options) {
    var loaded = loadVideoPlayer();
    loaded.videoPlayer.play("file:///movie.mp4", options);

    assert.strictEqual(loaded.calls.length, 1);
    assert.strictEqual(loaded.calls[0][2], "VideoPlayer");
    assert.strictEqual(loaded.calls[0][3], "play");
    return loaded.calls[0][4][1];
}

var defaultOptions = playOptionsFor();
assert.strictEqual(defaultOptions.volume, 1.0);
assert.strictEqual(defaultOptions.scalingMode, 1);
assert.strictEqual(defaultOptions.respectSilentMode, false);

var silentModeOptions = playOptionsFor({
    respectSilentMode: true,
    volume: 0.5
});
assert.strictEqual(silentModeOptions.respectSilentMode, true);
assert.strictEqual(silentModeOptions.volume, 0.5);
assert.strictEqual(silentModeOptions.scalingMode, 1);

var consecutiveCalls = loadVideoPlayer();
consecutiveCalls.videoPlayer.play("file:///movie.mp4", {
    respectSilentMode: true
});
consecutiveCalls.videoPlayer.play("file:///movie.mp4", {
    respectSilentMode: false
});
consecutiveCalls.videoPlayer.play("file:///movie.mp4", {
    respectSilentMode: true
});

assert.strictEqual(consecutiveCalls.calls.length, 3);
assert.strictEqual(consecutiveCalls.calls[0][4][1].respectSilentMode, true);
assert.strictEqual(consecutiveCalls.calls[1][4][1].respectSilentMode, false);
assert.strictEqual(consecutiveCalls.calls[2][4][1].respectSilentMode, true);

console.log("videoplayer option tests passed");

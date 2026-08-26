"use strict";

var assert = require("assert");
var fs = require("fs");
var path = require("path");

var androidSource = fs.readFileSync(
    path.join(__dirname, "../src/android/VideoPlayer.java"),
    "utf8"
);
var pluginXml = fs.readFileSync(path.join(__dirname, "../plugin.xml"), "utf8");
var readme = fs.readFileSync(path.join(__dirname, "../README.md"), "utf8");

assert(androidSource.includes("options.optBoolean(\"respectSilentMode\", false)"));
assert(androidSource.includes("audioManager.getRingerMode()"));
assert(androidSource.includes("AudioManager.RINGER_MODE_SILENT"));
assert(androidSource.includes("AudioManager.RINGER_MODE_VIBRATE"));
assert(androidSource.includes("player.setOnPreparedListener(mp ->"));
assert(
    androidSource.indexOf("float effectiveVolume = effectivePlaybackVolume(") <
        androidSource.indexOf("VideoPlayer.this.onPrepared(mp);")
);
assert(!androidSource.includes("getCurrentInterruptionFilter"));
assert(!androidSource.includes("setRingerMode("));
assert(!androidSource.includes("setStreamVolume("));
assert(pluginXml.includes('src="src/android/VideoPlayerAudioPolicy.java"'));
assert(readme.includes("checks the ringer mode immediately before playback starts"));
assert(readme.includes("does not monitor later ringer-mode changes"));
assert(readme.includes("does not change the device's media volume, ringer mode, or Do Not Disturb policy"));

console.log("Android silent mode source contract tests passed");

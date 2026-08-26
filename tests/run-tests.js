var path = require("path");
var childProcess = require("child_process");

require("./videoplayer.test");
require("./ios-audio-session.test");
require("./android-silent-mode.test");

var releaseResult = childProcess.spawnSync(
    "sh",
    [path.join(__dirname, "run-release-skill-tests.sh")],
    { stdio: "inherit" }
);

if (releaseResult.error) {
    throw releaseResult.error;
}
if (releaseResult.status !== 0) {
    process.exit(releaseResult.status === null ? 1 : releaseResult.status);
}

var javacResult = childProcess.spawnSync("javac", ["-version"], { stdio: "ignore" });
if (!javacResult.error && javacResult.status === 0) {
    var androidResult = childProcess.spawnSync(
        "sh",
        [path.join(__dirname, "run-android-audio-policy-tests.sh")],
        { stdio: "inherit" }
    );

    if (androidResult.error) {
        throw androidResult.error;
    }
    if (androidResult.status !== 0) {
        process.exit(androidResult.status === null ? 1 : androidResult.status);
    }
} else {
    console.log("native Android audio policy tests skipped because javac is unavailable");
}

if (process.platform === "darwin") {
    var result = childProcess.spawnSync(
        "sh",
        [path.join(__dirname, "run-ios-audio-session-tests.sh")],
        { stdio: "inherit" }
    );

    if (result.error) {
        throw result.error;
    }
    if (result.status !== 0) {
        process.exit(result.status === null ? 1 : result.status);
    }
} else {
    console.log("native iOS audio session tests skipped on non-macOS host");
}

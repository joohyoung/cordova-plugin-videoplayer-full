var path = require("path");
var childProcess = require("child_process");

require("./videoplayer.test");
require("./ios-audio-session.test");

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

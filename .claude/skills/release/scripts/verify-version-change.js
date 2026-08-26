"use strict";

var childProcess = require("child_process");
var fs = require("fs");

function fail(message) {
    console.error(message);
    process.exit(1);
}

function git(args) {
    try {
        return childProcess.execFileSync("git", args, {
            encoding: "utf8",
            stdio: ["ignore", "pipe", "pipe"]
        });
    } catch (error) {
        fail("git " + args.join(" ") + " 실행 실패");
    }
}

function readBlob(commit, file) {
    return git(["show", commit + ":" + file]);
}

function treeMode(commit, file) {
    var output = git(["ls-tree", commit, "--", file]).trim();
    var match = output.match(/^(100644|100755)\s+blob\s+[0-9a-f]+\t/);
    if (!match) {
        fail(commit + "의 " + file + "이 regular blob이 아닙니다");
    }
    return match[1];
}

function indexMode(file) {
    var output = git(["ls-files", "-s", "--", file]).trim();
    var match = output.match(/^(100644|100755)\s+[0-9a-f]+\s+0\t/);
    if (!match || output.indexOf("\n") !== -1) {
        fail("인덱스의 " + file + "이 단일 regular file이 아닙니다");
    }
    var stat;
    try {
        stat = fs.lstatSync(file);
    } catch (error) {
        fail(file + " lstat 실패: " + error.message);
    }
    if (!stat.isFile() || stat.isSymbolicLink()) {
        fail("작업 트리의 " + file + "이 regular file이 아닙니다");
    }
    return match[1];
}

function stringTokenEnd(text, start) {
    var escaped = false;
    for (var index = start + 1; index < text.length; index += 1) {
        var character = text[index];
        if (escaped) {
            escaped = false;
        } else if (character === "\\") {
            escaped = true;
        } else if (character === "\"") {
            return index + 1;
        }
    }
    fail("package.json 문자열이 닫히지 않았습니다");
}

function packageVersionRange(text) {
    var depth = 0;
    var found = null;
    for (var index = 0; index < text.length;) {
        var character = text[index];
        if (character === "\"") {
            var end = stringTokenEnd(text, index);
            if (depth === 1 && JSON.parse(text.slice(index, end)) === "version") {
                var cursor = end;
                while (/\s/.test(text[cursor] || "")) cursor += 1;
                if (text[cursor] === ":") {
                    cursor += 1;
                    while (/\s/.test(text[cursor] || "")) cursor += 1;
                    if (text[cursor] !== "\"") fail("package.json 최상위 version이 문자열이 아닙니다");
                    var valueEnd = stringTokenEnd(text, cursor);
                    if (found) fail("package.json 최상위 version 필드가 중복됩니다");
                    found = { start: cursor, end: valueEnd };
                }
            }
            index = end;
        } else {
            if (character === "{" || character === "[") depth += 1;
            if (character === "}" || character === "]") depth -= 1;
            index += 1;
        }
    }
    if (!found) fail("package.json 최상위 version 필드를 찾지 못했습니다");
    return found;
}

function pluginVersionRange(text) {
    var masked = text.replace(/<!--[\s\S]*?-->/g, function (comment) {
        return comment.replace(/[^\n]/g, " ");
    });
    var tag = masked.match(/<plugin(?=[\s>\/])[^>]*>/);
    if (!tag) fail("plugin.xml 루트 <plugin> 여는 태그를 찾지 못했습니다");
    var attributes = /\s([A-Za-z_:][-\w:.]*)\s*=\s*(["'])([^"']*)\2/g;
    var found = null;
    var match;
    while ((match = attributes.exec(tag[0])) !== null) {
        if (match[1] === "version") {
            if (found) fail("plugin.xml 루트 version 속성이 중복됩니다");
            var quoted = match[2] + match[3] + match[2];
            var relative = match[0].lastIndexOf(quoted) + 1;
            found = {
                start: tag.index + match.index + relative,
                end: tag.index + match.index + relative + match[3].length
            };
        }
    }
    if (!found) fail("plugin.xml 루트 version 속성을 찾지 못했습니다");
    return found;
}

function replaceRange(text, range, value) {
    return text.slice(0, range.start) + value + text.slice(range.end);
}

var base = process.argv[2];
var expectedVersion = process.argv[3];
var targetCommit = process.argv[4];
if (!/^[0-9a-f]{40,64}$/.test(base || "")) fail("base object ID 형식이 올바르지 않습니다");
if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(expectedVersion || "")) fail("새 버전 형식이 올바르지 않습니다");
if (targetCommit && !/^[0-9a-f]{40,64}$/.test(targetCommit)) fail("target object ID 형식이 올바르지 않습니다");

var files = ["package.json", "plugin.xml"];
files.forEach(function (file) {
    var baseMode = treeMode(base, file);
    var targetMode = targetCommit ? treeMode(targetCommit, file) : indexMode(file);
    if (targetMode !== baseMode) fail(file + "의 mode가 base와 다릅니다");
});

var basePackage = readBlob(base, "package.json");
var targetPackage = targetCommit ? readBlob(targetCommit, "package.json") : fs.readFileSync("package.json", "utf8");
var basePackageRange = packageVersionRange(basePackage);
var basePackageVersion = JSON.parse(basePackage.slice(basePackageRange.start, basePackageRange.end));
var expectedPackage = replaceRange(basePackage, basePackageRange, JSON.stringify(expectedVersion));
if (targetPackage !== expectedPackage) fail("package.json은 최상위 version 이외의 내용도 변경됐습니다");

var basePlugin = readBlob(base, "plugin.xml");
var targetPlugin = targetCommit ? readBlob(targetCommit, "plugin.xml") : fs.readFileSync("plugin.xml", "utf8");
var basePluginRange = pluginVersionRange(basePlugin);
var expectedPlugin = replaceRange(basePlugin, basePluginRange, expectedVersion);
if (targetPlugin !== expectedPlugin) fail("plugin.xml은 루트 plugin version 이외의 내용도 변경됐습니다");

if (basePackageVersion === expectedVersion) fail("새 버전이 base package.json 버전과 같습니다");
JSON.parse(targetPackage);
console.log("version-only change verified: " + basePackageVersion + " -> " + expectedVersion);

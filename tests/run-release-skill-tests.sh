#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
preflight="$repo_root/.claude/skills/release/scripts/preflight.sh"
publish="$repo_root/.claude/skills/release/scripts/publish.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[ "$(readlink "$repo_root/.agents/skills/release")" = "../../.claude/skills/release" ] || fail "release skill symlink target mismatch"
grep -q '^name: release$' "$repo_root/.claude/skills/release/SKILL.md" || fail "release skill frontmatter missing"
grep -q 'git push --atomic origin' "$publish" || fail "atomic push missing"
if grep -E '^[[:space:]]*(if[[:space:]]+![[:space:]]+)?git push' "$publish" | grep -Eq -- '--follow-tags|--tags|--force'; then
    fail "publish script contains a forbidden broad or force push option"
fi

git init --bare "$test_root/origin.git" >/dev/null
git init -b main "$test_root/work" >/dev/null
cd "$test_root/work"
git config user.name "Release Skill Test"
git config user.email "release-skill@example.invalid"

printf '%s\n' '{"name":"release-fixture","version":"1.0.0","scripts":{"test":"node -e \"process.exit(0)\""}}' > package.json
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plugin id="example" version="1.0.0"></plugin>' > plugin.xml
printf '%s\n' 'fixture' > README.md
git add -- package.json plugin.xml README.md
git commit -m "initial" >/dev/null
git remote add origin "$test_root/origin.git"
git push -u origin main >/dev/null

sh "$preflight" >/dev/null

printf '%s\n' 'dirty' >> README.md
if sh "$preflight" >/dev/null 2>&1; then
    fail "preflight accepted a dirty worktree"
fi
git restore -- README.md

git switch --detach >/dev/null 2>&1
if sh "$preflight" >/dev/null 2>&1; then
    fail "preflight accepted a detached HEAD"
fi
git switch main >/dev/null 2>&1

git config branch.main.merge refs/heads/not-main
if sh "$preflight" >/dev/null 2>&1; then
    fail "preflight accepted a mismatched upstream"
fi
git config branch.main.merge refs/heads/main

git clone --branch main "$test_root/origin.git" "$test_root/ahead" >/dev/null 2>&1
(
    cd "$test_root/ahead"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    git commit --allow-empty -m "local ahead" >/dev/null
    if sh "$preflight" >/dev/null 2>&1; then
        fail "preflight accepted a local HEAD that differs from origin"
    fi
    [ "$(node -p 'require("./package.json").version')" = "1.0.0" ] || fail "failed preflight modified the version"
)

git clone --branch main "$test_root/origin.git" "$test_root/hook" >/dev/null 2>&1
(
    cd "$test_root/hook"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    printf '%s\n' '#!/bin/sh' 'printf "%s\\n" hook-dirty >> README.md' 'git add -- README.md' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    node -e '
    const fs=require("fs");
    const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
    pkg.version="1.1.0";
    fs.writeFileSync("package.json",JSON.stringify(pkg)+"\n");
    const xml=fs.readFileSync("plugin.xml","utf8").replace("version=\"1.0.0\"","version=\"1.1.0\"");
    fs.writeFileSync("plugin.xml",xml);
    '
    hook_base=$(git rev-parse HEAD)
    if sh "$publish" 1.1.0 >/dev/null 2>&1; then
        fail "publish accepted a path added by a pre-commit hook"
    fi
    [ "$(git rev-parse HEAD)" != "$hook_base" ] || fail "hook rejection did not leave the release commit locally"
    if git show-ref --verify --quiet refs/tags/1.1.0; then
        fail "hook rejection created a release tag"
    fi
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$hook_base" ] || fail "hook rejection changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.1.0)" ] || fail "hook rejection pushed a release tag"
)

git tag -a unrelated -m unrelated

node -e '
const fs=require("fs");
const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
pkg.version="1.1.0";
fs.writeFileSync("package.json",JSON.stringify(pkg)+"\n");
const xml=fs.readFileSync("plugin.xml","utf8").replace("version=\"1.0.0\"","version=\"1.1.0\"");
fs.writeFileSync("plugin.xml",xml);
'

sh "$publish" 1.1.0 >/dev/null
release_commit=$(git rev-parse HEAD)
[ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$release_commit" ] || fail "remote branch SHA mismatch"
[ "$(git ls-remote origin 'refs/tags/1.1.0^{}' | awk 'NR==1 {print $1}')" = "$release_commit" ] || fail "remote tag peeled SHA mismatch"
[ -z "$(git ls-remote origin refs/tags/unrelated)" ] || fail "unrelated annotated tag was pushed"

node -e '
const fs=require("fs");
const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
pkg.version="1.1.1";
fs.writeFileSync("package.json",JSON.stringify(pkg)+"\n");
const xml=fs.readFileSync("plugin.xml","utf8").replace("version=\"1.1.0\"","version=\"1.1.1\"");
fs.writeFileSync("plugin.xml",xml);
fs.appendFileSync("README.md","dirty\n");
'
before_failed_release=$(git rev-parse HEAD)
if sh "$publish" 1.1.1 >/dev/null 2>&1; then
    fail "publish accepted an unrelated dirty file"
fi
[ "$(git rev-parse HEAD)" = "$before_failed_release" ] || fail "failed publish created a commit"
if git show-ref --verify --quiet refs/tags/1.1.1; then
    fail "failed publish created a tag"
fi
[ -z "$(git ls-remote origin refs/tags/1.1.1)" ] || fail "failed publish pushed a tag"

printf '%s\n' "release skill tests passed"

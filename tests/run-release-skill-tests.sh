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

set_fixture_version() {
    node -e '
    const fs=require("fs");
    const version=process.argv[1];
    const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
    const previous=pkg.version;
    pkg.version=version;
    fs.writeFileSync("package.json",JSON.stringify(pkg)+"\n");
    const xml=fs.readFileSync("plugin.xml","utf8").replace("version=\""+previous+"\"","version=\""+version+"\"");
    fs.writeFileSync("plugin.xml",xml);
    ' -- "$1"
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
    set_fixture_version 1.1.0
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

git clone --branch main "$test_root/origin.git" "$test_root/local-tag" >/dev/null 2>&1
(
    cd "$test_root/local-tag"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    local_tag_base=$(git rev-parse HEAD)
    git tag -a 1.2.0 -m "existing local tag"
    set_fixture_version 1.2.0
    if sh "$publish" 1.2.0 >/dev/null 2>&1; then
        fail "publish accepted an existing local tag"
    fi
    [ "$(git rev-parse HEAD)" = "$local_tag_base" ] || fail "local tag collision created a commit"
    [ "$(git rev-parse 'refs/tags/1.2.0^{}')" = "$local_tag_base" ] || fail "local tag collision moved the tag"
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$local_tag_base" ] || fail "local tag collision changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.2.0)" ] || fail "local tag collision pushed the tag"
)

git tag -a 1.3.0 -m "existing remote tag"
git push origin refs/tags/1.3.0:refs/tags/1.3.0 >/dev/null
git clone --branch main "$test_root/origin.git" "$test_root/remote-tag" >/dev/null 2>&1
(
    cd "$test_root/remote-tag"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    remote_tag_base=$(git rev-parse HEAD)
    remote_tag_before=$(git ls-remote origin 'refs/tags/1.3.0^{}' | awk 'NR==1 {print $1}')
    set_fixture_version 1.3.0
    if sh "$publish" 1.3.0 >/dev/null 2>&1; then
        fail "publish accepted an existing remote tag"
    fi
    [ "$(git rev-parse HEAD)" = "$remote_tag_base" ] || fail "remote tag collision created a commit"
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$remote_tag_base" ] || fail "remote tag collision changed the remote branch"
    [ "$(git ls-remote origin 'refs/tags/1.3.0^{}' | awk 'NR==1 {print $1}')" = "$remote_tag_before" ] || fail "remote tag collision moved the tag"
)

mkdir "$test_root/fail-bin"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_root/fail-bin/npm"
chmod +x "$test_root/fail-bin/npm"
git clone --branch main "$test_root/origin.git" "$test_root/npm-fail" >/dev/null 2>&1
(
    cd "$test_root/npm-fail"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    npm_fail_base=$(git rev-parse HEAD)
    set_fixture_version 1.4.0
    if PATH="$test_root/fail-bin:$PATH" sh "$publish" 1.4.0 >/dev/null 2>&1; then
        fail "publish continued after npm test failed"
    fi
    [ "$(git rev-parse HEAD)" = "$npm_fail_base" ] || fail "npm failure created a commit"
    if git show-ref --verify --quiet refs/tags/1.4.0; then
        fail "npm failure created a tag"
    fi
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$npm_fail_base" ] || fail "npm failure changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.4.0)" ] || fail "npm failure pushed a tag"
)

printf '%s\n' '#!/bin/sh' 'while read old new ref; do' '    [ "$ref" = "refs/tags/2.0.0" ] && exit 1' 'done' 'exit 0' > "$test_root/origin.git/hooks/pre-receive"
chmod +x "$test_root/origin.git/hooks/pre-receive"
git clone --branch main "$test_root/origin.git" "$test_root/push-fail" >/dev/null 2>&1
(
    cd "$test_root/push-fail"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    push_fail_base=$(git rev-parse HEAD)
    set_fixture_version 2.0.0
    if sh "$publish" 2.0.0 >/dev/null 2>&1; then
        fail "publish succeeded after the atomic push was rejected"
    fi
    push_fail_commit=$(git rev-parse HEAD)
    [ "$push_fail_commit" != "$push_fail_base" ] || fail "push failure did not leave the release commit locally"
    [ "$(git cat-file -t refs/tags/2.0.0)" = "tag" ] || fail "push failure did not leave an annotated tag"
    [ "$(git rev-parse 'refs/tags/2.0.0^{}')" = "$push_fail_commit" ] || fail "push failure tag does not point to the release commit"
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$push_fail_base" ] || fail "rejected atomic push changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/2.0.0)" ] || fail "rejected atomic push changed the remote tag"
)

git tag -a unrelated -m unrelated

set_fixture_version 1.1.0

sh "$publish" 1.1.0 >/dev/null
release_commit=$(git rev-parse HEAD)
[ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$release_commit" ] || fail "remote branch SHA mismatch"
[ "$(git ls-remote origin 'refs/tags/1.1.0^{}' | awk 'NR==1 {print $1}')" = "$release_commit" ] || fail "remote tag peeled SHA mismatch"
[ -z "$(git ls-remote origin refs/tags/unrelated)" ] || fail "unrelated annotated tag was pushed"

set_fixture_version 1.1.2
printf '%s\n' dirty >> README.md
before_failed_release=$(git rev-parse HEAD)
if sh "$publish" 1.1.2 >/dev/null 2>&1; then
    fail "publish accepted an unrelated dirty file"
fi
[ "$(git rev-parse HEAD)" = "$before_failed_release" ] || fail "failed publish created a commit"
if git show-ref --verify --quiet refs/tags/1.1.2; then
    fail "failed publish created a tag"
fi
[ -z "$(git ls-remote origin refs/tags/1.1.2)" ] || fail "failed publish pushed a tag"

printf '%s\n' "release skill tests passed"

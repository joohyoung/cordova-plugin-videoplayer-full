#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
preflight="$repo_root/.claude/skills/release/scripts/preflight.sh"
publish="$repo_root/.claude/skills/release/scripts/publish.sh"
verify_version_change="$repo_root/.claude/skills/release/scripts/verify-version-change.js"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

set_fixture_version() {
    preflight_output=$(sh "$preflight")
    publish_branch=$(printf '%s\n' "$preflight_output" | sed -n 's/^release branch: //p')
    publish_base=$(printf '%s\n' "$preflight_output" | sed -n 's/^release base: //p')
    publish_origin_fingerprint=$(printf '%s\n' "$preflight_output" | sed -n 's/^release origin fingerprint: //p')
    [ -n "$publish_branch" ] || fail "preflight branch output missing"
    [ -n "$publish_base" ] || fail "preflight base output missing"
    [ -n "$publish_origin_fingerprint" ] || fail "preflight origin fingerprint output missing"
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

run_publish() {
    publish_version=$1
    sh "$publish" "$publish_version" "$publish_branch" "$publish_base" "$publish_origin_fingerprint"
}

[ "$(readlink "$repo_root/.agents/skills/release")" = "../../.claude/skills/release" ] || fail "release skill symlink target mismatch"
grep -q '^name: release$' "$repo_root/.claude/skills/release/SKILL.md" || fail "release skill frontmatter missing"
[ -f "$verify_version_change" ] || fail "version-only verifier missing"
grep -q 'push --atomic --no-follow-tags' "$publish" || fail "atomic push missing"
if grep -E '^[[:space:]]*(if[[:space:]]+![[:space:]]+)?git .* push' "$publish" | grep -Eq -- '--follow-tags|--tags|--force'; then
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

invalid_tag_base=$(git rev-parse HEAD)
set +e
invalid_tag_output=$(sh "$publish" dev/1.1.0 2>&1)
invalid_tag_status=$?
set -e
[ "$invalid_tag_status" -ne 0 ] || fail "publish accepted a dev-prefixed release tag"
printf '%s\n' "$invalid_tag_output" | grep -q '접두사 없는 안정 SemVer' || fail "prefixed tag rejection did not explain the tag rule"
[ "$(git rev-parse HEAD)" = "$invalid_tag_base" ] || fail "prefixed tag rejection created a commit"
if git show-ref --verify --quiet refs/tags/dev/1.1.0; then
    fail "prefixed tag rejection created a local tag"
fi
[ -z "$(git ls-remote origin refs/tags/dev/1.1.0)" ] || fail "prefixed tag rejection pushed a tag"

multiline_version=$(printf '1.1.0\ndev/1.1.0')
set +e
multiline_output=$(sh "$publish" "$multiline_version" 2>&1)
multiline_status=$?
set -e
[ "$multiline_status" -ne 0 ] || fail "publish accepted a multiline release version"
printf '%s\n' "$multiline_output" | grep -q '접두사 없는 안정 SemVer' || fail "multiline version was not rejected by the version validator"

control_version=$(printf '1.1.0\ncredential-marker\033[31m')
set +e
control_output=$(sh "$publish" "$control_version" 2>&1)
control_status=$?
set -e
[ "$control_status" -ne 0 ] || fail "publish accepted a control-character release version"
case "$control_output" in
    *credential-marker*) fail "invalid version error exposed the rejected input" ;;
esac

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

weird_remote="$test_root/origin;credential-marker.git"
git clone --bare "$test_root/origin.git" "$weird_remote" >/dev/null 2>&1
git clone --branch main "$weird_remote" "$test_root/weird-origin" >/dev/null 2>&1
(
    cd "$test_root/weird-origin"
    weird_preflight_output=$(sh "$preflight")
    case "$weird_preflight_output" in
        *credential-marker*) fail "preflight exposed the raw origin URL" ;;
    esac
    printf '%s\n' "$weird_preflight_output" | grep -Eq '^release origin fingerprint: [0-9a-f]{64}$' || fail "preflight origin fingerprint missing"
)

git clone --branch main "$test_root/origin.git" "$test_root/failing-origin" >/dev/null 2>&1
(
    cd "$test_root/failing-origin"
    git remote set-url origin "$test_root/missing;credential-marker.git"
    set +e
    failing_preflight_output=$(sh "$preflight" 2>&1)
    failing_preflight_status=$?
    set -e
    [ "$failing_preflight_status" -ne 0 ] || fail "preflight accepted an unreachable origin"
    case "$failing_preflight_output" in
        *credential-marker*) fail "failed preflight exposed the raw origin URL" ;;
    esac
)

git init --bare "$test_root/second-origin.git" >/dev/null
git clone --branch main "$test_root/origin.git" "$test_root/multi-push" >/dev/null 2>&1
(
    cd "$test_root/multi-push"
    first_origin=$(git remote get-url origin)
    git remote set-url --add --push origin "$first_origin"
    git remote set-url --add --push origin "$test_root/second-origin.git"
    if sh "$preflight" >/dev/null 2>&1; then
        fail "preflight accepted multiple origin push URLs"
    fi
)

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
    if run_publish 1.1.0 >/dev/null 2>&1; then
        fail "publish accepted a path added by a pre-commit hook"
    fi
    [ "$(git rev-parse HEAD)" != "$hook_base" ] || fail "hook rejection did not leave the release commit locally"
    if git show-ref --verify --quiet refs/tags/1.1.0; then
        fail "hook rejection created a release tag"
    fi
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$hook_base" ] || fail "hook rejection changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.1.0)" ] || fail "hook rejection pushed a release tag"
)

git clone --branch main "$test_root/origin.git" "$test_root/stale-preflight" >/dev/null 2>&1
(
    cd "$test_root/stale-preflight"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    stale_base=$(git rev-parse HEAD)
    set_fixture_version 1.1.1
    git remote set-url --push origin changed.invalid
    if run_publish 1.1.1 >/dev/null 2>&1; then
        fail "publish accepted origin state that differs from preflight"
    fi
    [ "$(git rev-parse HEAD)" = "$stale_base" ] || fail "stale preflight input created a commit"
    if git show-ref --verify --quiet refs/tags/1.1.1; then
        fail "stale preflight input created a tag"
    fi
)

git clone --branch main "$test_root/origin.git" "$test_root/local-tag" >/dev/null 2>&1
(
    cd "$test_root/local-tag"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    local_tag_base=$(git rev-parse HEAD)
    git tag -a 1.2.0 -m "existing local tag"
    set_fixture_version 1.2.0
    if run_publish 1.2.0 >/dev/null 2>&1; then
        fail "publish accepted an existing local tag"
    fi
    [ "$(git rev-parse HEAD)" = "$local_tag_base" ] || fail "local tag collision created a commit"
    [ "$(git rev-parse 'refs/tags/1.2.0^{}')" = "$local_tag_base" ] || fail "local tag collision moved the tag"
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$local_tag_base" ] || fail "local tag collision changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.2.0)" ] || fail "local tag collision pushed the tag"
)

git clone --branch main "$test_root/origin.git" "$test_root/post-commit" >/dev/null 2>&1
(
    cd "$test_root/post-commit"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    printf '%s\n' '#!/bin/sh' 'git remote set-url --push origin changed.invalid' > .git/hooks/post-commit
    chmod +x .git/hooks/post-commit
    post_commit_base=$(git rev-parse HEAD)
    set_fixture_version 1.2.1
    if run_publish 1.2.1 >/dev/null 2>&1; then
        fail "publish accepted an origin URL changed by a post-commit hook"
    fi
    [ "$(git rev-parse HEAD)" != "$post_commit_base" ] || fail "post-commit rejection did not leave the release commit locally"
    if git show-ref --verify --quiet refs/tags/1.2.1; then
        fail "post-commit rejection created a release tag"
    fi
    [ "$(git ls-remote "$test_root/origin.git" refs/heads/main | awk 'NR==1 {print $1}')" = "$post_commit_base" ] || fail "post-commit rejection changed the original remote branch"
    [ -z "$(git ls-remote "$test_root/origin.git" refs/tags/1.2.1)" ] || fail "post-commit rejection pushed a release tag"
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
    if run_publish 1.3.0 >/dev/null 2>&1; then
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
    if PATH="$test_root/fail-bin:$PATH" run_publish 1.4.0 >/dev/null 2>&1; then
        fail "publish continued after npm test failed"
    fi
    [ "$(git rev-parse HEAD)" = "$npm_fail_base" ] || fail "npm failure created a commit"
    if git show-ref --verify --quiet refs/tags/1.4.0; then
        fail "npm failure created a tag"
    fi
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$npm_fail_base" ] || fail "npm failure changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.4.0)" ] || fail "npm failure pushed a tag"
)

git clone --branch main "$test_root/origin.git" "$test_root/extra-content" >/dev/null 2>&1
(
    cd "$test_root/extra-content"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    extra_content_base=$(git rev-parse HEAD)
    set_fixture_version 1.5.0
    node -e '
    const fs=require("fs");
    const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
    pkg.description="unexpected";
    fs.writeFileSync("package.json",JSON.stringify(pkg)+"\n");
    '
    if run_publish 1.5.0 >/dev/null 2>&1; then
        fail "publish accepted package.json content beyond version"
    fi
    [ "$(git rev-parse HEAD)" = "$extra_content_base" ] || fail "extra package content created a commit"
    if git show-ref --verify --quiet refs/tags/1.5.0; then
        fail "extra package content created a tag"
    fi
)

git clone --branch main "$test_root/origin.git" "$test_root/mode-change" >/dev/null 2>&1
(
    cd "$test_root/mode-change"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    mode_change_base=$(git rev-parse HEAD)
    set_fixture_version 1.5.1
    chmod +x package.json
    if run_publish 1.5.1 >/dev/null 2>&1; then
        fail "publish accepted a version file mode change"
    fi
    [ "$(git rev-parse HEAD)" = "$mode_change_base" ] || fail "file mode change created a commit"
    if git show-ref --verify --quiet refs/tags/1.5.1; then
        fail "file mode change created a tag"
    fi
)

mkdir "$test_root/mutate-bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" npm-mutated >> package.json' 'exit 0' > "$test_root/mutate-bin/npm"
chmod +x "$test_root/mutate-bin/npm"
git clone --branch main "$test_root/origin.git" "$test_root/npm-mutate" >/dev/null 2>&1
(
    cd "$test_root/npm-mutate"
    git config user.name "Release Skill Test"
    git config user.email "release-skill@example.invalid"
    npm_mutate_base=$(git rev-parse HEAD)
    set_fixture_version 1.6.0
    if PATH="$test_root/mutate-bin:$PATH" run_publish 1.6.0 >/dev/null 2>&1; then
        fail "publish accepted a successful npm test that mutated a version file"
    fi
    [ "$(git rev-parse HEAD)" = "$npm_mutate_base" ] || fail "npm mutation created a commit"
    if git show-ref --verify --quiet refs/tags/1.6.0; then
        fail "npm mutation created a tag"
    fi
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$npm_mutate_base" ] || fail "npm mutation changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/1.6.0)" ] || fail "npm mutation pushed a tag"
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
    set +e
    push_failure_output=$(run_publish 2.0.0 2>&1)
    push_failure_status=$?
    set -e
    [ "$push_failure_status" -ne 0 ] || fail "publish succeeded after the atomic push was rejected"
    printf '%s\n' "$push_failure_output" | grep -q 'atomic push에 실패했습니다' || fail "push failure did not report the expected state"
    case "$push_failure_output" in
        *"unbound variable"*) fail "push failure expanded a Korean suffix as part of a variable name" ;;
    esac
    push_fail_commit=$(git rev-parse HEAD)
    [ "$push_fail_commit" != "$push_fail_base" ] || fail "push failure did not leave the release commit locally"
    [ "$(git cat-file -t refs/tags/2.0.0)" = "tag" ] || fail "push failure did not leave an annotated tag"
    [ "$(git rev-parse 'refs/tags/2.0.0^{}')" = "$push_fail_commit" ] || fail "push failure tag does not point to the release commit"
    [ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$push_fail_base" ] || fail "rejected atomic push changed the remote branch"
    [ -z "$(git ls-remote origin refs/tags/2.0.0)" ] || fail "rejected atomic push changed the remote tag"
)

git config push.followTags true
git config remote.origin.mirror true
git tag -a unrelated -m unrelated

set_fixture_version 1.1.0

run_publish 1.1.0 >/dev/null
release_commit=$(git rev-parse HEAD)
release_tag_object=$(git rev-parse refs/tags/1.1.0)
[ "$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')" = "$release_commit" ] || fail "remote branch SHA mismatch"
[ "$(git ls-remote origin refs/tags/1.1.0 | awk 'NR==1 {print $1}')" = "$release_tag_object" ] || fail "remote tag object ID mismatch"
[ "$(git ls-remote origin 'refs/tags/1.1.0^{}' | awk 'NR==1 {print $1}')" = "$release_commit" ] || fail "remote tag peeled SHA mismatch"
[ -z "$(git ls-remote origin refs/tags/unrelated)" ] || fail "unrelated annotated tag was pushed"

set_fixture_version 1.1.2
printf '%s\n' dirty >> README.md
before_failed_release=$(git rev-parse HEAD)
if run_publish 1.1.2 >/dev/null 2>&1; then
    fail "publish accepted an unrelated dirty file"
fi
[ "$(git rev-parse HEAD)" = "$before_failed_release" ] || fail "failed publish created a commit"
if git show-ref --verify --quiet refs/tags/1.1.2; then
    fail "failed publish created a tag"
fi
[ -z "$(git ls-remote origin refs/tags/1.1.2)" ] || fail "failed publish pushed a tag"

printf '%s\n' "release skill tests passed"

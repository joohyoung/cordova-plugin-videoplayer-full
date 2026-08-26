#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

fingerprint() {
    node -e 'const crypto=require("crypto"),fs=require("fs");process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(0)).digest("hex"));'
}

version=${1-}
expected_branch=${2-}
expected_base=${3-}
expected_origin_fingerprint=${4-}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || fail "release script 디렉터리를 확인할 수 없습니다."
verify_version_change=$script_dir/verify-version-change.js
printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || fail "새 버전은 안정 SemVer M.m.p 형식이어야 합니다: $version"
printf '%s\n' "$expected_branch" | grep -Eq '^[A-Za-z0-9._/][A-Za-z0-9._/-]*$' || fail "preflight 브랜치가 안전한 형식이 아닙니다: $expected_branch"
printf '%s\n' "$expected_base" | grep -Eq '^[0-9a-f]{40,64}$' || fail "preflight base가 Git object ID 형식이 아닙니다: $expected_base"
printf '%s\n' "$expected_origin_fingerprint" | grep -Eq '^[0-9a-f]{64}$' || fail "preflight origin fingerprint 형식이 올바르지 않습니다."

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "Git 저장소 루트를 확인할 수 없습니다."
resolved_root=$(cd "$repo_root" && pwd -P) || fail "Git 저장소 루트 경로를 확인할 수 없습니다."
[ "$(pwd -P)" = "$resolved_root" ] || fail "publish는 저장소 루트에서 실행해야 합니다."

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || fail "현재 HEAD가 symbolic branch가 아닙니다."
case "$branch" in
    ""|-*|*[!A-Za-z0-9._/-]*) fail "안전하게 사용할 수 없는 브랜치 이름입니다: $branch" ;;
esac
[ "$branch" = "$expected_branch" ] || fail "현재 브랜치가 preflight 결과와 다릅니다: $branch"
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || fail "현재 브랜치에 upstream이 없습니다."
[ "$upstream" = "origin/$branch" ] || fail "upstream이 origin의 같은 이름 브랜치가 아닙니다: $upstream"

origin_fetch_urls=$(git remote get-url --all origin 2>/dev/null) || fail "origin fetch URL을 읽지 못했습니다."
origin_push_urls=$(git remote get-url --push --all origin 2>/dev/null) || fail "origin push URL을 읽지 못했습니다."
[ "$(printf '%s\n' "$origin_fetch_urls" | wc -l | tr -d ' ')" -eq 1 ] || fail "origin fetch URL은 정확히 하나여야 합니다."
[ "$(printf '%s\n' "$origin_push_urls" | wc -l | tr -d ' ')" -eq 1 ] || fail "origin push URL은 정확히 하나여야 합니다."
[ "$origin_fetch_urls" = "$origin_push_urls" ] || fail "origin fetch URL과 push URL이 다릅니다."
origin_fingerprint=$(printf '%s' "$origin_fetch_urls" | fingerprint) || fail "origin URL fingerprint 계산에 실패했습니다."
[ "$origin_fingerprint" = "$expected_origin_fingerprint" ] || fail "origin URL fingerprint가 preflight 결과와 다릅니다."

git fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null 2>&1 || fail "origin/$branch fetch에 실패했습니다. 원격 URL은 노출하지 않고 버전 파일이 수정된 상태로 남습니다."
local_head=$(git rev-parse HEAD) || fail "로컬 HEAD를 읽지 못했습니다. 버전 파일은 수정된 상태로 남습니다."
remote_head=$(git rev-parse "refs/remotes/origin/$branch") || fail "origin/$branch SHA를 읽지 못했습니다. 버전 파일은 수정된 상태로 남습니다."
[ "$local_head" = "$expected_base" ] || fail "version-up 이후 로컬 HEAD가 preflight base에서 이동했습니다. 버전 파일은 수정된 상태로 남습니다."
[ "$remote_head" = "$expected_base" ] || fail "version-up 이후 원격 브랜치가 preflight base에서 이동했습니다. 버전 파일은 수정된 상태로 남습니다."

git diff --cached --quiet -- || fail "version-up 전에 없던 staged change가 있습니다. commit하지 않고 중단합니다."
changed_files=$(git diff --name-only --)
expected_files=$(printf 'package.json\nplugin.xml')
[ "$changed_files" = "$expected_files" ] || fail "package.json과 plugin.xml 이외의 tracked change가 있거나 필수 변경이 빠졌습니다. commit하지 않고 중단합니다."
[ -z "$(git ls-files --others --exclude-standard)" ] || fail "untracked file이 있습니다. commit하지 않고 중단합니다."
node "$verify_version_change" "$expected_base" "$version" || fail "version 이외의 파일 변경이 있습니다. commit하지 않고 중단합니다."

if git show-ref --verify --quiet "refs/tags/$version"; then
    fail "로컬 태그 $version이 이미 있습니다. 이동하거나 삭제하지 않고 중단합니다."
else
    tag_status=$?
    [ "$tag_status" -eq 1 ] || fail "로컬 태그 $version 확인에 실패했습니다."
fi

set +e
remote_tag=$(git ls-remote --exit-code --tags origin "refs/tags/$version" 2>&1)
remote_tag_status=$?
set -e
case "$remote_tag_status" in
    0) fail "원격 태그 $version이 이미 있습니다. 이동하거나 삭제하지 않고 중단합니다." ;;
    2) ;;
    *) fail "원격 태그 $version 확인에 실패했습니다. 원격 오류 원문은 URL 보호를 위해 출력하지 않습니다." ;;
esac

npm test || fail "npm test가 실패했습니다. 버전 파일은 수정된 상태로 남습니다."

branch_after_test=$(git symbolic-ref --short HEAD 2>/dev/null) || fail "npm test 이후 HEAD가 symbolic branch가 아닙니다. commit하지 않고 중단합니다."
[ "$branch_after_test" = "$expected_branch" ] || fail "npm test 이후 브랜치가 preflight 결과와 달라졌습니다. commit하지 않고 중단합니다."
head_after_test=$(git rev-parse HEAD) || fail "npm test 이후 HEAD를 읽지 못했습니다. commit하지 않고 중단합니다."
[ "$head_after_test" = "$expected_base" ] || fail "npm test 이후 HEAD가 preflight base에서 이동했습니다. commit하지 않고 중단합니다."
upstream_after_test=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || fail "npm test 이후 upstream을 읽지 못했습니다. commit하지 않고 중단합니다."
[ "$upstream_after_test" = "origin/$expected_branch" ] || fail "npm test 이후 upstream이 달라졌습니다. commit하지 않고 중단합니다."
fetch_urls_after_test=$(git remote get-url --all origin 2>/dev/null) || fail "npm test 이후 origin fetch URL을 읽지 못했습니다. commit하지 않고 중단합니다."
push_urls_after_test=$(git remote get-url --push --all origin 2>/dev/null) || fail "npm test 이후 origin push URL을 읽지 못했습니다. commit하지 않고 중단합니다."
[ "$fetch_urls_after_test" = "$push_urls_after_test" ] || fail "npm test 이후 origin fetch URL과 push URL이 달라졌습니다. commit하지 않고 중단합니다."
fingerprint_after_test=$(printf '%s' "$fetch_urls_after_test" | fingerprint) || fail "npm test 이후 origin URL fingerprint 계산에 실패했습니다. commit하지 않고 중단합니다."
[ "$fingerprint_after_test" = "$expected_origin_fingerprint" ] || fail "npm test 이후 origin URL fingerprint가 달라졌습니다. commit하지 않고 중단합니다."
git diff --cached --quiet -- || fail "npm test 이후 staged change가 있습니다. commit하지 않고 중단합니다."
changed_files_after_test=$(git diff --name-only --)
[ "$changed_files_after_test" = "$expected_files" ] || fail "npm test 이후 버전 파일 이외의 tracked change가 있거나 필수 변경이 빠졌습니다. commit하지 않고 중단합니다."
[ -z "$(git ls-files --others --exclude-standard)" ] || fail "npm test 이후 untracked file이 있습니다. commit하지 않고 중단합니다."
node "$verify_version_change" "$expected_base" "$version" || fail "npm test 이후 version 이외의 파일 변경이 있습니다. commit하지 않고 중단합니다."

if git show-ref --verify --quiet "refs/tags/$version"; then
    fail "npm test 중 로컬 태그 $version이 생겼습니다. 이동하거나 삭제하지 않고 중단합니다."
fi
set +e
remote_tag_after_test=$(git ls-remote --exit-code --tags origin "refs/tags/$version" 2>&1)
remote_tag_after_test_status=$?
set -e
case "$remote_tag_after_test_status" in
    0) fail "npm test 중 원격 태그 $version이 생겼습니다. 이동하거나 삭제하지 않고 중단합니다." ;;
    2) ;;
    *) fail "npm test 이후 원격 태그 $version 확인에 실패했습니다. 원격 오류 원문은 URL 보호를 위해 출력하지 않습니다." ;;
esac

git add -- package.json plugin.xml || fail "버전 파일 stage에 실패했습니다. 현재 인덱스 상태를 유지하고 중단합니다."
staged_files=$(git diff --cached --name-only --)
[ "$staged_files" = "$expected_files" ] || fail "인덱스에 package.json과 plugin.xml 이외의 경로가 있습니다. commit하지 않고 중단합니다."
[ -z "$(git diff --name-only --)" ] || fail "stage 후 unstaged tracked change가 남았습니다. commit하지 않고 중단합니다."
[ -z "$(git ls-files --others --exclude-standard)" ] || fail "stage 후 untracked file이 남았습니다. commit하지 않고 중단합니다."

git commit -m "Cordova 플러그인 버전 $version" -- package.json plugin.xml || fail "버전 commit에 실패했습니다. staged change를 자동으로 되돌리지 않습니다."
release_commit=$(git rev-parse HEAD) || fail "release commit SHA를 읽지 못했습니다. commit은 로컬에 남습니다."

release_parent=$(git rev-parse "$release_commit^") || fail "release commit 부모 SHA를 읽지 못했습니다. commit은 로컬에 남습니다."
[ "$release_parent" = "$remote_head" ] || fail "release commit의 부모가 검증한 원격 HEAD와 다릅니다. commit $release_commit은 로컬에 남습니다."
commit_files=$(git diff-tree --no-commit-id --name-only -r "$release_commit" | LC_ALL=C sort) || fail "release commit 경로를 읽지 못했습니다. commit은 로컬에 남습니다."
[ "$commit_files" = "$expected_files" ] || fail "release commit에 package.json과 plugin.xml 이외의 경로가 포함됐습니다. commit $release_commit은 로컬에 남습니다."
[ -z "$(git status --porcelain --untracked-files=all)" ] || fail "release commit 뒤 작업 트리 또는 인덱스가 깨끗하지 않습니다. commit $release_commit은 로컬에 남습니다."
node "$verify_version_change" "$expected_base" "$version" "$release_commit" || fail "release commit에 version 이외의 변경이 있습니다. commit $release_commit은 로컬에 남습니다."
branch_after_commit=$(git symbolic-ref --short HEAD 2>/dev/null) || fail "release commit 뒤 HEAD가 symbolic branch가 아닙니다. commit은 로컬에 남습니다."
[ "$branch_after_commit" = "$expected_branch" ] || fail "release commit 뒤 브랜치가 preflight 결과와 다릅니다. commit은 로컬에 남습니다."
upstream_after_commit=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || fail "release commit 뒤 upstream을 읽지 못했습니다. commit은 로컬에 남습니다."
[ "$upstream_after_commit" = "origin/$expected_branch" ] || fail "release commit 뒤 upstream이 달라졌습니다. commit은 로컬에 남습니다."
fetch_urls_after_commit=$(git remote get-url --all origin 2>/dev/null) || fail "release commit 뒤 origin fetch URL을 읽지 못했습니다. commit은 로컬에 남습니다."
push_urls_after_commit=$(git remote get-url --push --all origin 2>/dev/null) || fail "release commit 뒤 origin push URL을 읽지 못했습니다. commit은 로컬에 남습니다."
[ "$fetch_urls_after_commit" = "$push_urls_after_commit" ] || fail "release commit 뒤 origin fetch URL과 push URL이 달라졌습니다. commit은 로컬에 남습니다."
fingerprint_after_commit=$(printf '%s' "$fetch_urls_after_commit" | fingerprint) || fail "release commit 뒤 origin URL fingerprint 계산에 실패했습니다. commit은 로컬에 남습니다."
[ "$fingerprint_after_commit" = "$expected_origin_fingerprint" ] || fail "release commit 뒤 origin URL fingerprint가 달라졌습니다. commit은 로컬에 남습니다."

git tag -a "$version" -m "Cordova plugin $version" "$release_commit" || fail "annotated 태그 생성에 실패했습니다. release commit $release_commit은 로컬에 남습니다."
[ "$(git cat-file -t "refs/tags/$version")" = "tag" ] || fail "생성된 $version 태그가 annotated tag가 아닙니다. commit과 tag를 자동으로 되돌리지 않습니다."
[ "$(git rev-parse "refs/tags/$version^{}")" = "$release_commit" ] || fail "생성된 $version 태그가 release commit을 가리키지 않습니다. commit과 tag를 자동으로 되돌리지 않습니다."
release_tag_object=$(git rev-parse "refs/tags/$version") || fail "생성된 $version 태그 object ID를 읽지 못했습니다. commit과 tag를 자동으로 되돌리지 않습니다."
[ "$(git rev-parse "refs/heads/$branch")" = "$release_commit" ] || fail "현재 브랜치 ref가 release commit에서 이동했습니다. commit과 tag를 자동으로 되돌리지 않습니다."

remote_branch_before_push=$(git ls-remote --exit-code origin "refs/heads/$branch" 2>/dev/null) || fail "push 직전 원격 브랜치 SHA 조회에 실패했습니다. 원격 URL은 노출하지 않고 commit과 tag를 로컬에 남깁니다."
remote_branch_before_push_sha=$(printf '%s\n' "$remote_branch_before_push" | awk 'NR==1 {print $1}')
[ "$remote_branch_before_push_sha" = "$expected_base" ] || fail "push 직전 원격 브랜치가 preflight base에서 이동했습니다. commit과 tag는 로컬에 남습니다."
set +e
remote_tag_before_push=$(git ls-remote --exit-code --tags origin "refs/tags/$version" 2>&1)
remote_tag_before_push_status=$?
set -e
case "$remote_tag_before_push_status" in
    0) fail "push 직전 원격 태그 $version이 생겼습니다. commit과 tag는 로컬에 남습니다." ;;
    2) ;;
    *) fail "push 직전 원격 태그 $version 확인에 실패했습니다. 원격 오류 원문은 URL 보호를 위해 출력하지 않습니다." ;;
esac

if ! git -c push.followTags=false -c remote.origin.mirror=false push --atomic --no-follow-tags --recurse-submodules=no origin \
    "$release_commit:refs/heads/$branch" \
    "$release_tag_object:refs/tags/$version" >/dev/null 2>&1; then
    fail "atomic push에 실패했습니다. 원격 오류 원문과 URL은 출력하지 않고 비원자적 방식으로 재시도하지 않습니다. 로컬 commit $release_commit과 태그 $version은 남습니다."
fi

remote_branch_output=$(git ls-remote --exit-code origin "refs/heads/$branch" 2>/dev/null) || fail "push 후 원격 브랜치 SHA 조회에 실패했습니다. 원격 URL은 출력하지 않습니다."
remote_branch_sha=$(printf '%s\n' "$remote_branch_output" | awk 'NR==1 {print $1}')
[ "$remote_branch_sha" = "$release_commit" ] || fail "원격 브랜치 SHA가 release commit과 다릅니다: $remote_branch_sha"

remote_tag_output=$(git ls-remote --exit-code --tags origin "refs/tags/$version^{}" 2>/dev/null) || fail "push 후 원격 태그 peeled SHA 조회에 실패했습니다. 원격 URL은 출력하지 않습니다."
remote_tag_sha=$(printf '%s\n' "$remote_tag_output" | awk 'NR==1 {print $1}')
[ "$remote_tag_sha" = "$release_commit" ] || fail "원격 태그 peeled SHA가 release commit과 다릅니다: $remote_tag_sha"
remote_tag_object_output=$(git ls-remote --exit-code --tags origin "refs/tags/$version" 2>/dev/null) || fail "push 후 원격 태그 object ID 조회에 실패했습니다. 원격 URL은 출력하지 않습니다."
remote_tag_object=$(printf '%s\n' "$remote_tag_object_output" | awk 'NR==1 {print $1}')
[ "$remote_tag_object" = "$release_tag_object" ] || fail "원격 태그 object ID가 로컬 annotated tag와 다릅니다: $remote_tag_object"

printf 'release commit: %s\n' "$release_commit"
printf 'release branch: %s\n' "$branch"
printf 'release tag: %s\n' "$version"
printf 'remote branch SHA: %s\n' "$remote_branch_sha"
printf 'remote tag object ID: %s\n' "$remote_tag_object"
printf 'remote tag peeled SHA: %s\n' "$remote_tag_sha"

#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

version=${1-}
printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || fail "새 버전은 안정 SemVer M.m.p 형식이어야 합니다: $version"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "Git 저장소 루트를 확인할 수 없습니다."
resolved_root=$(cd "$repo_root" && pwd -P) || fail "Git 저장소 루트 경로를 확인할 수 없습니다."
[ "$(pwd -P)" = "$resolved_root" ] || fail "publish는 저장소 루트에서 실행해야 합니다."

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || fail "현재 HEAD가 symbolic branch가 아닙니다."
case "$branch" in
    ""|-*|*[!A-Za-z0-9._/-]*) fail "안전하게 사용할 수 없는 브랜치 이름입니다: $branch" ;;
esac
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || fail "현재 브랜치에 upstream이 없습니다."
[ "$upstream" = "origin/$branch" ] || fail "upstream이 origin의 같은 이름 브랜치가 아닙니다: $upstream"

git fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" || fail "origin/$branch fetch에 실패했습니다. 버전 파일은 수정된 상태로 남습니다."
local_head=$(git rev-parse HEAD) || fail "로컬 HEAD를 읽지 못했습니다. 버전 파일은 수정된 상태로 남습니다."
remote_head=$(git rev-parse "refs/remotes/origin/$branch") || fail "origin/$branch SHA를 읽지 못했습니다. 버전 파일은 수정된 상태로 남습니다."
[ "$local_head" = "$remote_head" ] || fail "version-up 이후 원격 브랜치가 바뀌었거나 로컬 HEAD가 이동했습니다. 버전 파일은 수정된 상태로 남습니다."

git diff --cached --quiet -- || fail "version-up 전에 없던 staged change가 있습니다. commit하지 않고 중단합니다."
changed_files=$(git diff --name-only --)
expected_files=$(printf 'package.json\nplugin.xml')
[ "$changed_files" = "$expected_files" ] || fail "package.json과 plugin.xml 이외의 tracked change가 있거나 필수 변경이 빠졌습니다. commit하지 않고 중단합니다."
[ -z "$(git ls-files --others --exclude-standard)" ] || fail "untracked file이 있습니다. commit하지 않고 중단합니다."

node -e '
const fs=require("fs");
function fail(message){console.error(message);process.exit(1);}
const expected=process.argv[1];
let packageJson;
try{packageJson=JSON.parse(fs.readFileSync("package.json","utf8"));}catch(error){fail("package.json 읽기/파싱 실패: "+error.message);}
let pluginXml;
try{pluginXml=fs.readFileSync("plugin.xml","utf8");}catch(error){fail("plugin.xml 읽기 실패: "+error.message);}
const tag=pluginXml.replace(/<!--[\s\S]*?-->/g,"").match(/<plugin(?=[\s>\/])[^>]*>/);
if(!tag)fail("plugin.xml에서 루트 <plugin> 여는 태그를 찾지 못했습니다");
const attributes=/\s([A-Za-z_:][-\w:.]*)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)/g;
let match,pluginVersion;
while((match=attributes.exec(tag[0]))!==null){if(match[1]==="version"){pluginVersion=match[2]!==undefined?match[2]:match[3];break;}}
if(packageJson.version!==expected||pluginVersion!==expected)fail("두 버전 원본이 새 버전 "+expected+"과 일치하지 않습니다");
' -- "$version" || fail "버전 원본 재검증에 실패했습니다. commit하지 않고 중단합니다."

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
    *) printf '%s\n' "$remote_tag" >&2; fail "원격 태그 $version 확인에 실패했습니다." ;;
esac

npm test || fail "npm test가 실패했습니다. 버전 파일은 수정된 상태로 남습니다."

git add -- package.json plugin.xml || fail "버전 파일 stage에 실패했습니다. 현재 인덱스 상태를 유지하고 중단합니다."
staged_files=$(git diff --cached --name-only --)
[ "$staged_files" = "$expected_files" ] || fail "인덱스에 package.json과 plugin.xml 이외의 경로가 있습니다. commit하지 않고 중단합니다."
[ -z "$(git diff --name-only --)" ] || fail "stage 후 unstaged tracked change가 남았습니다. commit하지 않고 중단합니다."
[ -z "$(git ls-files --others --exclude-standard)" ] || fail "stage 후 untracked file이 남았습니다. commit하지 않고 중단합니다."

git commit -m "Cordova 플러그인 버전 $version" -- package.json plugin.xml || fail "버전 commit에 실패했습니다. staged change를 자동으로 되돌리지 않습니다."
release_commit=$(git rev-parse HEAD) || fail "release commit SHA를 읽지 못했습니다. commit은 로컬에 남습니다."

git tag -a "$version" -m "Cordova plugin $version" || fail "annotated 태그 생성에 실패했습니다. release commit $release_commit은 로컬에 남습니다."
[ "$(git cat-file -t "refs/tags/$version")" = "tag" ] || fail "생성된 $version 태그가 annotated tag가 아닙니다. commit과 tag를 자동으로 되돌리지 않습니다."

if ! git push --atomic origin \
    "refs/heads/$branch:refs/heads/$branch" \
    "refs/tags/$version:refs/tags/$version"; then
    fail "atomic push에 실패했습니다. 비원자적 방식으로 재시도하지 않습니다. 로컬 commit $release_commit과 태그 $version은 남습니다."
fi

remote_branch_output=$(git ls-remote --exit-code origin "refs/heads/$branch") || fail "push 후 원격 브랜치 SHA 조회에 실패했습니다."
remote_branch_sha=$(printf '%s\n' "$remote_branch_output" | awk 'NR==1 {print $1}')
[ "$remote_branch_sha" = "$release_commit" ] || fail "원격 브랜치 SHA가 release commit과 다릅니다: $remote_branch_sha"

remote_tag_output=$(git ls-remote --exit-code --tags origin "refs/tags/$version^{}") || fail "push 후 원격 태그 peeled SHA 조회에 실패했습니다."
remote_tag_sha=$(printf '%s\n' "$remote_tag_output" | awk 'NR==1 {print $1}')
[ "$remote_tag_sha" = "$release_commit" ] || fail "원격 태그 peeled SHA가 release commit과 다릅니다: $remote_tag_sha"

printf 'release commit: %s\n' "$release_commit"
printf 'release branch: %s\n' "$branch"
printf 'release tag: %s\n' "$version"
printf 'remote branch SHA: %s\n' "$remote_branch_sha"
printf 'remote tag peeled SHA: %s\n' "$remote_tag_sha"

#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "Git 저장소 루트를 확인할 수 없습니다. 파일을 수정하지 않고 중단합니다."
resolved_root=$(cd "$repo_root" && pwd -P) || fail "Git 저장소 루트 경로를 확인할 수 없습니다. 파일을 수정하지 않고 중단합니다."
[ "$(pwd -P)" = "$resolved_root" ] || fail "release는 저장소 루트에서 실행해야 합니다. 파일을 수정하지 않고 중단합니다."

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || fail "현재 HEAD가 symbolic branch가 아닙니다. 파일을 수정하지 않고 중단합니다."
case "$branch" in
    ""|-*|*[!A-Za-z0-9._/-]*) fail "안전하게 사용할 수 없는 브랜치 이름입니다: $branch" ;;
esac

[ -z "$(git status --porcelain --untracked-files=all)" ] || fail "작업 트리 또는 인덱스가 깨끗하지 않습니다. 파일을 수정하지 않고 중단합니다."

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || fail "현재 브랜치에 upstream이 없습니다. 파일을 수정하지 않고 중단합니다."
[ "$upstream" = "origin/$branch" ] || fail "upstream이 origin의 같은 이름 브랜치가 아닙니다: $upstream"

origin_fetch_urls=$(git remote get-url --all origin 2>/dev/null) || fail "origin fetch URL을 읽지 못했습니다. 파일을 수정하지 않고 중단합니다."
origin_push_urls=$(git remote get-url --push --all origin 2>/dev/null) || fail "origin push URL을 읽지 못했습니다. 파일을 수정하지 않고 중단합니다."
[ -n "$origin_fetch_urls" ] || fail "origin fetch URL이 비어 있습니다. 파일을 수정하지 않고 중단합니다."
[ "$(printf '%s\n' "$origin_fetch_urls" | wc -l | tr -d ' ')" -eq 1 ] || fail "origin fetch URL은 정확히 하나여야 합니다. 파일을 수정하지 않고 중단합니다."
[ "$(printf '%s\n' "$origin_push_urls" | wc -l | tr -d ' ')" -eq 1 ] || fail "origin push URL은 정확히 하나여야 합니다. 파일을 수정하지 않고 중단합니다."
[ "$origin_fetch_urls" = "$origin_push_urls" ] || fail "origin fetch URL과 push URL이 다릅니다. 파일을 수정하지 않고 중단합니다."
origin_url=$origin_fetch_urls

git fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" || fail "origin/$branch fetch에 실패했습니다. 파일을 수정하지 않고 중단합니다."
local_head=$(git rev-parse HEAD) || fail "로컬 HEAD를 읽지 못했습니다."
remote_head=$(git rev-parse "refs/remotes/origin/$branch") || fail "origin/$branch SHA를 읽지 못했습니다."
[ "$local_head" = "$remote_head" ] || fail "로컬 HEAD와 origin/$branch가 다릅니다. 파일을 수정하지 않고 중단합니다."

printf 'release branch: %s\n' "$branch"
printf 'release base: %s\n' "$local_head"
printf 'release origin URL: %s\n' "$origin_url"

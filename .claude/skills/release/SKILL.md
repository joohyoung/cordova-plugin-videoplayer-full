---
name: release
description: 이 저장소의 Cordova 플러그인 릴리스를 만든다. 명시적인 릴리스 요청이나 "$release", "/release" 호출에서 기존 version-up으로 버전을 올린 뒤 두 버전 파일만 커밋하고 annotated 태그와 현재 브랜치를 원자적으로 push·검증할 때 사용한다. 단순 버전 수정에는 version-up을 사용한다.
---

# release

이 저장소의 Cordova 플러그인 버전 커밋과 태그를 원격에 함께 게시한다. `npm publish`, GitHub release, CHANGELOG는 만들지 않는다.

단순히 버전 값만 바꾸라는 요청에는 이 스킬이 아니라 `version-up`을 사용한다. 이 스킬은 commit, tag, push까지 명시적으로 요청된 릴리스 작업에만 사용한다.

## 절차

1. 저장소 루트에서 `sh .claude/skills/release/scripts/preflight.sh`를 실행한다.
   - 이 스크립트는 작업 트리와 인덱스가 깨끗하고, 현재 symbolic branch의 upstream이 같은 이름의 `origin` 브랜치이며, fetch 후 로컬 HEAD와 원격 추적 브랜치가 같은지 확인한다.
   - `origin`의 fetch URL과 push URL은 동일한 값 하나씩만 허용한다. URL 원문은 출력하지 않으며, 출력된 branch, base SHA, origin URL의 SHA-256 fingerprint를 각각 `{브랜치}`, `{base}`, `{origin-fingerprint}`로 기록한다.
   - 실패하면 버전 파일을 수정하지 않고 중단한다.
2. 사용자가 준 명시 버전 또는 `major`·`minor`·`patch`를 기존 `version-up` 스킬에 그대로 넘긴다. 인자가 없으면 그 스킬의 후보 선택 절차를 따른다.
   - `version-up`의 결과에서 검증된 새 버전을 `{새버전}`으로 기록한다.
   - `version-up`이 실패하면 이 스킬도 중단한다. 파일이 이미 수정된 상태인지는 그 스킬의 결과대로 보고한다.
3. push 대상이 preflight가 보고한 현재 브랜치이고, 태그 이름이 `{새버전}`임을 사용자에게 알린다.
4. `sh .claude/skills/release/scripts/publish.sh "{새버전}" "{브랜치}" "{base}" "{origin-fingerprint}"`을 실행한다.
   - 인자에는 `version-up`이 검증한 안정 SemVer 값만 넣는다.
   - 스크립트는 버전 원본과 변경 경계를 다시 검증하고 `npm test`를 실행한 뒤 `package.json`과 `plugin.xml`만 stage·commit한다.
   - 두 파일은 base blob과 byte 단위로 비교해 지정된 version 필드·속성 외의 변경과 file mode 변경을 거부한다. `npm test` 뒤에도 branch, HEAD, upstream, origin URL, 작업 트리와 두 파일의 변경 경계를 다시 검증한다.
   - 같은 로컬·원격 태그가 없는 경우에만 `{새버전}` annotated 태그를 만든다.
   - 검증한 release commit SHA와 annotated tag object ID를 source로 삼은 완전한 refspec만 `--atomic --no-follow-tags`로 push하고, 원격 브랜치 SHA·태그 object ID·peeled SHA를 로컬 release 결과와 대조한다.
5. 이전 버전, 새 버전, release commit SHA, 태그, push 대상 브랜치, 원격 SHA 검증 결과를 요약한다.

## 실패 처리

- 어느 명령도 종료 코드가 0일 것이라고 출력 문구만 보고 가정하지 않는다.
- preflight 실패 후에는 `version-up`을 실행하지 않는다.
- `publish.sh`가 실패하면 비원자적 push나 force push로 재시도하지 않는다.
- version-up 이후 실패로 남은 버전 파일, staged change, commit 또는 tag를 자동으로 되돌리거나 삭제하지 않는다. 스크립트가 보고한 현재 상태와 다음 수동 조치가 필요한 지점을 그대로 전달한다.
- 기존 태그는 이동·삭제하지 않고 기존 `dev/*` 태그도 건드리지 않는다.
- 저장소에 커밋된 코드와 npm lifecycle script는 신뢰된 릴리스 입력으로 취급한다. 테스트는 격리 container에서 돌지 않으므로 lifecycle script 자체의 외부 부수효과를 되돌리거나 차단하지는 않지만, 테스트가 로컬 release 상태를 바꾸면 commit 전에 중단한다.
- push 직전에 원격 branch가 `{base}`이고 태그가 없는지 다시 확인한다. 이 스킬은 정책상 `--force-with-lease`도 사용하지 않으므로 조회 직후 원격 branch가 삭제되거나 `{base}`의 조상으로 되감기는 경쟁까지 클라이언트에서 exact-old CAS로 막지는 못한다. 릴리스 대상 원격 branch는 삭제·강제 갱신을 금지하는 보호 규칙을 전제로 하며, 일반 fast-forward가 아닌 변경은 서버에서 거부해야 한다.

## 책임 경계

- `version-up`: `package.json`과 `plugin.xml` 버전 수정 및 테스트. commit, tag, push 없음.
- `release`: `version-up`을 호출한 뒤 버전 파일 commit, annotated tag, 명시적 atomic push와 원격 SHA 검증.
- `/gh:changelog`: 기존처럼 `version-up`을 직접 사용한다. 이 `release` 스킬을 중간 단계로 호출하지 않는다.

이 스킬의 기준 구현은 `.claude/skills/release`이고 `.agents/skills/release`는 같은 디렉터리를 가리키는 저장소 상대 심볼릭 링크다.

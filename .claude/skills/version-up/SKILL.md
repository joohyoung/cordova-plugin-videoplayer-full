---
name: version-up
description: 이 저장소가 배포하는 Cordova 플러그인 버전을 올린다. package.json의 version과 plugin.xml 루트 plugin 요소의 version 속성을 같은 SemVer로 동기화하고 검증한다. 사용자가 "version up", "버전 올려", "버전 업", "버전업", "$version-up"이라고 요청할 때 사용한다. 커밋·태그·push·publish·release는 하지 않는다.
---

# version-up

이 저장소가 배포하는 **Cordova 플러그인 버전**을 올린다. Cordova CLI 버전이나 플랫폼(`cordova-ios`, `cordova-android`) 버전이 아니다.

버전 값은 두 곳에 있으며 항상 같아야 한다.

| 버전 원본 | 위치 |
|---|---|
| `package.json` | 최상위 객체의 `version` 필드 |
| `plugin.xml` | 루트 `<plugin>` 요소의 `version` 속성 |

## 버전 형식

- 안정 버전 SemVer `M.m.p` 만 받는다 (예: `1.0.7`).
- `M`, `m`, `p`는 각각 0 이상의 정수다. 앞자리 0을 붙인 값(`1.0.07`)은 받지 않는다.
- 프리릴리스·빌드 메타데이터(`-beta.1`, `+build.5`)는 이 스킬에서 받지 않는다.
- 앱 전용 4자리 빌드 번호, `android-versionCode`, `ios-CFBundleVersion`은 이 저장소에 없으며 이 스킬이 만들지 않는다.

## 절차

아래 순서를 그대로 따른다. 각 단계의 성패는 출력 문구가 아니라 **종료 코드**로 가린다. 어느 단계에서 중단하든 그 시점까지 파일을 수정하지 않았으면 아무것도 수정하지 않은 상태로 끝낸다.

### 1. 현재 버전 읽기

저장소 루트에서 아래 명령을 실행한다. 두 원본을 함께 읽어 `package.json`과 `plugin.xml` 값을 탭으로 구분해 낸다.

```bash
node -e '
const fs=require("fs");
function fail(m){console.error(m);process.exit(1);}
let p;
try{p=JSON.parse(fs.readFileSync("package.json","utf8"));}catch(e){fail("package.json 읽기/파싱 실패: "+e.message);}
const pv=p.version;
if(typeof pv!=="string"||pv==="")fail("package.json의 최상위 version 필드가 비었거나 문자열이 아닙니다");
let x;
try{x=fs.readFileSync("plugin.xml","utf8");}catch(e){fail("plugin.xml 읽기 실패: "+e.message);}
const t=x.replace(/<!--[\s\S]*?-->/g,"").match(/<plugin(?=[\s>\/])[^>]*>/);
if(!t)fail("plugin.xml에서 루트 <plugin> 여는 태그를 찾지 못했습니다");
const a=t[0].match(/\sversion\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)/);
if(!a)fail("plugin.xml 루트 <plugin>에 version 속성이 없습니다");
const xv=a[1]!==undefined?a[1]:a[2];
if(xv==="")fail("plugin.xml 루트 <plugin>의 version 속성이 비어 있습니다");
console.log("package.json\t"+pv);
console.log("plugin.xml\t"+xv);
'
```

이 명령이 지키는 것:

- **주석과 중첩 태그를 먼저 걷어 낸다.** XML 주석을 제거한 뒤 첫 `<plugin` **여는 태그 안에서만** `version`을 찾는다. 주석 처리된 `<!-- <plugin version="0.0.1"> -->`나 중첩된 `<plugin version="9.9.9"/>`의 값을 루트 값으로 잘못 읽지 않으며, 루트 태그에 `version`이 없으면 다른 태그로 넘어가지 않고 종료 코드 1로 끝난다.
- **큰따옴표와 작은따옴표를 모두 인식한다.** XML은 둘 다 허용하므로 어느 쪽이든 읽는다(스크립트를 작은따옴표 셸 문자열로 감쌀 수 있도록 정규식 안에서는 `\x27`로 적었다).
- **빈 값을 성공으로 읽지 않는다.** `version` 필드가 없거나(`undefined`), `null`이거나, 빈 문자열이거나, `version=""` 빈 속성이면 모두 종료 코드 1로 끝난다. 종료 코드만 보는 판정이 빈 출력을 정상으로 오독하지 않게 하려는 것이다.
- **스크립트를 작은따옴표로 감싼다.** 큰따옴표로 감싸면 `$`와 백틱이 셸에 먼저 해석되어 정규식 끝 앵커가 깨지거나 파일에서 읽은 값이 명령으로 실행될 수 있다. 이 스킬은 서로 다른 에이전트에서 실행되므로 셸 이스케이프에 의존하지 않는다.

처리:

- **비정상 종료하면** 그 출력을 그대로 보고하고 **파일을 수정하지 않은 채 중단한다.**
- 읽은 두 값을 각각 `{현재-package}`, `{현재-plugin}`으로 기록한다.

### 2. 두 원본의 현재 버전 일치·형식 확인

1단계와 같은 방식으로 두 값을 다시 읽어 비교와 형식 검증까지 한 번에 수행한다. 1단계 스크립트 끝의 두 `console.log` 줄을 아래로 바꿔 실행한다.

```bash
const SEMVER=/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
if(pv!==xv)fail("두 원본의 현재 버전이 다릅니다 (package.json="+pv+", plugin.xml="+xv+"). 파일을 수정하지 않고 중단합니다");
if(!SEMVER.test(pv))fail("현재 버전 "+pv+"은(는) 안정 버전 SemVer M.m.p가 아닙니다. 두 파일의 현재 값을 먼저 바로잡으십시오");
console.log(pv);
```

- **두 값이 다르면** 파일을 수정하지 않고 두 값과 각 파일 경로를 보고한 뒤 중단한다. 어느 쪽이 옳은지 이 스킬이 추측해 맞추지 않는다.
- **현재 버전이 `M.m.p` 형식이 아니면** 파일을 수정하지 않고 중단한다. 두 파일이 똑같이 `1.0.6-beta.1`처럼 적혀 있어도 여기서 걸린다 — 이 검사가 없으면 4단계의 수치 비교가 `NaN`을 내고 `NaN <= 0`이 `false`라 **다운그레이드가 통과한다.** 3단계의 patch/minor/major 후보 계산도 `M.m.p`가 아니면 정의되지 않는다.
- 두 검사를 지나면 그 값을 `{현재버전}`으로 기록하고 다음 단계로 간다.

### 3. 새 버전 정하기

호출 형태에 따라 세 갈래로 갈린다. **위에서부터 차례로 보고 처음 맞는 갈래를 쓴다.**

1. **증가 단위(`major` / `minor` / `patch`)를 받았으면** 그 단위를 `{현재버전}`에 적용해 `{새버전}`을 계산하고 4단계로 간다. **이 갈래에서는 후보를 제시하지도, 입력을 기다리지도 않는다.**
   - 이 갈래가 필요한 이유: 저장소 릴리스 절차(`/gh:changelog`)가 증가 단위를 스스로 결정한 뒤 이 스킬에 그 단위를 넘겨 호출한다. 그 호출은 사람이 답할 자리가 없으므로 단위를 받으면 곧바로 계산해야 한다.
2. **구체적인 새 버전 값을 받았으면** 그 값을 `{새버전}`으로 쓰고 4단계로 간다.
3. **아무것도 받지 않았으면** `{현재버전}`을 기준으로 세 후보를 계산해 보여 주고 어느 것으로 올릴지(또는 직접 입력할 값이 있는지) 입력받는다.

증가 단위의 계산식은 다음과 같다.

| 단위 | 계산 | `2.3.4` 기준 예시 |
|---|---|---|
| patch | `M.m.(p+1)` | `2.3.5` |
| minor | `M.(m+1).0` | `2.4.0` |
| major | `(M+1).0.0` | `3.0.0` |

- 후보 제시와 입력 수집은 실행 중인 에이전트가 쓸 수 있는 아무 방식으로나 한다. 특정 도구 이름에 의존하지 않는다.
- **대화형 입력이 불가능한 실행 환경이면**(무인 실행, 루프 실행 등) 임의로 고르지 말고 계산한 후보만 출력한 뒤 중단한다. 3번 갈래에서 입력을 받지 못한 경우도 같다.

### 4. 새 버전 검증

3단계의 세 갈래 어디를 지났든 아래 명령으로 검증한다. 인자를 주지 않으면 후보를 출력하고(3단계 3번 갈래), `major`·`minor`·`patch`를 주면 계산해 검증하며(1번 갈래), 구체적인 값을 주면 그 값을 검증한다(2번 갈래).

1단계 스크립트 끝의 두 `console.log` 줄을 아래로 바꾸고, 인자를 `node -e '…' {인자}` 형태로 넘겨 실행한다.

```bash
const SEMVER=/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
if(pv!==xv)fail("두 원본의 현재 버전이 다릅니다 (package.json="+pv+", plugin.xml="+xv+"). 파일을 수정하지 않고 중단합니다");
if(!SEMVER.test(pv))fail("현재 버전 "+pv+"은(는) 안정 버전 SemVer M.m.p가 아닙니다. 두 파일의 현재 값을 먼저 바로잡으십시오");
const u=process.argv[1];
const n=pv.split(".").map(Number);
const cand={patch:[n[0],n[1],n[2]+1].join("."),minor:[n[0],n[1]+1,0].join("."),major:[n[0]+1,0,0].join(".")};
if(u===undefined){console.log("현재 버전: "+pv);console.log("patch\t"+cand.patch);console.log("minor\t"+cand.minor);console.log("major\t"+cand.major);process.exit(0);}
const next=Object.prototype.hasOwnProperty.call(cand,u)?cand[u]:u;
if(!SEMVER.test(next))fail("새 버전 "+next+"은(는) 안정 버전 SemVer M.m.p가 아닙니다");
const b=next.split(".").map(Number);
const cmp=(b[0]-n[0])||(b[1]-n[1])||(b[2]-n[2]);
if(!(cmp>0))fail("새 버전 "+next+"은(는) 현재 버전 "+pv+"보다 크지 않습니다");
console.log(next);
```

- 이 명령은 **현재 버전을 두 파일에서 스스로 다시 읽는다.** 앞 단계에서 읽은 값을 명령 문자열에 되붙이지 않으므로, 파일 내용이 명령으로 해석될 자리가 없다.
- 인자로 넘기는 것은 사용자나 호출자가 정한 단위·버전 값 하나뿐이다. 그 값에 공백이나 셸 메타문자가 있으면 명령에 넣지 말고 그대로 보고한 뒤 중단한다.
- 비교는 사전순이 아니라 **수치로** 한다 (`1.0.10`은 `1.0.9`보다 크다). `!(cmp>0)`으로 판정하므로 `cmp`가 `NaN`이어도 실패로 떨어진다.
- 하나라도 어긋나면 **파일을 수정하지 않고** 사유를 보고한 뒤 중단한다. 값을 추측해 고쳐 쓰지 않는다.
- 통과하면 출력된 값을 `{새버전}`으로 기록한다.

### 5. 두 파일 수정

검증을 통과한 경우에만 수정한다. **아래 두 값 외에는 아무것도 바꾸지 않는다.**

- `package.json`: 최상위 `version` 필드의 값 `{현재버전}` → `{새버전}`.
  - `"version": "{현재버전}"` 한 곳만 바꾼다. 파일 전체를 다시 직렬화하거나 들여쓰기·키 순서를 바꾸지 않는다.
  - `npm version`은 쓰지 않는다 — 태그를 만들고 lifecycle 스크립트를 돌린다.
- `plugin.xml`: 루트 `<plugin>` 여는 태그의 `version="{현재버전}"` → `version="{새버전}"`.
  - 파일 안에 다른 `version` 속성이 생기더라도 루트 `<plugin>`의 것만 바꾼다.

수정은 실행 중인 에이전트의 파일 편집 수단으로 하며, 특정 도구 이름에 의존하지 않는다.

### 6. 검증

1. 1단계와 같은 두 명령으로 값을 **다시 읽는다.**
2. 두 값이 서로 같고 `{새버전}`과 정확히 일치하는지 확인한다. 어긋나면 어느 파일이 어떤 값인지 보고하고 중단한다 — 한쪽만 바뀐 상태를 그대로 두지 말고 사용자에게 알린다.
3. `git diff --name-only`로 이번에 바뀐 파일이 `package.json`과 `plugin.xml` 둘뿐인지 확인한다. 그 밖의 파일이 있으면 보고한다.
4. `npm test`를 실행한다.
   - 실패하면 실패 출력을 그대로 보고한다. 이 스킬은 실패를 자동으로 고치지 않는다.

### 7. 요약

다음을 표로 보고한다.

- 이전 버전, 새 버전
- 수정한 파일 (`package.json`, `plugin.xml`)
- 두 원본의 값 일치 여부
- `npm test` 결과

## 하지 않는 것

이 스킬은 아래를 **수행하지 않는다.** 사용자가 별도로 요청하면 그때 다른 절차로 처리한다.

- `git commit`, `git tag`, `git push`
- `npm publish`
- GitHub release 생성
- CHANGELOG 작성
- Cordova CLI 버전 변경
- `cordova-ios`, `cordova-android` 등 플랫폼 버전 변경
- `package.json`의 `engines.cordovaDependencies` 변경
- 이 플러그인을 사용하는 상위 앱의 앱 버전 또는 빌드 번호 변경

## 중단 조건 요약

아래 중 하나라도 걸리면 **파일을 수정하지 않은 채** 사유를 보고하고 멈춘다.

- 두 원본에서 현재 버전을 읽지 못함 (1단계)
- 두 원본의 현재 버전이 서로 다름 (2단계)
- 새 버전을 입력받지 못함 (3단계)
- 새 버전이 `M.m.p` 형식이 아님 (4단계)
- 새 버전이 현재 버전보다 크지 않음 (4단계)

수정 후 검증(6단계)에서 어긋난 경우에는 이미 바꾼 값을 되돌리지 말고, 무엇이 어긋났는지 그대로 보고한다.

## 이 스킬이 두 경로에 있는 이유

기준 구현은 `.claude/skills/version-up/SKILL.md` 하나뿐이다. `.agents/skills/version-up`은 그 디렉터리를 가리키는 저장소 상대 심볼릭 링크다.

- Claude Code는 프로젝트 스킬을 `.claude/skills/<이름>/SKILL.md`에서 읽는다.
- Codex는 `$REPO_ROOT/.agents/skills`를 탐색하고 심볼릭 링크된 스킬 폴더의 링크 대상을 따라간다.

사본을 두 벌 두지 않으므로 두 제품이 언제나 같은 절차를 실행한다. 이 스킬을 고칠 때는 `.claude/skills/version-up/SKILL.md`만 고친다.

# DotDesk

[English](README.md) | **한국어**

내 Mac에서 일하는 AI 코딩 에이전트(Claude Code, Codex)를 귀여운 도트 캐릭터로 보여주는 macOS 앱.

- **데스크톱 펫** — 지금 일하는 에이전트가 화면 아래를 돌아다니다가, 일을 시작하면 멈춰서 타이핑하거나 문서를 읽어요. 말풍선 아이콘으로 지금 하는 일(읽기·검색·작성·실행·웹·팀원 호출·계획…)을 보여줘요. 쉬는 동안에는 낮잠, 커피, 게임, 독서, 스트레칭을 번갈아 해요.
- **사무실 창** — 화면 구석의 작은 창에 여러 에이전트가 프로젝트별 구역으로 나뉘어 앉아 일해요. 모니터 화면도 하는 일에 따라 바뀌고, 서브에이전트는 책상 앞에 팀원으로 나타나요. 한동안 조용하면 쉬러 가서 소파 낮잠, 빈백에서 책 읽기, 커피 마시기, 화분 물 주기, 창밖 구경, 창가에서 둘이 수다 떨기, 스트레칭 같은 걸 무작위로 골라 하고, 시간이 지나면 다른 걸 해요.
- **권한 요청 응답** — 에이전트 창으로 가지 않고 펫 말풍선에서 허용/거부하거나, 자동 허용(바이패스)할 수 있어요. 자동 허용이어도 `rm -rf` 같은 위험한 명령은 따로 물어볼 수 있어요.
- **여러 계정·조직 구분** — `CLAUDE_CONFIG_DIR`/`CODEX_HOME`별 로그인 계정을 읽어서 책상 깃발 색과 이름표로 구분해요.
- **캐릭터 고르기** — 새 에이전트마다 머리와 옷을 무작위로 조합해요. 기본 도트 프리셋 8종, [Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents) 캐릭터, [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)에서 모은 포켓몬 중에서 에이전트·프로젝트별로 고를 수 있어요.

## 설치

[Releases](https://github.com/cadenzah/dotdesk/releases/latest)에서 `DotDesk-<버전>.zip`을 내려받아 압축을 풀고, `DotDesk.app`을 `응용 프로그램` 폴더로 옮기세요. macOS 14 이상, Apple Silicon Mac에서 동작해요.

### 처음 실행하기

DotDesk는 Apple 개발자 인증서로 서명하거나 공증(notarization)받지 않은 앱이에요. 그래서 처음 열면 macOS가 *"Apple은 'DotDesk'에 악성 코드가 없음을 확인할 수 없습니다"* 같은 경고를 띄우고 실행을 막아요. 아래 방법 중 하나로 한 번만 허용하면 그다음부터는 그냥 열려요.

**방법 1. 시스템 설정에서 허용 (macOS 15 이상)**

1. `DotDesk.app`을 더블클릭해요. 경고가 뜨면 **완료**를 눌러 닫아요.
2. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 아래쪽 **보안** 항목까지 내려요.
3. *"'DotDesk'이(가) 확인된 개발자가 아니기 때문에 사용이 차단되었습니다"* 옆의 **그래도 열기**를 눌러요. (경고를 띄운 뒤 한 시간쯤 안에만 보여요.)
4. 암호나 Touch ID로 확인하고, 다시 뜨는 창에서 **그래도 열기**를 눌러요.

**방법 2. 우클릭으로 열기 (macOS 14)**

Finder에서 `DotDesk.app`을 우클릭(또는 Control-클릭)하고 **열기**를 고른 뒤, 경고 창에서 다시 **열기**를 눌러요. macOS 15부터는 이 방법이 막혀서 방법 1을 써야 해요.

**방법 3. 터미널에서 격리 표시 지우기**

내려받은 파일에 붙는 격리 표시(`com.apple.quarantine`)를 지우면 경고 없이 열려요. *"'DotDesk'이(가) 손상되었기 때문에 열 수 없습니다"*라는 메시지가 뜰 때도 이 방법으로 해결돼요.

```sh
xattr -dr com.apple.quarantine /Applications/DotDesk.app
```

> 이 경고는 앱이 위험하다는 뜻이 아니라, Apple이 확인한 적 없는 개발자의 앱이라는 뜻이에요. 그래도 걱정되면 아래처럼 소스에서 직접 빌드해서 쓰세요. 직접 빌드한 앱에는 격리 표시가 붙지 않아 경고 없이 열려요.

## 빌드와 실행

macOS 14 이상, Xcode(또는 Swift 5.10+ 툴체인)가 필요해요.

```sh
./scripts/build-app.sh   # build/DotDesk.app 생성 (ad-hoc 서명)
open build/DotDesk.app
```

처음 실행하면 설정의 **연동** 탭이 열려요. **훅 설치**를 누르면 DotDesk가 이벤트를 받기 시작해요. 이미 열려 있는 Claude Code 세션에도 바로 반영돼요.

실제 에이전트 없이 보고 싶으면 메뉴바의 **데모 에이전트**를 켜거나 `scripts/simulate-agent.sh`를 실행하세요.

### 지우기

1. 설정 **연동** 탭에서 각 설정 폴더의 **훅 제거**를 눌러요. `dotdesk-hook`이 들어간 항목만 지워져요.
2. 앱을 끝내고 `DotDesk.app`, `~/.dotdesk`(릴레이 스크립트·토큰), `~/Library/Application Support/DotDesk`(설정)를 지우면 돼요.

## 동작 방식

```
Claude Code / Codex ──hook──▶ ~/.dotdesk/dotdesk-hook.sh ──HTTP(127.0.0.1)──▶ DotDesk
Codex 세션 기록(~/.codex/sessions/**/rollout-*.jsonl) ──────────tail──────────▶ DotDesk
```

- **Claude Code**: `~/.claude/settings.json`(또는 각 `CLAUDE_CONFIG_DIR`)의 `hooks`에 릴레이 스크립트를 등록해요. 처음 설치할 때 `settings.json.dotdesk.backup`으로 백업하고, 지울 때는 `dotdesk-hook`이 들어간 항목만 지워요. Claude 데스크톱 앱의 Code 탭도 같은 설정을 쓰므로 함께 보여요.
- **Codex**: `~/.codex/hooks.json`에 같은 형식으로 등록해요. Codex는 새 훅을 신뢰해야 실행하므로 `codex`의 `/hooks`에서 승인해 주세요. 훅 없이도 세션 기록 파일을 읽어서 활동을 보여줘요(이때는 권한 응답이 안 돼요).
- 릴레이 스크립트는 DotDesk가 꺼져 있으면 아무것도 출력하지 않고 바로 끝나요. 에이전트는 평소처럼 동작해요.
- 이벤트 서버는 `127.0.0.1`에서만 열리고, `~/.dotdesk/token`(권한 0600)의 토큰이 맞아야 요청을 받아요.

### 권한 요청 모드

| 모드 | 동작 |
|---|---|
| 에이전트 창에서 직접 응답 (기본) | 지금처럼 터미널/앱에서 허락. 펫은 손 들고 기다리는 모습만 |
| 펫 말풍선에서 응답 | 펫·사무실에 허용/거부 카드. 시간 안에 답이 없으면 원래 흐름으로 넘김 |
| 자동 허용 (바이패스) | 묻지 않고 허용. 위험 패턴(설정에서 편집)은 말풍선으로 확인 |

전체 설정 외에 프로젝트별로 다르게 하거나, 세션 하나만 "이 세션 자동 허용"으로 바꿀 수 있어요. 자동 허용이어도 Claude Code의 `deny` 규칙은 그대로 지켜져요.

### 계정 구분

- Claude: `$CLAUDE_CONFIG_DIR/.claude.json`(기본은 `~/.claude.json`)의 `oauthAccount`에서 이메일·조직 이름을 읽어요.
- Codex: `$CODEX_HOME/auth.json`의 ID 토큰에서 이메일·플랜·조직 이름만 읽어요.
- 토큰 자체는 저장하거나 어디로도 보내지 않아요. 설정의 **계정** 탭에서 이름과 깃발 색을 정할 수 있어요.

## 에셋과 라이선스

- DotDesk 코드와 기본 도트 캐릭터·가구는 직접 그린 것으로 [MIT 라이선스](LICENSE)예요.
- **Pixel Agents 에셋**은 앱에 포함하지 않아요. VS Code(또는 Cursor·Windsurf)에 설치된 Pixel Agents 확장 프로그램 폴더에서 캐릭터와 일부 가구(책상·화분·소파·시계)를 읽어요. 가구는 설정에서 끌 수 있어요. Pixel Agents는 MIT이고, 캐릭터는 [JIK-A-4의 MetroCity 팩(CC0)](https://jik-a-4.itch.io/metrocity-free-topdown-character-pack)을 바탕으로 해요.
- **포켓몬 스프라이트**는 Nintendo/Game Freak/The Pokémon Company의 저작물이라 앱에 포함하지 않아요. PokeTokenBar가 [PokeAPI/sprites](https://github.com/PokeAPI/sprites)에서 내려받아 둔 로컬 파일(`~/Library/Application Support/PokeTokenBar/sprites`)을 그대로 읽어요. 개인적·비상업적 용도로만 써 주세요.
- 다른 캐릭터 시트를 쓰려면 Pixel Agents 형식(16×32 프레임, 행: 아래/위/오른쪽, 열: 걷기1·서기·걷기2·타이핑1·타이핑2·읽기1·읽기2)의 `characters/char_N.png`가 든 폴더를 설정에서 지정하면 돼요.

DotDesk는 비공식 개인 프로젝트예요. Anthropic, OpenAI, Nintendo, Game Freak, Creatures Inc., The Pokémon Company와 관련이 없고 이들의 보증을 받지 않았어요. Claude, Codex, Pokémon 등의 상표는 각 소유자의 것이에요.

## 개발

```
Sources/DotDesk/
  App/       앱 진입점, 메뉴바, 개발용 렌더러
  Core/      이벤트 서버, 훅 설치, 세션 상태, 계정·프로젝트 판별, Codex 기록 감시, 설정
  Sprites/   도트 캔버스, 기본 캐릭터·가구·아이콘, 에셋 로더
  UI/        펫, 사무실 시뮬레이션/렌더러, 설정 화면
scripts/
  build-app.sh       .app 번들 만들기
  bump-version.sh    커밋 접두어로 VERSION 올리기
  make-icon.sh       아이콘 다시 만들기
  simulate-agent.sh  가짜 Claude 세션 이벤트 보내기
```

- `swift build && .build/debug/DotDesk --render-preview /tmp/dotdesk-preview` — 캐릭터 시트, 아이콘, 데모 사무실, 설정 화면을 PNG로 저장해요(화면 녹화 권한 없이 확인할 때 유용해요).
- 릴리스: `scripts/bump-version.sh`를 실행하면 마지막 릴리스 이후 커밋을 보고 `VERSION`을 올려서 커밋해요(`feat` → minor, `fix`·`perf` → patch, 나머지는 그대로. `patch`/`minor`/`major`/`X.Y.Z`로 직접 정하거나 `-n`으로 미리 볼 수 있어요). 그다음 `main`에 push하면 GitHub Actions(`.github/workflows/release.yml`)가 앱을 빌드해서 `v<버전>` Release에 zip으로 올려요. 이미 올라간 버전이면 건너뛰어요.
- 앱이 실행 중일 때 `curl -X POST -H "X-DotDesk-Token: $(cat ~/.dotdesk/token)" http://127.0.0.1:$(cat ~/.dotdesk/port)/debug/snapshot`을 보내면 열린 창과 세션 상태를 `~/.dotdesk/snapshots/`에 저장해요.

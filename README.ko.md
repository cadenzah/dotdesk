# DotDesk

[English](README.md) | **한국어**

내 Mac에서 일하는 AI 코딩 에이전트(Claude Code, Codex)를 귀여운 도트 캐릭터로 보여주는 macOS 앱.

- **데스크톱 펫** — 지금 일하는 에이전트가 화면 아래를 돌아다니다가, 일을 시작하면 멈춰서 타이핑하거나 문서를 읽어요. 말풍선 아이콘으로 지금 하는 일(읽기·검색·작성·실행·웹·팀원 호출·계획…)을 보여줘요. 쉬는 동안에는 낮잠, 커피, 게임, 독서, 스트레칭을 번갈아 해요.
- **사무실 창** — 화면 구석의 작은 창에 여러 에이전트가 프로젝트별 구역으로 나뉘어 앉아 일해요. 모니터 화면도 하는 일에 따라 바뀌고, 서브에이전트는 책상 앞에 팀원으로 나타나요. 한동안 조용하면 쉬러 가서 소파 낮잠, 빈백에서 책 읽기, 커피 마시기, 화분 물 주기, 창밖 구경, 창가에서 둘이 수다 떨기, 스트레칭 같은 걸 무작위로 골라 하고, 시간이 지나면 다른 걸 해요. 같은 프로젝트에 새 세션이 생기면 일을 마쳤거나 쉬고 있던 캐릭터가 이어서 맡아요(`/clear` 뒤에도 같은 캐릭터예요). 자리를 넘겨준 세션이 다시 일하면 쉬는 동료나 새 캐릭터가 들어와요.
- **권한 요청 응답** — 에이전트 창으로 가지 않고 펫 말풍선에서 허용/거부하거나, 자동 허용(바이패스)할 수 있어요. 자동 허용은 모든 권한 확인을 끄는 것과 같으니 [주의사항](#자동-허용을-켜기-전에)을 먼저 읽어 주세요.
- **에이전트 창으로 가기** — 펫을 클릭하거나 사무실에서 캐릭터를 더블클릭하면 그 에이전트가 일하는 터미널이나 앱 창을 앞으로 가져와요. Terminal과 iTerm2는 탭까지 정확히 고르고(처음 한 번 제어 권한을 물어봐요), tmux 안이면 그 창과 패널도 골라요. VS Code·Cursor·Ghostty 같은 다른 앱은 앱을 앞으로 가져오고, 설정 **연동** 탭에서 손쉬운 사용 권한을 주면 프로젝트 이름이 제목에 든 창을 골라요.
- **소리와 알림** — 에이전트가 허락을 기다리거나, 질문하거나, 오래 걸린 일을 마치면 소리를 내고 macOS 알림도 띄울 수 있어요. 알림을 누르면 그 에이전트의 창으로 가고, 펫 말풍선 응답 모드에서는 알림에서 바로 허용·거부할 수 있어요. 1분 동안 답이 없으면 펫이 화면 가운데로 걸어와 손을 흔들며 한 번 더 불러요. 에이전트 앱을 보고 있을 때는 조용하고, 메뉴바에서 **알림 소리**를 바로 끌 수 있어요. 설정 **알림** 탭에서 고를 수 있어요.
- **성공·실패 리액션** — 도구 호출이 실패하면 어지러운 말풍선과 함께 몸을 흔들고, 테스트(pytest, jest, `swift test`, `go test`, `npm test` 등)가 통과하면 반짝이며 환호하고, 실패하면 빨간 ✕를 띄워요. 5분 넘게 걸린 일을 마치면 색종이를 뿌려요.
- **하루 기록과 퇴근 요약** — 날마다 일한 시간(시간대별·프로젝트별), 요청, 끝낸 작업, 고친 파일, 테스트 결과, 토큰을 모아요. 사무실 벽 화이트보드에 최근 12시간을 그래프로 그리고, 퇴근할 때(오후 6시가 지나 모든 에이전트가 20분 동안 쉬면) 오늘과 지난 7일을 담은 요약 카드를 띄워요. 메뉴바의 **오늘의 기록…**이나 화이트보드를 눌러 언제든 볼 수 있어요.
- **컨텍스트 게이지** — 세션의 대화 기록 파일을 읽어서 컨텍스트가 얼마나 찼는지 펫 말풍선과 사무실 이름표 아래에 막대로 보여주고, 지금까지 쓴 출력 토큰도 알려줘요. 80%를 넘으면 캐릭터가 땀을 흘리고, 대화를 정리(compact)하는 동안에는 상자에 서류를 싸요. Claude의 컨텍스트 크기는 모델 이름에 `[1m]`이 있거나 20만 토큰을 넘긴 적이 있으면 1M, 아니면 200K로 짐작하고, 설정 **일반** 탭에서 직접 고를 수 있어요. Codex는 스스로 알려주는 값을 써요.
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
| 자동 허용 (바이패스) | 묻지 않고 허용. 위험 패턴(설정에서 편집)이 든 셸 명령만 말풍선으로 확인 |

전체 설정 외에 프로젝트별로 다르게 하거나, 세션 하나만 "이 세션 자동 허용"으로 바꿀 수 있어요. 어느 쪽이든 켤 때 확인 창이 한 번 떠요.

#### 자동 허용을 켜기 전에

자동 허용은 Claude Code의 `--dangerously-skip-permissions`와 거의 같아요. 켜면 원래 물어봤을 모든 작업이 바로 실행돼요.

- 파일 수정·삭제, 셸 명령, 네트워크 요청, MCP 도구를 모두 묻지 않고 허용해요. 프로젝트 밖의 파일(`~/.zshrc`, `.git/hooks`, `~/.claude/settings.json` 등)도 예외가 아니에요.
- 에이전트가 웹페이지·이슈·파일에 숨은 지시(프롬프트 인젝션)를 따르면, 그 지시도 확인 없이 실행돼요.
- **위험 패턴은 안전장치가 아니에요.** 셸 명령에 적어 둔 글자가 그대로 들어 있을 때만 물어보는 편의 기능이라, `rm -r -f`나 `find . -delete`처럼 다르게 쓴 명령이나 파일 쓰기 같은 셸이 아닌 도구는 잡지 못해요.
- 믿을 수 있는 프로젝트나 컨테이너·VM 같은 격리된 환경에서만 쓰세요. 꼭 막아야 할 작업은 Claude Code의 `permissions.deny` 규칙으로 막으세요. deny 규칙은 자동 허용이어도 그대로 지켜져요.

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

# DotDesk

내 Mac에서 일하는 AI 코딩 에이전트(Claude Code, Codex)를 귀여운 도트 캐릭터로 보여주는 macOS 앱.

- **데스크톱 펫** — 지금 일하는 에이전트가 화면 아래를 돌아다니다가, 일을 시작하면 멈춰서 타이핑하거나 문서를 읽어요. 말풍선 아이콘으로 지금 하는 일(읽기·검색·작성·실행·웹·팀원 호출·계획…)을 보여줘요.
- **사무실 창** — 화면 구석의 작은 창에 여러 에이전트가 프로젝트별 구역으로 나뉘어 앉아 일해요. 모니터 화면도 하는 일에 따라 바뀌고, 서브에이전트는 책상 앞에 팀원으로 나타나요. 한동안 조용하면 라운지 소파로 가서 자요.
- **권한 요청 응답** — 에이전트 창으로 가지 않고 펫 말풍선에서 허용/거부하거나, 자동 허용(바이패스)할 수 있어요. 자동 허용이어도 `rm -rf` 같은 위험한 명령은 따로 물어볼 수 있어요.
- **여러 계정·조직 구분** — `CLAUDE_CONFIG_DIR`/`CODEX_HOME`별 로그인 계정을 읽어서 책상 깃발 색과 이름표로 구분해요.
- **캐릭터 고르기** — 기본 도트 캐릭터 8종, [Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents) 캐릭터, [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)에서 모은 포켓몬 중에서 에이전트·프로젝트별로 고를 수 있어요.

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

DotDesk는 비공식 개인 프로젝트예요. Anthropic, OpenAI, Nintendo, Game Freak, Creatures Inc., The Pokémon Company와 관련이 없고 이들의 보증을 받지 않았어요. Claude, Codex, Pokémon 등의 상표는 각 소유자의 것이에요.
- 다른 캐릭터 시트를 쓰려면 Pixel Agents 형식(16×32 프레임, 행: 아래/위/오른쪽, 열: 걷기1·서기·걷기2·타이핑1·타이핑2·읽기1·읽기2)의 `characters/char_N.png`가 든 폴더를 설정에서 지정하면 돼요.

## 개발

```
Sources/DotDesk/
  App/       앱 진입점, 메뉴바, 개발용 렌더러
  Core/      이벤트 서버, 훅 설치, 세션 상태, 계정·프로젝트 판별, Codex 기록 감시, 설정
  Sprites/   도트 캔버스, 기본 캐릭터·가구·아이콘, 에셋 로더
  UI/        펫, 사무실 시뮬레이션/렌더러, 설정 화면
scripts/
  build-app.sh       .app 번들 만들기
  make-icon.sh       아이콘 다시 만들기
  simulate-agent.sh  가짜 Claude 세션 이벤트 보내기
```

- `swift build && .build/debug/DotDesk --render-preview /tmp/dotdesk-preview` — 캐릭터 시트, 아이콘, 데모 사무실, 설정 화면을 PNG로 저장해요(화면 녹화 권한 없이 확인할 때 유용해요).
- 앱이 실행 중일 때 `curl -X POST -H "X-DotDesk-Token: $(cat ~/.dotdesk/token)" http://127.0.0.1:$(cat ~/.dotdesk/port)/debug/snapshot`을 보내면 열린 창과 세션 상태를 `~/.dotdesk/snapshots/`에 저장해요.

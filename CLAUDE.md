# DotDesk

## 커밋 메시지

- `<접두어>: <한국어 설명>` 형식으로, 설명은 "~함"으로 끝내요. 예: `fix: 말풍선이 캐릭터 바운스를 따라 흔들리지 않게 함`
- 접두어는 `feat`(기능 추가·변경), `fix`(버그 수정), `perf`(성능), `docs`, `chore`, `refactor` 중에서 골라요. 버전 계산이 이 접두어에 기대므로 반드시 붙여요.
- 호환이 깨지는 변경은 `feat!:`처럼 `!`를 붙이거나 본문에 `BREAKING CHANGE:`를 써요.

## 버전과 릴리스

- 버전은 루트의 `VERSION` 파일 하나가 기준이에요(SemVer, `X.Y.Z`). `scripts/build-app.sh`가 이 값을 `Info.plist`에 넣어요.
- `VERSION`이 바뀐 커밋이 `main`에 push되면 `.github/workflows/release.yml`이 앱을 빌드해서 `v<버전>` GitHub Release를 만들어요. 그러니 **push가 곧 릴리스**예요.
- `VERSION`을 손으로 고치지 말고 `scripts/bump-version.sh`를 써요. 이 스크립트는 `VERSION`만 커밋하고, 다른 변경(스테이징된 것 포함)은 건드리지 않아요.

### 자동 결정 규칙 (마지막 릴리스 태그 `v<VERSION>` 이후 커밋 기준)

| 커밋 | 올리는 자리 |
|---|---|
| `feat!:` 등 `!` 또는 `BREAKING CHANGE` | major (단, 1.0 전에는 minor) |
| `feat:` | minor |
| `fix:`, `perf:` | patch |
| `docs`, `chore`, `refactor` 등만 있음 | 안 올림 |

### 버전 관련 지시를 받았을 때

| 지시 예 | 할 일 |
|---|---|
| "버전 올려줘", "릴리스 준비해줘" | `scripts/bump-version.sh -n`으로 근거 커밋과 결과를 먼저 보여주고, 이어서 `scripts/bump-version.sh` 실행 |
| "다음 버전 뭐가 돼?", "올릴 게 있어?" | `scripts/bump-version.sh -n`만 실행하고 보고 |
| "패치로 / 마이너로 / 메이저로 올려줘" | `scripts/bump-version.sh patch` / `minor` / `major` |
| "1.0으로 올려줘", "0.3.2로 맞춰줘" | `scripts/bump-version.sh 1.0.0` / `0.3.2` |
| "릴리스해줘", "배포해줘" | 위처럼 버전을 올린 뒤 push 여부를 물어보고, 허락받으면 `main`에 push |

- push는 사용자가 요청하거나 허락했을 때만 해요. 버전만 올려 달라고 하면 커밋에서 멈춰요.
- 스크립트가 "아직 릴리스되지 않았어요"라고 하면, 지금 `VERSION`이 아직 push되지 않은 상태예요. 단계를 직접 지정해서 한 번 더 올리지 말고 사용자에게 알려요.
- 스크립트가 "릴리스할 변경이 없어요"라고 하면 그대로 보고하고, 억지로 올리지 않아요.
- 릴리스 태그는 GitHub에서 만들어지므로 로컬에 없을 수 있어요. 스크립트가 먼저 `git fetch --tags`를 해요.

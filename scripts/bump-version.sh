#!/bin/sh
# Bumps VERSION from the commits since the last release (tag v<VERSION>) and commits only VERSION.
#   scripts/bump-version.sh                  # 커밋 접두어로 자동 결정: feat → minor, fix·perf → patch, 그 외는 그대로
#   scripts/bump-version.sh patch|minor|major|X.Y.Z   # 직접 지정
#   scripts/bump-version.sh -n [...]         # 계산 결과만 보여주고 바꾸지 않음
# push하면 .github/workflows/release.yml이 새 버전을 릴리스해요.
set -e
cd "$(dirname "$0")/.."

DRY_RUN=
if [ "$1" = "-n" ]; then DRY_RUN=1; shift; fi
LEVEL="$1"

if ! git diff --quiet HEAD -- VERSION; then
  echo "VERSION에 커밋하지 않은 변경이 있어요. 먼저 정리하세요." >&2
  exit 1
fi

CURRENT=$(tr -d '[:space:]' < VERSION)
# 릴리스 태그는 GitHub에서 만들어지므로 먼저 가져와요.
git fetch --tags --quiet origin 2>/dev/null || true

if [ -z "$LEVEL" ]; then
  if ! git rev-parse -q --verify "refs/tags/v$CURRENT" >/dev/null; then
    echo "v$CURRENT은 아직 릴리스되지 않았어요. 지금 push하면 $CURRENT 그대로 릴리스돼요." >&2
    echo "그래도 올리려면 단계를 직접 지정하세요: $0 patch|minor|major|X.Y.Z" >&2
    exit 1
  fi
  RANGE="v$CURRENT..HEAD"
  echo "v$CURRENT 이후 커밋:"
  git log --format='  %h %s' "$RANGE"
  SUBJECTS=$(git log --format=%s "$RANGE")
  if printf '%s\n' "$SUBJECTS" | grep -Eq '^[a-z]+(\([^)]*\))?!:' \
    || git log --format=%b "$RANGE" | grep -q '^BREAKING CHANGE'; then
    LEVEL=major
  elif printf '%s\n' "$SUBJECTS" | grep -Eq '^feat(\([^)]*\))?:'; then
    LEVEL=minor
  elif printf '%s\n' "$SUBJECTS" | grep -Eq '^(fix|perf)(\([^)]*\))?:'; then
    LEVEL=patch
  else
    echo "릴리스할 변경(feat·fix·perf)이 없어요. 버전을 $CURRENT 그대로 둬요."
    exit 0
  fi
  # 1.0 전에는 호환이 깨지는 변경도 minor로 올려요.
  if [ "$LEVEL" = major ] && [ "${CURRENT%%.*}" = 0 ]; then
    echo "호환이 깨지는 변경이 있지만 1.0 전이라 minor로 올려요."
    LEVEL=minor
  fi
fi

IFS=. read -r MAJOR MINOR PATCH <<EOF
$CURRENT
EOF
case "$LEVEL" in
  major) NEXT="$((MAJOR + 1)).0.0" ;;
  minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
  patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  *)
    if ! printf '%s' "$LEVEL" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "알 수 없는 단계예요: $LEVEL (patch | minor | major | X.Y.Z)" >&2
      exit 1
    fi
    NEXT="$LEVEL" ;;
esac

if [ "$NEXT" = "$CURRENT" ] || git rev-parse -q --verify "refs/tags/v$NEXT" >/dev/null; then
  echo "v$NEXT은 이미 있는 버전이에요." >&2
  exit 1
fi

if [ -n "$DRY_RUN" ]; then
  echo "$CURRENT → $NEXT ($LEVEL, 바꾸지 않음)"
  exit 0
fi

printf '%s\n' "$NEXT" > VERSION
git commit -q -m "chore: 버전 올림 ($CURRENT → $NEXT)" -- VERSION
echo "$CURRENT → $NEXT ($LEVEL) 커밋했어요. push하면 v$NEXT 릴리스가 만들어져요."

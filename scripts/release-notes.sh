#!/bin/sh
# Prints release notes for v<VERSION> from the commit prefixes since the previous release tag.
#   scripts/release-notes.sh             # VERSION 파일의 버전, HEAD까지
#   scripts/release-notes.sh 0.2.0 [ref] # 버전과 끝 커밋을 직접 지정
# feat·fix·perf와 호환이 깨지는 변경만 싣고, docs·chore·refactor 등은 빼요.
# 제목과 안내 문구는 영어예요. 항목은 커밋 본문의 "Release-Note: <영어 한 줄>"을 쓰고,
# 없으면 커밋 제목(접두어 뺀 부분)을 그대로 써요.
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
REF="${2:-HEAD}"
TAG="v$VERSION"
if ! git rev-parse -q --verify "$REF^{commit}" >/dev/null; then
  echo "커밋을 찾을 수 없어요: $REF (태그라면 git fetch --tags를 먼저 하세요)" >&2
  exit 1
fi
REPO="${GITHUB_REPOSITORY:-$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')}"

# 이전 릴리스: REF에 포함된 v* 태그 중 이번 태그를 뺀 가장 높은 버전
PREV=$(git tag --list 'v*' --merged "$REF" --sort=-v:refname | grep -vx "$TAG" | head -n 1 || true)
if [ -n "$PREV" ]; then RANGE="$PREV..$REF"; else RANGE="$REF"; fi

# 커밋마다 "종류<TAB>설명<TAB>해시" 한 줄로 바꿔요.
CHANGES=$(git log --no-merges --format='%H%x1f%s%x1f%b%x1e' "$RANGE" | awk -v RS='\036' -F '\037' '
  {
    sub(/^\n+/, "", $1)
    if ($1 == "") next
    if (!match($2, /^[a-z]+(\([^)]*\))?!?: */)) next
    head = substr($2, 1, RLENGTH); desc = substr($2, RLENGTH + 1)
    type = head; sub(/[(!:].*/, "", type)
    if (head ~ /!/ || $3 ~ /(^|\n)BREAKING CHANGE/) kind = "breaking"
    else if (type == "feat" || type == "fix" || type == "perf") kind = type
    else next
    if (match($3, /(^|\n)Release-Note:[ \t]*[^\n]+/)) {
      note = substr($3, RSTART, RLENGTH)
      sub(/^\n?Release-Note:[ \t]*/, "", note); sub(/[ \t]+$/, "", note)
      if (note != "") desc = note
    }
    printf "%s\t%s\t%s\n", kind, desc, $1
  }')

section() {
  ITEMS=$(printf '%s\n' "$CHANGES" | awk -F '\t' -v k="$1" -v repo="$REPO" \
    '$1 == k { printf "- %s ([%s](https://github.com/%s/commit/%s))\n", $2, substr($3, 1, 7), repo, $3 }')
  [ -n "$ITEMS" ] && printf '## %s\n\n%s\n\n' "$2" "$ITEMS"
  return 0
}

section breaking "Breaking changes"
section feat "New features"
section fix "Bug fixes"
section perf "Performance"
if [ -z "$CHANGES" ]; then
  printf 'No user-facing changes.\n\n'
fi

cat <<EOF
## Install

Download \`DotDesk-$VERSION.zip\` below, unzip it, and move \`DotDesk.app\` to your \`Applications\` folder. Requires macOS 14 or later on an Apple Silicon Mac.

DotDesk is not notarized by Apple, so macOS blocks it the first time you open it. Allow it once in **System Settings → Privacy & Security → Open Anyway**, or run \`xattr -dr com.apple.quarantine /Applications/DotDesk.app\` in Terminal. See [First launch](https://github.com/$REPO#first-launch) for details.

EOF
if [ -n "$PREV" ]; then
  echo "**Full Changelog**: https://github.com/$REPO/compare/$PREV...$TAG"
else
  echo "**Full Changelog**: https://github.com/$REPO/commits/$TAG"
fi

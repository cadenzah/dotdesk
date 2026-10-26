# DotDesk

**English** | [한국어](README.ko.md)

A macOS app that shows the AI coding agents working on your Mac (Claude Code, Codex) as cute pixel-art characters.

- **Desktop pet** — Active agents wander along the bottom of your screen, then stop to type or read documents when they start working. A speech-bubble icon shows what they're doing right now (reading, searching, writing, running commands, browsing the web, calling teammates, planning…).
- **Office window** — In a small window in the corner of your screen, agents sit and work in areas grouped by project. Their monitors change with what they're doing, and subagents appear as teammates in front of the desk. After a while of inactivity, they head to the lounge sofa and fall asleep.
- **Answer permission requests** — Allow or deny from the pet's speech bubble without switching to the agent's window, or auto-approve (bypass). Even with auto-approve on, DotDesk can still ask you about dangerous commands like `rm -rf`.
- **Multiple accounts and organizations** — Reads the signed-in account for each `CLAUDE_CONFIG_DIR`/`CODEX_HOME` and tells them apart with desk flag colors and name tags.
- **Pick your characters** — Each new agent gets a random mix of hair and outfit. Or choose per agent or per project from 8 built-in pixel presets, [Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents) characters, or the Pokémon collected by [PokeTokenBar](https://github.com/chattymin/PokeTokenBar).

> The app's UI is currently in Korean. Labels below are quoted as they appear in the app, with an English translation in parentheses.

## Install

Download `DotDesk-<version>.zip` from [Releases](https://github.com/cadenzah/dotdesk/releases/latest), unzip it, and move `DotDesk.app` to your `Applications` folder. Requires macOS 14 or later on an Apple Silicon Mac.

### First launch

DotDesk is not signed with an Apple Developer certificate or notarized. So the first time you open it, macOS shows a warning like *"Apple could not verify 'DotDesk' is free of malware…"* and blocks it. Allow it once using one of the methods below, and it will open normally from then on.

**Option 1. Allow it in System Settings (macOS 15 and later)**

1. Double-click `DotDesk.app`. When the warning appears, click **Done** to close it.
2. Go to **System Settings → Privacy & Security** and scroll down to the **Security** section.
3. Click **Open Anyway** next to the message saying "DotDesk" was blocked. (It only shows for about an hour after the warning appeared.)
4. Confirm with your password or Touch ID, then click **Open Anyway** in the dialog that follows.

**Option 2. Open with right-click (macOS 14)**

In Finder, right-click (or Control-click) `DotDesk.app`, choose **Open**, then click **Open** again in the warning dialog. This no longer works as of macOS 15, so use Option 1 there.

**Option 3. Remove the quarantine flag in Terminal**

Removing the quarantine attribute (`com.apple.quarantine`) attached to downloaded files lets the app open without a warning. This also fixes the *"'DotDesk' is damaged and can't be opened"* message.

```sh
xattr -dr com.apple.quarantine /Applications/DotDesk.app
```

> This warning doesn't mean the app is dangerous — only that it comes from a developer Apple hasn't verified. If you're still concerned, build it from source as described below. Apps you build yourself don't get the quarantine flag, so they open without a warning.

## Build and run

Requires macOS 14 or later and Xcode (or a Swift 5.10+ toolchain).

```sh
./scripts/build-app.sh   # creates build/DotDesk.app (ad-hoc signed)
open build/DotDesk.app
```

On first launch, the **연동** (Integrations) tab in Settings opens. Click **훅 설치** (Install hooks) and DotDesk starts receiving events. This takes effect immediately, even for Claude Code sessions that are already open.

To try it without a real agent, turn on **데모 에이전트** (Demo agent) in the menu bar, or run `scripts/simulate-agent.sh`.

### Uninstall

1. In the Settings **연동** (Integrations) tab, click **훅 제거** (Remove hooks) for each config folder. Only entries containing `dotdesk-hook` are removed.
2. Quit the app and delete `DotDesk.app`, `~/.dotdesk` (relay script and token), and `~/Library/Application Support/DotDesk` (settings).

## How it works

```
Claude Code / Codex ──hook──▶ ~/.dotdesk/dotdesk-hook.sh ──HTTP(127.0.0.1)──▶ DotDesk
Codex session logs (~/.codex/sessions/**/rollout-*.jsonl) ───────tail───────▶ DotDesk
```

- **Claude Code**: Registers the relay script under `hooks` in `~/.claude/settings.json` (or each `CLAUDE_CONFIG_DIR`). On first install it backs up the file to `settings.json.dotdesk.backup`, and on removal it deletes only entries containing `dotdesk-hook`. The Code tab in the Claude desktop app uses the same settings, so it shows up too.
- **Codex**: Registers in `~/.codex/hooks.json` in the same format. Codex only runs new hooks once they're trusted, so approve them via `/hooks` in `codex`. Even without hooks, DotDesk reads the session log files to show activity (permission responses aren't available in that case).
- If DotDesk isn't running, the relay script exits immediately without printing anything, so your agents behave as usual.
- The event server listens only on `127.0.0.1` and accepts requests only with the token in `~/.dotdesk/token` (permissions 0600).

### Permission request modes

| Mode | Behavior |
|---|---|
| Answer in the agent's window (default) | Approve in the terminal/app as usual. The pet just raises its hand and waits |
| Answer from the pet's speech bubble | An allow/deny card appears on the pet and in the office. If there's no answer in time, it falls back to the normal flow |
| Auto-approve (bypass) | Allows without asking. Dangerous patterns (editable in Settings) are confirmed via speech bubble |

Besides the global setting, you can use a different mode per project, or switch a single session to "auto-approve this session". Claude Code's `deny` rules are still enforced even with auto-approve on.

### Account detection

- Claude: Reads the email and organization name from `oauthAccount` in `$CLAUDE_CONFIG_DIR/.claude.json` (default `~/.claude.json`).
- Codex: Reads only the email, plan, and organization name from the ID token in `$CODEX_HOME/auth.json`.
- Tokens themselves are never stored or sent anywhere. You can set names and flag colors in the **계정** (Accounts) tab in Settings.

## Assets and licenses

- DotDesk's code and its built-in pixel characters and furniture are hand-drawn and released under the [MIT License](LICENSE).
- **Pixel Agents assets** are not bundled with the app. DotDesk reads the characters and some furniture (desk, plant, sofa, clock) from the Pixel Agents extension folder installed in VS Code (or Cursor/Windsurf). The furniture can be turned off in Settings. Pixel Agents is MIT-licensed, and its characters are based on [JIK-A-4's MetroCity pack (CC0)](https://jik-a-4.itch.io/metrocity-free-topdown-character-pack).
- **Pokémon sprites** are the property of Nintendo/Game Freak/The Pokémon Company and are not bundled with the app. DotDesk reads the local files PokeTokenBar downloaded from [PokeAPI/sprites](https://github.com/PokeAPI/sprites) (`~/Library/Application Support/PokeTokenBar/sprites`) as-is. Please use them for personal, non-commercial purposes only.
- To use a different character sheet, point Settings to a folder containing `characters/char_N.png` in the Pixel Agents format (16×32 frames; rows: down/up/right; columns: walk1, stand, walk2, type1, type2, read1, read2).

DotDesk is an unofficial personal project. It is not affiliated with or endorsed by Anthropic, OpenAI, Nintendo, Game Freak, Creatures Inc., or The Pokémon Company. Claude, Codex, Pokémon, and other trademarks belong to their respective owners.

## Development

```
Sources/DotDesk/
  App/       App entry point, menu bar, dev renderer
  Core/      Event server, hook install, session state, account/project detection, Codex log watcher, settings
  Sprites/   Pixel canvas, built-in characters/furniture/icons, asset loader
  UI/        Pet, office simulation/renderer, settings screens
scripts/
  build-app.sh       Build the .app bundle
  bump-version.sh    Bump VERSION from commit prefixes
  make-icon.sh       Regenerate the icon
  simulate-agent.sh  Send fake Claude session events
```

- `swift build && .build/debug/DotDesk --render-preview /tmp/dotdesk-preview` — Saves character sheets, icons, a demo office, and settings screens as PNGs (handy for checking without Screen Recording permission).
- Releases: Run `scripts/bump-version.sh` to bump `VERSION` from the commits since the last release (`feat` → minor, `fix`/`perf` → patch, others → no bump; pass `patch`/`minor`/`major`/`X.Y.Z` to choose, `-n` to preview) and commit it. Then push to `main`; GitHub Actions (`.github/workflows/release.yml`) builds the app and uploads it as a zip to the `v<version>` Release. Versions that are already released are skipped.
- While the app is running, `curl -X POST -H "X-DotDesk-Token: $(cat ~/.dotdesk/token)" http://127.0.0.1:$(cat ~/.dotdesk/port)/debug/snapshot` saves the open windows and session state to `~/.dotdesk/snapshots/`.

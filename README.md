# DotDesk

**English** | [한국어](README.ko.md)

A macOS app that shows the AI coding agents working on your Mac (Claude Code, Codex) as cute pixel-art characters.

- **Desktop pet** — Active agents wander along the bottom of your screen, then stop to type or read documents when they start working. A speech-bubble icon shows what they're doing right now (reading, searching, writing, running commands, browsing the web, calling teammates, planning…). While resting, they take turns napping, sipping coffee, gaming, reading and stretching.
- **Office window** — In a small window in the corner of your screen, agents sit and work in areas grouped by project. Their monitors change with what they're doing, and subagents appear as teammates in front of the desk. After a while of inactivity, they take a break and pick something at random — a nap on the sofa, reading on the beanbag, coffee, watering the plant, gazing out the window, chatting in pairs by a window, stretching — and switch to something else after a bit. When a new session starts in the same project, a character whose session ended or is resting takes it on (so `/clear` keeps the same face). If the session they left gets busy again, a free colleague or a new character steps in.
- **Answer permission requests** — Allow or deny from the pet's speech bubble without switching to the agent's window, or auto-approve (bypass). Auto-approve turns off permission checks entirely, so read [the caveats](#before-turning-on-auto-approve) first.
- **Jump to the agent's window** — Click a pet, or double-click a character in the office, to bring forward the terminal or app that agent runs in. Terminal and iTerm2 switch to the exact tab (macOS asks once to let DotDesk control them), and tmux panes are selected too. In other apps such as VS Code, Cursor or Ghostty the app comes forward, and with Accessibility access (Settings → **Integrations**) DotDesk raises the window named after the project.
- **Sounds and notifications** — A sound (and optionally a macOS notification) when an agent waits for permission, asks a question, or finishes a task that took a while. Click the notification to jump to the agent's window, or allow/deny right from it when answering from the speech bubble. If you don't answer for a minute, the pet walks to the middle of the screen, waves and calls once more. It stays quiet while the agent's app is in front, and the menu bar has a quick **Alert sound** toggle. Set it up in the **Alerts** tab in Settings.
- **Reactions** — Characters shake with a dizzy bubble when a tool call fails, cheer with a sparkle when a test run passes (pytest, jest, `swift test`, `go test`, `npm test`…) and show a red ✕ when it fails, and throw confetti after finishing a task that took over five minutes.
- **Daily log** — Keeps a tally of each day: busy time (hour by hour and per project), requests, finished tasks, edited files, test results and tokens. A whiteboard on the office wall charts the last 12 hours, and once you're done for the day (after 6 pm, when every agent has been idle for 20 minutes) a summary card opens with the day and the past week. Open it any time from the menu bar (**Today's log…**) or by clicking the whiteboard.
- **Teamwork** — When an agent calls a subagent, the teammate walks up to the desk, they take turns talking, and the papers change hands; when the teammate is done they hand the results back before leaving. Messages between agents (`SendMessage`, Codex `send_input`) fly across the office as paper planes, and the pet says when work was handed off or brought back.
- **A growing office** — The office collects decorations as you work with your agents: a picture frame after the first finished task, string lights after three days, a floor lamp after 100 requests, a trophy shelf for passing tests (more trophies at 50 and 200), a cat on the window sill after ten long tasks, and a plaque at 100 hours. The pet announces each one, and Settings → **General** shows what's next.
- **Context gauge** — Reads each session's transcript to show how full its context window is, as a bar in the pet's speech bubble and under each name tag in the office, along with the tokens generated so far. Past 80% the character starts to sweat, and while the conversation is being compacted they pack papers into a box. Claude's window is guessed (1M when the model says `[1m]` or a session went past 200K, otherwise 200K) and can be set in the **General** tab; Codex reports its own.
- **Usage limits** — Under the context gauge, shows how much of your plan's 5-hour and weekly limits (and per-model weekly limits) that agent's account has used, and when each one resets. Providers report a percentage, not token counts. For Claude, connect the status line in the **Integrations** tab to get live values while a CLI session runs; otherwise DotDesk shows the last value Claude Code saved, with how old it is. Codex limits come from its session logs.
- **Multiple accounts and organizations** — Reads the signed-in account for each `CLAUDE_CONFIG_DIR`/`CODEX_HOME` and tells them apart with desk flag colors and name tags.
- **Pick your characters** — Each new agent gets a random mix of hair and outfit. Or choose per agent or per project from 8 built-in pixel presets, [Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents) characters, or the Pokémon collected by [PokeTokenBar](https://github.com/chattymin/PokeTokenBar). Claude agents also wear a hat for their model: a crown for Opus, a beret for Sonnet, a sprout for Haiku, and a wizard hat for Fable (can be turned off in the **General** tab).

> The app is in English and Korean. It follows your system language; to switch, use **Language** in Settings → **General**.

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

On first launch, the **Integrations** tab in Settings opens. Click **Install hooks** and DotDesk starts receiving events. This takes effect immediately, even for Claude Code sessions that are already open.

To try it without a real agent, turn on **Demo agent** in the menu bar, or run `scripts/simulate-agent.sh`.

### Uninstall

1. In the Settings **Integrations** tab, click **Remove hooks** for each config folder. Only entries containing `dotdesk-hook` are removed. If you connected the status line, click **Disconnect** too; your previous status line comes back.
2. Quit the app and delete `DotDesk.app`, `~/.dotdesk` (relay script and token), and `~/Library/Application Support/DotDesk` (settings).

## How it works

```
Claude Code / Codex ──hook──▶ ~/.dotdesk/dotdesk-hook.sh ──HTTP(127.0.0.1)──▶ DotDesk
Codex session logs (~/.codex/sessions/**/rollout-*.jsonl) ───────tail───────▶ DotDesk
```

- **Claude Code**: Registers the relay script under `hooks` in `~/.claude/settings.json` (or each `CLAUDE_CONFIG_DIR`). On first install it backs up the file to `settings.json.dotdesk.backup`, and on removal it deletes only entries containing `dotdesk-hook`. The Code tab in the Claude desktop app uses the same settings, so it shows up too.
- **Codex**: Registers in `~/.codex/hooks.json` in the same format. Codex only runs new hooks once they're trusted, so approve them via `/hooks` in `codex`. Even without hooks, DotDesk reads the session log files to show activity (permission responses aren't available in that case).
- **Claude app chats**: Chats in the Claude desktop app's Chat tab run on Anthropic's servers, so there are no hooks or log files. With Accessibility access, DotDesk reads the app's chat sidebar instead: a chat that is replying has a spinner on its row. Those chats appear in the office's "Claude chats" area. It only works while the app shows the Chat tab, and you can turn it off in the **Integrations** tab of Settings.
- **Status line (optional)**: Plan usage limits aren't in hook payloads, but they are in Claude Code's status line input. **Connect status line** wraps the `statusLine` command in `settings.json` with `~/.dotdesk/dotdesk-statusline.sh`, which forwards that input to DotDesk and then runs your previous status line command, so what you see doesn't change. **Disconnect** restores the previous setting (kept in `~/.dotdesk/statusline-backup.json`).
- If DotDesk isn't running, the relay script exits immediately without printing anything, so your agents behave as usual.
- The event server listens only on `127.0.0.1` and accepts requests only with the token in `~/.dotdesk/token` (permissions 0600).

### Permission request modes

| Mode | Behavior |
|---|---|
| Answer in the agent's window (default) | Approve in the terminal/app as usual. The pet just raises its hand and waits |
| Answer from the pet's speech bubble | An allow/deny card appears on the pet and in the office. If there's no answer in time, it falls back to the normal flow |
| Auto-approve (bypass) | Allows without asking. Only shell commands containing a dangerous pattern (editable in Settings) are confirmed via speech bubble |

Besides the global setting, you can use a different mode per project, or switch a single session to "auto-approve this session". Either way, DotDesk asks you to confirm once when you turn it on.

#### Before turning on auto-approve

Auto-approve is close to Claude Code's `--dangerously-skip-permissions`: everything that would have prompted you runs right away.

- File edits and deletions, shell commands, network requests, and MCP tools are all allowed without asking, including files outside the project (`~/.zshrc`, `.git/hooks`, `~/.claude/settings.json`, …).
- If the agent follows instructions hidden in a web page, issue, or file (prompt injection), those run without confirmation too.
- **Dangerous patterns are not a safety boundary.** They only ask when a shell command contains the exact text you listed, so variants like `rm -r -f` or `find . -delete`, and non-shell tools such as file writes, slip through.
- Use it only in projects you trust or in an isolated environment such as a container or VM. Block what must never happen with Claude Code's `permissions.deny` rules, which are still enforced with auto-approve on.

### Account detection

- Claude: Reads the email and organization name from `oauthAccount` in `$CLAUDE_CONFIG_DIR/.claude.json` (default `~/.claude.json`).
- Codex: Reads only the email, plan, and organization name from the ID token in `$CODEX_HOME/auth.json`.
- Tokens themselves are never stored or sent anywhere. You can set names and flag colors in the **Accounts** tab in Settings.

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

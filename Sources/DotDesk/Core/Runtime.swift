import Foundation

/// Files shared between the app and the hook relay script.
/// Kept in ~/.dotdesk (no spaces) so hook commands stay simple to quote.
enum Runtime {
    static let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dotdesk")
    static let hookScript = dir.appendingPathComponent("dotdesk-hook.sh")
    static let portFile = dir.appendingPathComponent("port")
    static let tokenFile = dir.appendingPathComponent("token")

    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DotDesk")
    }()

    private(set) static var token = ""

    static func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

        if let t = try? String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 32 {
            token = t
        } else {
            var bytes = [UInt8](repeating: 0, count: 24)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            token = bytes.map { String(format: "%02x", $0) }.joined()
            writePrivate(token, to: tokenFile)
        }

        if (try? String(contentsOf: hookScript, encoding: .utf8)) != hookScriptSource {
            try? hookScriptSource.write(to: hookScript, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScript.path)
    }

    static func writePort(_ port: UInt16) {
        writePrivate(String(port), to: portFile)
    }

    static func removePort() {
        try? FileManager.default.removeItem(at: portFile)
    }

    private static func writePrivate(_ s: String, to url: URL) {
        try? s.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Relay installed as the hook command for Claude Code and Codex.
    /// It must never get in the agent's way: when DotDesk isn't running it exits 0 with no output,
    /// which both agents treat as "no decision".
    static let hookScriptSource = #"""
    #!/bin/sh
    # DotDesk hook relay: forwards Claude Code / Codex hook events to the DotDesk app.
    # Usage: dotdesk-hook.sh <claude|codex> <HookEventName>
    provider="$1"
    event="$2"
    dir="$HOME/.dotdesk"
    if [ ! -r "$dir/port" ] || [ ! -r "$dir/token" ]; then
      cat >/dev/null
      exit 0
    fi
    port=$(cat "$dir/port")
    token=$(cat "$dir/token")
    case "$provider" in
      claude) conf="${CLAUDE_CONFIG_DIR:-}" ;;
      codex) conf="${CODEX_HOME:-}" ;;
      *) conf="" ;;
    esac
    # Permission requests wait for an answer from the pet; everything else is fire-and-forget.
    if [ "$event" = "PermissionRequest" ]; then maxtime=890; else maxtime=2; fi
    curl -s --connect-timeout 1 --max-time "$maxtime" \
      -H 'Expect:' -H 'Content-Type: application/json' \
      -H "X-DotDesk-Token: $token" \
      -H "X-DotDesk-Event: $event" \
      -H "X-DotDesk-Config-Dir: $conf" \
      -H "X-DotDesk-PID: $PPID" \
      -H "X-DotDesk-App: ${__CFBundleIdentifier:-}" \
      -H "X-DotDesk-Tmux: ${TMUX:-}" \
      -H "X-DotDesk-Tmux-Pane: ${TMUX_PANE:-}" \
      --data-binary @- "http://127.0.0.1:$port/hook/$provider" 2>/dev/null
    exit 0
    """#
}

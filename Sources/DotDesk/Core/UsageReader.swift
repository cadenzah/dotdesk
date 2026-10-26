import Foundation

/// Follows agent transcripts to learn how full each session's context is.
/// Claude Code writes `usage` on every assistant message; Codex rollouts carry `token_count` events.
/// New bytes are read off the main thread each time the session reports something.
@MainActor
final class UsageReader {
    static let shared = UsageReader()

    private struct Tail {
        let path: String
        var offset: UInt64 = 0
        var partial = Data()
        var usage = ContextUsage()
        /// Claude repeats a message's usage on each of its content blocks; count its output once.
        var lastMessageId: String?
        var lastMessageOutput = 0
        var reading = false
        var pending = false
    }

    private var tails: [String: Tail] = [:]
    private let queue = DispatchQueue(label: "DotDesk.UsageReader", qos: .utility)

    func follow(sessionKey: String, path: String) {
        var t = tails[sessionKey].flatMap { $0.path == path ? $0 : nil } ?? Tail(path: path)
        if t.reading {
            t.pending = true
            tails[sessionKey] = t
            return
        }
        t.reading = true
        tails[sessionKey] = t
        let start = t
        queue.async {
            var t = start
            Self.readNew(&t)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let current = self.tails[sessionKey], current.path == path else { return }
                    t.reading = false
                    t.pending = false
                    self.tails[sessionKey] = t
                    SessionStore.shared.setUsage(sessionKey, t.usage)
                    if current.pending { self.follow(sessionKey: sessionKey, path: path) }
                }
            }
        }
    }

    func forget(_ sessionKey: String) {
        tails[sessionKey] = nil
    }

    // MARK: Parsing

    nonisolated private static func readNew(_ t: inout Tail) {
        guard let h = FileHandle(forReadingAtPath: t.path) else { return }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd() else { return }
        if end < t.offset { t = Tail(path: t.path) }  // Rewritten from scratch.
        guard end > t.offset else { return }
        try? h.seek(toOffset: t.offset)
        guard let data = try? h.read(upToCount: Int(end - t.offset)) else { return }
        t.offset += UInt64(data.count)
        var buf = t.partial + data
        var start = buf.startIndex
        while let nl = buf[start...].firstIndex(of: 0x0A) {
            parse(buf[start..<nl], into: &t)
            start = buf.index(after: nl)
        }
        buf = Data(buf[start...])
        t.partial = buf
    }

    nonisolated private static let markers = ["\"usage\"", "compact_boundary", "token_count", "turn_context"].map { Data($0.utf8) }

    nonisolated private static func parse(_ line: Data, into t: inout Tail) {
        // Most lines are tool output; skip them before paying for JSON parsing.
        guard markers.contains(where: { line.range(of: $0) != nil }),
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        let type = obj["type"] as? String
        switch type {
        case "assistant":
            guard (obj["isSidechain"] as? Bool) != true, let m = obj["message"] as? [String: Any],
                  let u = m["usage"] as? [String: Any] else { return }
            let model = m["model"] as? String
            if model == "<synthetic>" { return }
            let prompt = int(u["input_tokens"]) + int(u["cache_creation_input_tokens"]) + int(u["cache_read_input_tokens"])
            let out = int(u["output_tokens"])
            t.usage.contextTokens = prompt + out
            t.usage.peakTokens = max(t.usage.peakTokens, prompt + out)
            if let model { t.usage.model = model }
            let id = m["id"] as? String
            if id != nil, id == t.lastMessageId {
                t.usage.outputTokens += max(0, out - t.lastMessageOutput)
                t.lastMessageOutput = max(out, t.lastMessageOutput)
            } else {
                t.usage.outputTokens += out
                t.lastMessageId = id
                t.lastMessageOutput = out
            }
        case "system" where obj["subtype"] as? String == "compact_boundary":
            t.usage.contextTokens = nil
        case "turn_context":
            if let model = (obj["payload"] as? [String: Any])?["model"] as? String { t.usage.model = model }
        case "event_msg":
            guard let p = obj["payload"] as? [String: Any], p["type"] as? String == "token_count",
                  let info = p["info"] as? [String: Any] else { return }
            if let last = info["last_token_usage"] as? [String: Any] {
                let used = int(last["total_tokens"])
                t.usage.contextTokens = used
                t.usage.peakTokens = max(t.usage.peakTokens, used)
            }
            if let total = info["total_token_usage"] as? [String: Any] { t.usage.outputTokens = int(total["output_tokens"]) }
            if let w = info["model_context_window"] as? Int, w > 0 { t.usage.reportedWindow = w }
        default:
            break
        }
    }

    nonisolated private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
}

/// "164k", "1.2M" — short token counts for labels.
func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 {
        let m = Double(n) / 1_000_000
        return m == m.rounded() ? "\(Int(m))M" : String(format: "%.1fM", m)
    }
    if n >= 1_000 { return "\(n / 1_000)k" }
    return "\(n)"
}

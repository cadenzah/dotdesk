import Foundation

/// Turns a tool call (Claude Code or Codex naming) into an activity and a short human-readable detail.
enum ActivityMapper {
    static func activity(forTool tool: String, input: [String: Any]) -> (Activity, String) {
        let lower = tool.lowercased()
        let a: Activity
        switch tool {
        case "Read", "NotebookRead", "Skill", "view_image", "read_file":
            a = .reading
        case "Grep", "Glob", "LS", "ToolSearch", "LSP", "list_dir", "grep_files":
            a = .searching
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch", "str_replace_editor":
            a = .typing
        case "Bash", "BashOutput", "KillShell", "KillBash", "PowerShell", "Monitor",
             "exec_command", "shell", "local_shell", "write_stdin", "exec", "unified_exec":
            a = .running
        case "WebFetch", "WebSearch", "web_search", "web_fetch":
            a = .browsing
        case "Task", "Agent", "spawn_agent", "SendMessage", "TeamCreate", "send_input", "wait":
            a = .delegating
        case "TodoWrite", "update_plan", "TaskCreate", "TaskUpdate", "EnterPlanMode":
            a = .planning
        case "AskUserQuestion", "ExitPlanMode", "request_user_input":
            a = .waitingInput
        default:
            if lower.contains("browser") || lower.contains("chrome") || lower.contains("fetch") {
                a = .browsing
            } else if lower.contains("search") || lower.contains("find") || lower.contains("query") {
                a = .searching
            } else if lower.contains("read") || lower.contains("get") || lower.contains("list") {
                a = .reading
            } else {
                a = .tool
            }
        }
        return (a, detail(tool: tool, input: input))
    }

    static func detail(tool: String, input: [String: Any]) -> String {
        func str(_ k: String) -> String? {
            (input[k] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func file(_ p: String) -> String { (p as NSString).lastPathComponent }

        if let p = str("file_path") ?? str("notebook_path") ?? str("path") { return file(p) }
        switch tool {
        case "Bash", "PowerShell", "exec_command", "shell", "local_shell", "unified_exec":
            if let d = str("description") { return truncate(d, 40) }
            if let c = str("command") ?? str("cmd") { return truncate(c, 40) }
            if let arr = input["command"] as? [String] { return truncate(arr.joined(separator: " "), 40) }
        case "apply_patch":
            let patch = str("command") ?? str("input") ?? ""
            for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
                if let r = patch.range(of: marker) {
                    let rest = patch[r.upperBound...]
                    return file(String(rest.prefix { !$0.isNewline }))
                }
            }
            return "패치"
        case "Grep", "Glob", "grep_files":
            if let p = str("pattern") { return truncate(p, 32) }
        case "WebFetch", "web_fetch":
            if let u = str("url"), let host = URL(string: u)?.host { return host }
        case "WebSearch", "web_search":
            if let q = str("query") { return truncate(q, 32) }
        case "Task", "Agent", "spawn_agent":
            if let d = str("description") { return truncate(d, 32) }
            if let t = str("subagent_type") { return t }
        case "Skill":
            if let s = str("skill") { return s }
        default:
            break
        }
        if tool.hasPrefix("mcp__") {
            let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
            if parts.count >= 3 { return "\(parts[1]) · \(parts.dropFirst(2).joined(separator: "_"))" }
        }
        return tool
    }

    /// Text shown on the permission card.
    static func permissionSummary(tool: String, input: [String: Any]) -> String {
        if let c = input["command"] as? String, tool != "apply_patch" { return truncate(c, 120) }
        if let p = input["file_path"] as? String { return "\(tool) · \(abbreviatePath(p))" }
        if let u = input["url"] as? String { return "\(tool) · \(u)" }
        return "\(tool) · \(detail(tool: tool, input: input))"
    }

    private static let testCommand = try! NSRegularExpression(pattern: #"""
        (?x)\b(pytest|jest|vitest|mocha|rspec|phpunit|ctest|tox|nox|playwright\s+test)\b
        | \b(npm|pnpm|yarn|bun)\s+(run\s+)?test\b
        | \b(go|cargo|swift|dotnet|mix|deno|flutter|dart|bundle\s+exec\s+rake)\s+test\b
        | \bmake\s+(test|check)\b | \bgradlew?\s+\S*test | \bmvn\s+(\S+\s+)*test\b
        | \bpython3?\s+-m\s+(pytest|unittest)\b | \bxcodebuild\b.*\btest\b
        """#)

    /// A shell command that runs a test suite.
    static func isTestCommand(_ cmd: String) -> Bool {
        testCommand.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)) != nil
    }

    private static let testFailure = try! NSRegularExpression(pattern: #"""
        (?x)\b[1-9]\d*\s+(failed|failing|failures?|errors?)\b | \bFAILED\b | \bFAIL\s | \bTests?\s+failed\b
        | \btest\s+result:\s+FAILED | \bExecuted\s+\d+\s+tests?,\s+with\s+[1-9]\d*\s+failures?
        """#)

    /// Test output that reports failures even though the command itself exited cleanly.
    static func outputShowsTestFailure(_ text: String) -> Bool {
        testFailure.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// stdout and stderr of a tool result, whatever shape the agent reports it in.
    static func outputText(_ response: Any?) -> String {
        if let s = response as? String { return s }
        if let d = response as? [String: Any] {
            return ["stdout", "stderr", "output", "error"].compactMap { d[$0] as? String }.joined(separator: "\n")
        }
        return ""
    }

    static func shellCommand(tool: String, input: [String: Any]) -> String? {
        if let c = input["command"] as? String { return c }
        if let c = input["cmd"] as? String { return c }
        if let arr = input["command"] as? [String] { return arr.joined(separator: " ") }
        return nil
    }
}

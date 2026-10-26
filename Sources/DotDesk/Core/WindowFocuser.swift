import AppKit
import ApplicationServices
import Darwin

/// Brings the terminal tab or app window an agent runs in to the front.
///
/// The hook relay reports its parent pid, so the process tree tells us the GUI app above the agent and
/// the agent's tty. Terminal and iTerm2 then select the exact tab by tty through AppleScript; inside
/// tmux the pane is selected first and the attached client leads to the terminal. Any other app is
/// activated, and with Accessibility access its window titled after the project is raised.
@MainActor
enum WindowFocuser {
    static func canFocus(_ s: AgentSession) -> Bool {
        s.origin != nil || (s.provider == .codex && s.cwd != nil)
    }

    /// Fills in what the reported pid leads to. Done when the hook arrives, because that pid may be a
    /// short-lived shell between the agent and the relay.
    static func resolve(_ o: inout SessionOrigin) {
        guard let pid = o.pid else { return }
        let found = walk(from: pid)
        o.tty = found.tty
        if let app = found.app {
            o.appPid = app.processIdentifier
            o.appBundleId = app.bundleIdentifier ?? o.appBundleId
        }
    }

    /// Returns false when there is nowhere to go (no origin, or the agent's app is gone).
    @discardableResult
    static func focus(_ s: AgentSession) -> Bool {
        let names = windowNames(for: s)
        guard let o = s.origin ?? codexOrigin(s) else { return false }

        if let pane = o.tmuxPane, let tmux = o.tmux {
            let fallback = runningApp(o)
            DispatchQueue.global(qos: .userInitiated).async {
                let client = Tmux.select(pane: pane, env: tmux)
                DispatchQueue.main.async {
                    if let client {
                        let found = walk(from: client)
                        if let app = found.app ?? fallback {
                            bringForward(app, tty: found.tty, names: names)
                            return
                        }
                    }
                    if let fallback { bringForward(fallback, tty: nil, names: names) } else { NSSound.beep() }
                }
            }
            return true
        }

        guard let app = runningApp(o) else { return false }
        bringForward(app, tty: o.tty, names: names)
        return true
    }

    /// Focuses the session or beeps when it can't.
    static func focusOrBeep(_ s: AgentSession) {
        if !focus(s) { NSSound.beep() }
    }

    // MARK: Apps

    private static func runningApp(_ o: SessionOrigin) -> NSRunningApplication? {
        if let pid = o.appPid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
           o.appBundleId == nil || app.bundleIdentifier == o.appBundleId {
            return app
        }
        guard let id = o.appBundleId else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first { !$0.isTerminated }
    }

    private static func bringForward(_ app: NSRunningApplication, tty: String?, names: [String]) {
        let script: String?
        switch app.bundleIdentifier {
        case "com.apple.Terminal": script = terminalScript
        case "com.googlecode.iterm2": script = itermScript
        default: script = nil
        }
        if let script, let tty {
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = runAppleScript(script, args: [tty])
                if !ok { DispatchQueue.main.async { activate(app, names: names) } }
            }
            return
        }
        activate(app, names: names)
    }

    private static func activate(_ app: NSRunningApplication, names: [String]) {
        raiseWindow(of: app.processIdentifier, matching: names)
        if app.isHidden { app.unhide() }
        NSApp.yieldActivation(to: app)
        if !app.activate(), let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    /// Raises the window whose title mentions the project. Needs Accessibility access; without it the
    /// app just comes forward with whatever window it had in front.
    private static func raiseWindow(of pid: pid_t, matching names: [String]) {
        guard AXIsProcessTrusted(), !names.isEmpty else { return }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for w in windows {
            var t: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success,
                  let title = t as? String, names.contains(where: { title.localizedCaseInsensitiveContains($0) }) else { continue }
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            return
        }
    }

    private static func windowNames(for s: AgentSession) -> [String] {
        var names: [String] = []
        if let cwd = s.cwd { names.append((cwd as NSString).lastPathComponent) }
        let project = SettingsStore.shared.projectName(s.projectKey)
        names.append(project)
        names.append((s.projectKey as NSString).lastPathComponent)
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && $0 != "/" && seen.insert($0).inserted }
    }

    // MARK: Processes

    /// Climbs from `pid` to the first regular GUI app, picking up the first controlling tty on the way.
    private static func walk(from pid: pid_t) -> (app: NSRunningApplication?, tty: String?) {
        var tty: String?
        var current = pid
        for _ in 0..<64 {
            guard current > 1, let info = procInfo(current) else { break }
            if tty == nil, info.tdev != -1, info.tdev != 0, let name = devname(info.tdev, S_IFCHR) {
                tty = "/dev/" + String(cString: name)
            }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return (app, tty)
            }
            current = info.ppid
        }
        return (nil, tty)
    }

    private static func procInfo(_ pid: pid_t) -> (ppid: pid_t, tdev: dev_t)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return (info.kp_eproc.e_ppid, info.kp_eproc.e_tdev)
    }

    /// Codex sessions seen only through rollout files have no hook origin; find a `codex` process
    /// running in the session's folder instead.
    private static func codexOrigin(_ s: AgentSession) -> SessionOrigin? {
        guard s.provider == .codex, let cwd = s.cwd else { return nil }
        let target = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        for pid in pids.prefix(Int(max(0, n))) where pid > 1 {
            var nameBuf = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0, String(cString: nameBuf) == "codex" else { continue }
            var vinfo = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vinfo, size) == size else { continue }
            let path = withUnsafeBytes(of: vinfo.pvi_cdir.vip_path) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            guard URL(fileURLWithPath: path).standardizedFileURL.path == target else { continue }
            var o = SessionOrigin(pid: pid)
            resolve(&o)
            return o
        }
        return nil
    }

    // MARK: AppleScript

    /// Runs through osascript off the main thread; the first run asks for Automation permission.
    nonisolated private static func runAppleScript(_ source: String, args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return p.terminationStatus == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }

    private static let terminalScript = """
    on run argv
      set target to item 1 of argv
      tell application id "com.apple.Terminal"
        repeat with w in windows
          repeat with t in tabs of w
            if tty of t is target then
              set miniaturized of w to false
              set selected of t to true
              set index of w to 1
              activate
              return "ok"
            end if
          end repeat
        end repeat
      end tell
      return "missing"
    end run
    """

    private static let itermScript = """
    on run argv
      set target to item 1 of argv
      tell application id "com.googlecode.iterm2"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if tty of s is target then
                select w
                select t
                select s
                activate
                return "ok"
              end if
            end repeat
          end repeat
        end repeat
      end tell
      return "missing"
    end run
    """
}

/// Selects a tmux pane and reports which client is showing it.
private enum Tmux {
    /// `env` is `$TMUX`: "<socket>,<server pid>,<session>". Returns the pid of the client now on the pane.
    static func select(pane: String, env: String) -> pid_t? {
        let parts = env.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let socket = parts.first, !socket.isEmpty, let binary = binary(serverPid: parts.count > 1 ? Int32(parts[1]) : nil) else { return nil }
        func run(_ args: [String]) -> String? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = ["-S", socket] + args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        }
        guard let session = run(["display-message", "-p", "-t", pane, "#{session_name}"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        // Prefer a client already on that session, otherwise the one used most recently.
        let clients = (run(["list-clients", "-F", "#{client_tty}\t#{client_pid}\t#{client_activity}\t#{client_session}"]) ?? "")
            .split(separator: "\n").compactMap { line -> (tty: String, pid: pid_t, activity: Int, session: String)? in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count == 4, let pid = Int32(f[1]) else { return nil }
                return (f[0], pid, Int(f[2]) ?? 0, f[3])
            }
        let client = clients.filter { $0.session == session }.max { $0.activity < $1.activity }
            ?? clients.max { $0.activity < $1.activity }
        if let c = client, c.session != session {
            _ = run(["switch-client", "-c", c.tty, "-t", session])
        }
        _ = run(["select-window", "-t", pane])
        _ = run(["select-pane", "-t", pane])
        return client?.pid
    }

    private static func binary(serverPid: pid_t?) -> String? {
        if let pid = serverPid {
            var buf = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
                let path = String(cString: buf)
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

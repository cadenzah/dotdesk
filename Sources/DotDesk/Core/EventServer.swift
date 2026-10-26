import Foundation
import Network

struct HookRequest {
    let provider: Provider
    let event: String
    /// CLAUDE_CONFIG_DIR / CODEX_HOME of the agent process, empty when unset.
    let configDir: String?
    /// Where the agent runs, so clicking its character can bring that window forward.
    let origin: SessionOrigin?
    let json: [String: Any]
}

/// Answers one hook call. Permission requests keep the HTTP connection open until `reply` is called.
final class HookResponder {
    private let lock = NSLock()
    private var done = false
    private let send: (Data) -> Void
    /// Called on the main queue if the hook process goes away before we answered (curl timeout, agent killed).
    var onAbandoned: (() -> Void)?

    init(send: @escaping (Data) -> Void) { self.send = send }

    func reply(_ body: Data = Data()) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { send(body) }
    }

    fileprivate func peerClosed() {
        lock.lock()
        let pending = !done
        done = true
        lock.unlock()
        if pending { DispatchQueue.main.async { self.onAbandoned?() } }
    }
}

/// Minimal HTTP/1.1 server on 127.0.0.1 that receives hook events from dotdesk-hook.sh.
final class EventServer {
    private let queue = DispatchQueue(label: "DotDesk.EventServer")
    private var listener: NWListener?
    private let token: String
    private(set) var port: UInt16 = 0
    var handler: ((HookRequest, HookResponder) -> Void)?
    /// Development aid: POST /debug/snapshot makes the app save PNGs of its own windows.
    var snapshotHandler: (() -> Void)?

    init(token: String) { self.token = token }

    func start(preferredPort: UInt16, onReady: @escaping (UInt16) -> Void) {
        listen(port: preferredPort, attemptsLeft: 30, onReady: onReady)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func listen(port: UInt16, attemptsLeft: Int, onReady: @escaping (UInt16) -> Void) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let retry = { [weak self] in
            guard attemptsLeft > 0 else { NSLog("DotDesk: no free port for event server"); return }
            self?.listen(port: port &+ 1, attemptsLeft: attemptsLeft - 1, onReady: onReady)
        }
        guard let l = try? NWListener(using: params) else { retry(); return }
        l.stateUpdateHandler = { [weak self, weak l] state in
            switch state {
            case .ready:
                self?.port = port
                DispatchQueue.main.async { onReady(port) }
            case .failed:
                l?.cancel()
                retry()
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener = l
        l.start(queue: queue)
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            switch HTTPRequest.parse(buf) {
            case .complete(let req):
                self.handle(req, on: c)
            case .invalid:
                c.cancel()
            case .incomplete where isComplete || error != nil || buf.count > HTTPRequest.maxSize:
                c.cancel()
            case .incomplete:
                self.receive(c, buffer: buf)
            }
        }
    }

    private func handle(_ req: HTTPRequest, on c: NWConnection) {
        func respond(_ status: String, _ body: Data) {
            var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            if body.isEmpty { head = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }
            c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
        }

        if req.method == "POST", req.path == "/debug/snapshot", req.headers["x-dotdesk-token"] == token {
            DispatchQueue.main.async { self.snapshotHandler?() }
            respond("200 OK", Data())
            return
        }
        guard req.method == "POST", req.path.hasPrefix("/hook/"),
              let provider = Provider(rawValue: String(req.path.dropFirst("/hook/".count))) else {
            respond("404 Not Found", Data()); return
        }
        guard req.headers["x-dotdesk-token"] == token else {
            respond("403 Forbidden", Data()); return
        }
        let json = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:]
        let event = req.headers["x-dotdesk-event"].flatMap { $0.isEmpty ? nil : $0 }
            ?? json["hook_event_name"] as? String ?? "Unknown"
        let configDir = req.headers["x-dotdesk-config-dir"].flatMap { $0.isEmpty ? nil : $0 }
        let origin = SessionOrigin(headers: req.headers)

        let responder = HookResponder { body in
            self.queue.async { respond("200 OK", body) }
        }
        // Watch for the client hanging up while a permission request is pending.
        c.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil { responder.peerClosed() }
        }
        let hook = HookRequest(provider: provider, event: event, configDir: configDir, origin: origin, json: json)
        DispatchQueue.main.async { [weak self] in
            if let h = self?.handler { h(hook, responder) } else { responder.reply() }
        }
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Upper bound for headers plus body; hook payloads are far smaller.
    static let maxSize = 64 << 20

    enum ParseResult {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    static func parse(_ data: Data) -> ParseResult {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = data.range(of: sep) else { return .incomplete }
        guard let head = String(data: data[data.startIndex..<r.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        // Digits only: a negative or malformed length would otherwise build an invalid range and crash.
        let lengthText = headers["content-length"] ?? "0"
        guard !lengthText.isEmpty, lengthText.allSatisfy(\.isASCII), lengthText.allSatisfy(\.isNumber),
              let length = Int(lengthText), length <= maxSize else { return .invalid }
        let bodyStart = r.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]
        return .complete(HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body)))
    }
}

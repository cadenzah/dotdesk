import Combine
import Foundation

/// Whether DotDesk's hooks are installed, so the UI can say so when nothing can reach the app.
@MainActor
final class IntegrationStatus: ObservableObject {
    static let shared = IntegrationStatus()

    @Published private(set) var claudeConnected = false
    @Published private(set) var codexConnected = false
    @Published var lastError: String?

    private let settings = SettingsStore.shared
    private var timer: Timer?

    private init() {
        refresh()
        // Hooks can also be added or removed by editing the settings files directly.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let claude = settings.s.claudeConfigDirs.contains {
            HookInstaller.isInstalled(at: HookInstaller.claudeSettingsURL(configDir: $0))
        }
        let codex = settings.s.codexHomes.contains {
            HookInstaller.isInstalled(at: HookInstaller.codexHooksURL(home: $0))
        }
        if claude != claudeConnected { claudeConnected = claude }
        if codex != codexConnected { codexConnected = codex }
    }

    func installClaude(configDir: String = "~/.claude") {
        do {
            try HookInstaller.installClaude(configDir: configDir)
            lastError = nil
        } catch {
            lastError = L("설치하지 못했어요: \(error.localizedDescription)", "Couldn't install: \(error.localizedDescription)")
        }
        refresh()
    }
}

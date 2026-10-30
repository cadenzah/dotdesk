import AppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
        DebugRender.run(to: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--hook-roundtrip"), i + 1 < args.count {
        // Installs then removes hooks in the given config dir (use a copy!) to check nothing else changes.
        let dir = args[i + 1]
        try! HookInstaller.installClaude(configDir: dir)
        print("installed:", HookInstaller.isInstalled(at: HookInstaller.claudeSettingsURL(configDir: dir)))
        try! FileManager.default.copyItem(atPath: dir + "/settings.json", toPath: dir + "/after-install.json")
        try! HookInstaller.uninstall(at: HookInstaller.claudeSettingsURL(configDir: dir))
        print("after uninstall:", HookInstaller.isInstalled(at: HookInstaller.claudeSettingsURL(configDir: dir)))
        exit(0)
    }
    if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
        DebugRender.renderIcon(to: args[i + 1])
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

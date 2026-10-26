import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, characters, projects, accounts, permissions, integrations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "일반"
        case .characters: return "캐릭터"
        case .projects: return "프로젝트"
        case .accounts: return "계정"
        case .permissions: return "권한"
        case .integrations: return "연동"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .characters: return "person.crop.square"
        case .projects: return "folder"
        case .accounts: return "person.2"
        case .permissions: return "hand.raised"
        case .integrations: return "link"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $nav.tab) {
            GeneralTab().tabItem { Label("일반", systemImage: "gearshape") }.tag(SettingsTab.general)
            CharactersTab().tabItem { Label("캐릭터", systemImage: "person.crop.square") }.tag(SettingsTab.characters)
            ProjectsTab().tabItem { Label("프로젝트", systemImage: "folder") }.tag(SettingsTab.projects)
            AccountsTab().tabItem { Label("계정", systemImage: "person.2") }.tag(SettingsTab.accounts)
            PermissionsTab().tabItem { Label("권한", systemImage: "hand.raised") }.tag(SettingsTab.permissions)
            IntegrationsTab().tabItem { Label("연동", systemImage: "link") }.tag(SettingsTab.integrations)
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("데스크톱 펫") {
                Toggle("펫 보이기", isOn: $settings.s.pet.enabled)
                Picker("움직임", selection: $settings.s.pet.mode) {
                    ForEach(PetMode.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("크기")
                    Slider(value: $settings.s.pet.scale, in: 2...5, step: 1)
                    Text("\(Int(settings.s.pet.scale))x").monospacedDigit().frame(width: 28)
                }
                Toggle("하는 일을 말풍선으로 알려주기", isOn: $settings.s.pet.showSpeech)
                Toggle("일하는 에이전트가 없으면 펫 숨기기", isOn: $settings.s.pet.hideWhenNoAgents)
            }
            Section("사무실 창") {
                Toggle("사무실 창 보이기", isOn: $settings.s.office.enabled)
                Toggle("항상 위에 띄우기", isOn: $settings.s.office.alwaysOnTop)
                Toggle("에이전트가 없으면 자동으로 숨기기", isOn: $settings.s.office.autoHide)
            }
            Section("시간") {
                Stepper("\(Int(settings.s.sleepAfterMinutes))분 동안 소식이 없으면 잠들기", value: $settings.s.sleepAfterMinutes, in: 1...60)
                Stepper("\(Int(settings.s.forgetAfterMinutes / 60))시간 동안 소식이 없으면 퇴근", value: $settings.s.forgetAfterMinutes, in: 60...1440, step: 60)
            }
            Section {
                Toggle("로그인할 때 DotDesk 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Characters

struct CharactersTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var sprites = SpriteLibrary.shared

    var body: some View {
        Form {
            Section {
                Picker("새 에이전트의 기본 캐릭터", selection: $settings.s.characterSource) {
                    ForEach(CharacterSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                if settings.s.characterSource == .pokemon {
                    Toggle("이로치(색이 다른) 포켓몬 우선", isOn: $settings.s.pokemonPreferShiny)
                }
                Text("에이전트마다 자동으로 겹치지 않게 골라요. 사무실에서 캐릭터를 우클릭하면 바꿀 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("에셋 위치") {
                PathRow(title: "Pixel Agents 에셋", detected: sprites.pixelAgentsDir?.path, value: $settings.s.pixelAgentsAssetsPath,
                        note: "VS Code의 Pixel Agents 확장 프로그램에서 자동으로 찾아요 (MIT, 캐릭터 원본은 CC0 MetroCity)")
                Toggle("Pixel Agents 가구도 사용", isOn: $settings.s.office.usePixelAgentsFurniture)
                PathRow(title: "PokeTokenBar 스프라이트", detected: sprites.pokemonDir?.path, value: $settings.s.pokemonSpritesPath,
                        note: "PokeTokenBar에서 모은 포켓몬만 쓸 수 있어요. 앱에 포함하지 않고 이 폴더에서 바로 읽어요.")
                Button("에셋 다시 불러오기") { sprites.reload() }
            }
            Section("미리보기") {
                CharacterGallery()
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.s.pixelAgentsAssetsPath) { sprites.reload() }
        .onChange(of: settings.s.pokemonSpritesPath) { sprites.reload() }
        .onChange(of: settings.s.office.usePixelAgentsFurniture) { sprites.reload() }
    }
}

struct PathRow: View {
    let title: String
    let detected: String?
    @Binding var value: String?
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(detected.map(abbreviatePath) ?? "찾지 못함")
                    .font(.caption).foregroundStyle(detected == nil ? .red : .secondary)
                    .lineLimit(1).truncationMode(.middle)
                Button("선택…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { value = url.path }
                }
                if value != nil { Button("자동") { value = nil } }
            }
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CharacterGallery: View {
    @ObservedObject private var sprites = SpriteLibrary.shared

    var body: some View {
        let groups = Dictionary(grouping: sprites.choices, by: \.group)
        ForEach(["기본 도트", "Pixel Agents", "포켓몬"], id: \.self) { g in
            if let list = groups[g], !list.isEmpty {
                VStack(alignment: .leading) {
                    Text(g).font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(list) { c in CharacterThumb(ref: c.ref).help(c.name) }
                        }
                    }
                }
            }
        }
    }
}

struct CharacterThumb: View {
    let ref: String
    var shirt = RGBA(0x4dabf7)
    var size: CGFloat = 40

    var body: some View {
        let skin = SpriteLibrary.shared.skin(for: ref, shirt: shirt)
        let (img, _) = skin.frame(facing: .down, pose: .stand, tick: 0)
        Image(decorative: img, scale: 1)
            .resizable()
            .interpolation(skin.isSheet ? .none : .medium)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size * (skin.isSheet ? 1.6 : 1))
    }
}

// MARK: Projects

struct ProjectsTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var store = SessionStore.shared

    var body: some View {
        let live = Set(store.sessions.values.map(\.projectKey))
        let keys = Set(settings.s.projects.keys).union(live).sorted { a, b in
            (live.contains(a) ? 0 : 1, settings.projectName(a)) < (live.contains(b) ? 0 : 1, settings.projectName(b))
        }
        Form {
            Section {
                Text("같은 프로젝트의 에이전트는 같은 색 옷을 입고 같은 구역에 앉아요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(keys, id: \.self) { key in
                Section {
                    ProjectRow(key: key, live: live.contains(key))
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ProjectRow: View {
    let key: String
    let live: Bool
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        let binding = Binding(get: { settings.s.projects[key] ?? ProjectSettings() }, set: { settings.s.projects[key] = $0 })
        HStack {
            Circle().fill(settings.projectColor(key).color).frame(width: 10, height: 10)
            TextField("이름", text: Binding(get: { binding.wrappedValue.name ?? "" }, set: { binding.wrappedValue.name = $0.isEmpty ? nil : $0 }),
                      prompt: Text(ProjectResolver.defaultName(for: key)))
            if live { Text("근무 중").font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Color.green.opacity(0.2))) }
        }
        Text(abbreviatePath(key)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        ColorPicker("색", selection: Binding(get: { settings.projectColor(key).color },
                                            set: { binding.wrappedValue.colorHex = RGBA($0).hex }), supportsOpacity: false)
        HStack {
            Text("기본 캐릭터")
            Spacer()
            if let ref = binding.wrappedValue.character {
                CharacterThumb(ref: ref, shirt: settings.projectColor(key), size: 18)
                Text(SpriteLibrary.shared.displayName(ref)).foregroundStyle(.secondary)
            }
            Menu(binding.wrappedValue.character == nil ? "자동" : "바꾸기") {
                Button("자동 (에이전트마다 다르게)") { binding.wrappedValue.character = nil }
                CharacterPickerMenu(current: binding.wrappedValue.character ?? "") { binding.wrappedValue.character = $0 }
            }
            .fixedSize()
        }
        Picker("권한 요청", selection: Binding(get: { binding.wrappedValue.permissionMode }, set: { binding.wrappedValue.permissionMode = $0 })) {
            Text("전체 설정 따르기 (\(settings.s.permissions.mode.label))").tag(PermissionMode?.none)
            ForEach(PermissionMode.allCases) { Text($0.label).tag(PermissionMode?.some($0)) }
        }
        HStack {
            Spacer()
            Button("목록에서 지우기", role: .destructive) { settings.s.projects.removeValue(forKey: key) }
                .disabled(live)
        }
    }
}

// MARK: Accounts

struct AccountsTab: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        let accounts = settings.s.accounts.compactMap { k, v in v.lastSeen.map { (k, $0) } }
            .sorted { ($0.1.provider.rawValue, $0.1.defaultLabel) < ($1.1.provider.rawValue, $1.1.defaultLabel) }
        Form {
            Section {
                Text("여러 계정·조직을 오가며 써도 구분할 수 있게, 계정마다 이름과 색을 정해요. 사무실 책상의 깃발 색이 계정 색이에요.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Claude는 CLAUDE_CONFIG_DIR별 .claude.json, Codex는 CODEX_HOME별 auth.json에서 로그인 정보(이메일·조직 이름)만 읽어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if accounts.isEmpty {
                Text("아직 본 계정이 없어요. 에이전트가 일을 시작하면 나타나요.").foregroundStyle(.secondary)
            }
            ForEach(accounts, id: \.0) { key, info in
                Section {
                    let binding = Binding(get: { settings.s.accounts[key] ?? AccountSettings() }, set: { settings.s.accounts[key] = $0 })
                    HStack {
                        Image(systemName: info.provider == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                        TextField("표시 이름", text: Binding(get: { binding.wrappedValue.label ?? "" },
                                                         set: { binding.wrappedValue.label = $0.isEmpty ? nil : $0 }),
                                  prompt: Text(info.defaultLabel))
                    }
                    Text([info.email, info.orgName, info.plan, abbreviatePath(info.configDir)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    ColorPicker("깃발 색", selection: Binding(get: { settings.accountColor(info).color },
                                                           set: { binding.wrappedValue.colorHex = RGBA($0).hex }), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Permissions

struct PermissionsTab: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Picker("권한 요청 처리", selection: $settings.s.permissions.mode) {
                    ForEach(PermissionMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                switch settings.s.permissions.mode {
                case .passthrough:
                    Text("지금처럼 에이전트 창에서 허락해요. 펫은 손을 들고 기다리는 모습만 보여줘요.")
                        .font(.caption).foregroundStyle(.secondary)
                case .bubble:
                    Text("펫 위에 허용/거부 카드가 떠요. 시간 안에 답하지 않으면 원래대로 에이전트 창에서 물어봐요.")
                        .font(.caption).foregroundStyle(.secondary)
                case .autoAllow:
                    Text("모든 권한 요청을 묻지 않고 허용해요. 파일 삭제나 배포 같은 위험한 작업도 그냥 실행될 수 있어요. Claude Code의 deny 규칙은 그래도 지켜져요.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            if settings.s.permissions.mode != .passthrough {
                Section {
                    Stepper("말풍선 대기 시간: \(Int(settings.s.permissions.bubbleTimeout))초",
                            value: $settings.s.permissions.bubbleTimeout, in: 15...600, step: 15)
                }
            }
            Section("자동 허용의 예외") {
                Toggle("위험해 보이는 셸 명령은 자동 허용 대신 말풍선으로 묻기", isOn: $settings.s.permissions.askForDangerous)
                TextEditor(text: Binding(get: { settings.s.permissions.dangerousPatterns.joined(separator: "\n") },
                                         set: { settings.s.permissions.dangerousPatterns = $0.components(separatedBy: "\n") }))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 110)
                Text("한 줄에 하나씩, 명령에 이 글자가 들어 있으면 물어봐요.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("프로젝트마다 다르게 하려면 프로젝트 탭에서 바꾸세요. 펫·사무실 메뉴에서 세션 하나만 자동 허용으로 바꿀 수도 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Integrations

struct IntegrationsTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var store = SessionStore.shared
    @State private var refresh = 0
    @State private var message: String?
    @State private var newClaudeDir = ""
    @State private var newCodexHome = ""

    var body: some View {
        Form {
            Section("Claude Code") {
                ForEach(settings.s.claudeConfigDirs, id: \.self) { dir in
                    HookRow(title: abbreviatePath(expandPath(dir)), url: HookInstaller.claudeSettingsURL(configDir: dir), refresh: refresh,
                            install: { try HookInstaller.installClaude(configDir: dir) },
                            remove: dir == "~/.claude" ? nil : { settings.s.claudeConfigDirs.removeAll { $0 == dir } },
                            message: $message, bump: { refresh += 1; IntegrationStatus.shared.refresh() })
                }
                HStack {
                    TextField("다른 CLAUDE_CONFIG_DIR 추가", text: $newClaudeDir, prompt: Text("~/.claude-work"))
                    Button("추가") {
                        let d = newClaudeDir.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty, !settings.s.claudeConfigDirs.contains(d) { settings.s.claudeConfigDirs.append(d) }
                        newClaudeDir = ""
                    }
                }
                Text("settings.json의 hooks에 DotDesk 항목만 추가해요(처음 한 번 .dotdesk.backup으로 백업). 데스크톱 앱의 Code 탭에도 적용되고, 이미 열려 있는 세션에도 바로 반영돼요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Codex") {
                ForEach(settings.s.codexHomes, id: \.self) { home in
                    HookRow(title: abbreviatePath(expandPath(home)), url: HookInstaller.codexHooksURL(home: home), refresh: refresh,
                            install: { try HookInstaller.installCodex(home: home) },
                            remove: home == "~/.codex" ? nil : { settings.s.codexHomes.removeAll { $0 == home } },
                            message: $message, bump: { refresh += 1; IntegrationStatus.shared.refresh() })
                }
                HStack {
                    TextField("다른 CODEX_HOME 추가", text: $newCodexHome, prompt: Text("~/.codex-work"))
                    Button("추가") {
                        let d = newCodexHome.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty, !settings.s.codexHomes.contains(d) { settings.s.codexHomes.append(d) }
                        newCodexHome = ""
                    }
                }
                Toggle("세션 기록 파일로도 지켜보기 (훅 없이 동작, 권한 응답은 불가)", isOn: $settings.s.watchCodexRollouts)
                Text("Codex는 새 훅을 처음 쓸 때 검토가 필요해요. 터미널에서 codex를 실행하고 /hooks에서 DotDesk 훅을 신뢰해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("테스트") {
                Toggle("데모 에이전트 출근시키기", isOn: Binding(get: { store.demoRunning }, set: { _ in store.toggleDemo() }))
                LabeledContent("이벤트 서버", value: AppDelegate.shared.map { "127.0.0.1:\($0.serverPort)" } ?? "-")
                LabeledContent("훅 스크립트", value: abbreviatePath(Runtime.hookScript.path))
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}

struct HookRow: View {
    let title: String
    let url: URL
    let refresh: Int
    let install: () throws -> Void
    let remove: (() -> Void)?
    @Binding var message: String?
    let bump: () -> Void

    var body: some View {
        let installed = HookInstaller.isInstalled(at: url)
        HStack {
            Image(systemName: installed ? "checkmark.circle.fill" : "circle").foregroundStyle(installed ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(title)
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Button("훅 제거") {
                    do { try HookInstaller.uninstall(at: url); message = nil } catch { message = error.localizedDescription }
                    bump()
                }
            } else {
                Button("훅 설치") {
                    do { try install(); message = nil } catch { message = error.localizedDescription }
                    bump()
                }
            }
            if let remove { Button(role: .destructive) { remove() } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
        }
        .id(refresh)
    }
}

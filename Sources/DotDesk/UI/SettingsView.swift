import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, characters, projects, accounts, alerts, permissions, integrations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return L("일반", "General")
        case .characters: return L("캐릭터", "Characters")
        case .projects: return L("프로젝트", "Projects")
        case .accounts: return L("계정", "Accounts")
        case .alerts: return L("알림", "Alerts")
        case .permissions: return L("권한", "Permissions")
        case .integrations: return L("연동", "Integrations")
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .characters: return "person.crop.square"
        case .projects: return "folder"
        case .accounts: return "person.2"
        case .alerts: return "bell"
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
            GeneralTab().tabItem { Label(L("일반", "General"), systemImage: "gearshape") }.tag(SettingsTab.general)
            CharactersTab().tabItem { Label(L("캐릭터", "Characters"), systemImage: "person.crop.square") }.tag(SettingsTab.characters)
            ProjectsTab().tabItem { Label(L("프로젝트", "Projects"), systemImage: "folder") }.tag(SettingsTab.projects)
            AccountsTab().tabItem { Label(L("계정", "Accounts"), systemImage: "person.2") }.tag(SettingsTab.accounts)
            AlertsTab().tabItem { Label(L("알림", "Alerts"), systemImage: "bell") }.tag(SettingsTab.alerts)
            PermissionsTab().tabItem { Label(L("권한", "Permissions"), systemImage: "hand.raised") }.tag(SettingsTab.permissions)
            IntegrationsTab().tabItem { Label(L("연동", "Integrations"), systemImage: "link") }.tag(SettingsTab.integrations)
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
            Section(L("데스크톱 펫", "Desktop pet")) {
                Toggle(L("펫 보이기", "Show pet"), isOn: $settings.s.pet.enabled)
                Picker(L("움직임", "Movement"), selection: $settings.s.pet.mode) {
                    ForEach(PetMode.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text(L("크기", "Size"))
                    Slider(value: $settings.s.pet.scale, in: 2...5, step: 1)
                    Text("\(Int(settings.s.pet.scale))x").monospacedDigit().frame(width: 28)
                }
                Toggle(L("하는 일을 말풍선으로 알려주기", "Show what it's doing in a speech bubble"), isOn: $settings.s.pet.showSpeech)
                Toggle(L("일하는 에이전트가 없으면 펫 숨기기", "Hide pet when no agents are working"), isOn: $settings.s.pet.hideWhenNoAgents)
            }
            Section(L("사무실 창", "Office window")) {
                Toggle(L("사무실 창 보이기", "Show office window"), isOn: $settings.s.office.enabled)
                Toggle(L("항상 위에 띄우기", "Keep on top"), isOn: $settings.s.office.alwaysOnTop)
                Toggle(L("에이전트가 없으면 자동으로 숨기기", "Hide automatically when there are no agents"), isOn: $settings.s.office.autoHide)
            }
            Section(L("사무실 꾸미기", "Office decorations")) {
                Toggle(L("모은 장식 보이기", "Show earned decorations"), isOn: $settings.s.office.showDecorations)
                DecorationList()
            }
            Section(L("컨텍스트", "Context")) {
                Toggle(L("컨텍스트·사용량 한도 게이지 보이기", "Show context and usage limit gauges"), isOn: $settings.s.showContextGauge)
                Picker(L("Claude 컨텍스트 크기", "Claude context size"), selection: $settings.s.contextWindow) {
                    Text(L("자동", "Auto")).tag(0)
                    Text("200K").tag(200_000)
                    Text("1M").tag(1_000_000)
                }
                Text(L("대화 기록 파일에서 마지막 응답의 토큰 수를 읽어요. 자동은 모델 이름에 [1m]이 있거나 20만 토큰을 넘긴 적이 있으면 1M으로 봐요. 80%를 넘으면 캐릭터가 땀을 흘리고, 대화를 정리하는 동안에는 상자에 짐을 싸요.",
                       "Reads the token count of the last response from the transcript file. Auto assumes 1M if the model name has [1m] or usage has ever passed 200K tokens. Above 80% the character sweats, and during compaction it packs boxes."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("하루 기록", "Daily log")) {
                Toggle(L("퇴근할 때 오늘의 기록 띄우기", "Show today's log when agents go home"), isOn: $settings.s.summary.autoShow)
                if settings.s.summary.autoShow {
                    Stepper(L("\(settings.s.summary.afterHour)시가 지나고", "After \(settings.s.summary.afterHour):00"), value: $settings.s.summary.afterHour, in: 12...23)
                    Stepper(L("모든 에이전트가 \(Int(settings.s.summary.quietMinutes))분 동안 쉬면", "When all agents have rested for \(Int(settings.s.summary.quietMinutes)) min"),
                            value: $settings.s.summary.quietMinutes, in: 5...120, step: 5)
                }
                Button(L("오늘의 기록 보기", "Show today's log")) { AppDelegate.shared?.showSummary() }
                Text(L("하루에 한 번만 떠요. 메뉴바나 사무실 화이트보드를 눌러도 볼 수 있어요.", "Shows once a day. You can also open it from the menu bar or the office whiteboard."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("시간", "Timing")) {
                Stepper(L("\(Int(settings.s.sleepAfterMinutes))분 동안 소식이 없으면 잠들기", "Fall asleep after \(Int(settings.s.sleepAfterMinutes)) min of quiet"), value: $settings.s.sleepAfterMinutes, in: 1...60)
                Stepper(L("\(Int(settings.s.forgetAfterMinutes / 60))시간 동안 소식이 없으면 퇴근", "Go home after \(Int(settings.s.forgetAfterMinutes / 60)) hr of quiet"), value: $settings.s.forgetAfterMinutes, in: 60...1440, step: 60)
            }
            Section {
                Picker(L("언어", "Language"), selection: $settings.s.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("로그인할 때 DotDesk 실행", "Launch DotDesk at login"), isOn: $launchAtLogin)
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
                Picker(L("새 에이전트의 기본 캐릭터", "Default character for new agents"), selection: $settings.s.characterSource) {
                    ForEach(CharacterSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                if settings.s.characterSource == .pokemon {
                    Toggle(L("이로치(색이 다른) 포켓몬 우선", "Prefer shiny Pokémon"), isOn: $settings.s.pokemonPreferShiny)
                }
                Text(settings.s.characterSource == .builtin
                     ? L("에이전트마다 머리·옷을 무작위로 조합해요. 사무실에서 캐릭터를 우클릭하면 바꿀 수 있어요.",
                         "Each agent gets a random mix of hair and clothes. Right-click a character in the office to change it.")
                     : L("에이전트마다 자동으로 겹치지 않게 골라요. 사무실에서 캐릭터를 우클릭하면 바꿀 수 있어요.",
                         "Each agent automatically gets a different one. Right-click a character in the office to change it."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("에셋 위치", "Asset locations")) {
                PathRow(title: L("Pixel Agents 에셋", "Pixel Agents assets"), detected: sprites.pixelAgentsDir?.path, value: $settings.s.pixelAgentsAssetsPath,
                        note: L("VS Code의 Pixel Agents 확장 프로그램에서 자동으로 찾아요 (MIT, 캐릭터 원본은 CC0 MetroCity)",
                                 "Found automatically in the Pixel Agents extension for VS Code (MIT; characters based on CC0 MetroCity)"))
                Toggle(L("Pixel Agents 가구도 사용", "Also use Pixel Agents furniture"), isOn: $settings.s.office.usePixelAgentsFurniture)
                PathRow(title: L("PokeTokenBar 스프라이트", "PokeTokenBar sprites"), detected: sprites.pokemonDir?.path, value: $settings.s.pokemonSpritesPath,
                        note: L("PokeTokenBar에서 모은 포켓몬만 쓸 수 있어요. 앱에 포함하지 않고 이 폴더에서 바로 읽어요.",
                                 "Only Pokémon you've collected in PokeTokenBar. They aren't bundled; DotDesk reads them from this folder."))
                Button(L("에셋 다시 불러오기", "Reload assets")) { sprites.reload() }
            }
            Section(L("미리보기", "Preview")) {
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
                Text(detected.map(abbreviatePath) ?? L("찾지 못함", "Not found"))
                    .font(.caption).foregroundStyle(detected == nil ? .red : .secondary)
                    .lineLimit(1).truncationMode(.middle)
                Button(L("선택…", "Choose…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { value = url.path }
                }
                if value != nil { Button(L("자동", "Auto")) { value = nil } }
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
                    Text(characterGroupLabel(g)).font(.caption).foregroundStyle(.secondary)
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
    var pose = Pose.stand
    var tick = 0

    var body: some View {
        let skin = SpriteLibrary.shared.skin(for: ref, shirt: shirt)
        let (img, flip) = skin.frame(facing: .down, pose: pose, tick: tick)
        Image(decorative: img, scale: 1)
            .resizable()
            .interpolation(skin.isSheet ? .none : .medium)
            .aspectRatio(contentMode: .fit)
            .scaleEffect(x: flip ? -1 : 1)
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
                Text(L("같은 프로젝트의 에이전트는 같은 색 옷을 입고 같은 구역에 앉아요.", "Agents on the same project wear the same color and sit in the same area."))
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
            TextField(L("이름", "Name"), text: Binding(get: { binding.wrappedValue.name ?? "" }, set: { binding.wrappedValue.name = $0.isEmpty ? nil : $0 }),
                      prompt: Text(ProjectResolver.defaultName(for: key)))
            if live { Text(L("근무 중", "Working")).font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Color.green.opacity(0.2))) }
        }
        Text(abbreviatePath(key)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        ColorPicker(L("색", "Color"), selection: Binding(get: { settings.projectColor(key).color },
                                            set: { binding.wrappedValue.colorHex = RGBA($0).hex }), supportsOpacity: false)
        HStack {
            Text(L("기본 캐릭터", "Default character"))
            Spacer()
            if let ref = binding.wrappedValue.character {
                CharacterThumb(ref: ref, shirt: settings.projectColor(key), size: 18)
                Text(SpriteLibrary.shared.displayName(ref)).foregroundStyle(.secondary)
            }
            Menu(binding.wrappedValue.character == nil ? L("자동", "Auto") : L("바꾸기", "Change")) {
                Button(L("자동 (에이전트마다 다르게)", "Auto (different for each agent)")) { binding.wrappedValue.character = nil }
                CharacterPickerMenu(current: binding.wrappedValue.character ?? "") { binding.wrappedValue.character = $0 }
            }
            .fixedSize()
        }
        Picker(L("권한 요청", "Permission requests"), selection: Binding(get: { binding.wrappedValue.permissionMode }, set: { mode in
            if mode == .autoAllow, binding.wrappedValue.permissionMode != .autoAllow,
               !AutoAllowWarning.confirm(L("‘\(settings.projectName(key))’ 프로젝트", "the project “\(settings.projectName(key))”")) { return }
            binding.wrappedValue.permissionMode = mode
        })) {
            Text(L("전체 설정 따르기 (\(settings.s.permissions.mode.label))", "Use global setting (\(settings.s.permissions.mode.label))")).tag(PermissionMode?.none)
            ForEach(PermissionMode.allCases) { Text($0.label).tag(PermissionMode?.some($0)) }
        }
        HStack {
            Spacer()
            Button(L("목록에서 지우기", "Remove from list"), role: .destructive) { settings.s.projects.removeValue(forKey: key) }
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
                Text(L("여러 계정·조직을 오가며 써도 구분할 수 있게, 계정마다 이름과 색을 정해요. 사무실 책상의 깃발 색이 계정 색이에요.",
                        "Give each account a name and color to tell them apart when you switch between accounts or organizations. The flag on each office desk shows the account color."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("Claude는 CLAUDE_CONFIG_DIR별 .claude.json, Codex는 CODEX_HOME별 auth.json에서 로그인 정보(이메일·조직 이름)만 읽어요.",
                        "Reads only sign-in info (email, organization name): from .claude.json in each CLAUDE_CONFIG_DIR for Claude, and auth.json in each CODEX_HOME for Codex."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if accounts.isEmpty {
                Text(L("아직 본 계정이 없어요. 에이전트가 일을 시작하면 나타나요.", "No accounts seen yet. They'll appear once an agent starts working.")).foregroundStyle(.secondary)
            }
            ForEach(accounts, id: \.0) { key, info in
                Section {
                    let binding = Binding(get: { settings.s.accounts[key] ?? AccountSettings() }, set: { settings.s.accounts[key] = $0 })
                    HStack {
                        Image(systemName: info.provider == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                        TextField(L("표시 이름", "Display name"), text: Binding(get: { binding.wrappedValue.label ?? "" },
                                                         set: { binding.wrappedValue.label = $0.isEmpty ? nil : $0 }),
                                  prompt: Text(info.defaultLabel))
                    }
                    Text([info.email, info.orgName, info.plan, abbreviatePath(info.configDir)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    ColorPicker(L("깃발 색", "Flag color"), selection: Binding(get: { settings.accountColor(info).color },
                                                           set: { binding.wrappedValue.colorHex = RGBA($0).hex }), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Permissions

/// Auto-allow approves everything without asking, so every way of turning it on goes through this confirmation.
@MainActor
enum AutoAllowWarning {
    static var risks: String {
        L("파일 수정·삭제, 셸 명령, 네트워크 요청, MCP 도구가 모두 묻지 않고 실행돼요. 에이전트가 웹페이지나 파일에 숨은 지시(프롬프트 인젝션)를 따르면 프로젝트 밖의 파일이나 셸·Claude Code 설정까지 바뀔 수 있어요.",
          "File edits and deletions, shell commands, network requests, and MCP tools all run without asking. If the agent follows instructions hidden in a web page or file (prompt injection), files outside the project, your shell, or Claude Code settings can be changed too.")
    }
    static var exceptionsCaveat: String {
        L("위험 명령 예외는 셸 명령에 적어 둔 글자가 그대로 들어 있을 때만 물어보는 편의 기능이에요. ‘rm -r -f’처럼 다르게 쓴 명령이나 파일 쓰기 같은 셸이 아닌 도구는 잡지 못하니 안전장치로 믿지 마세요.",
          "Dangerous patterns are a convenience, not a safety boundary. They only ask when a shell command contains the exact text you listed, so variants like ‘rm -r -f’ and non-shell tools such as file writes slip through.")
    }
    static var advice: String {
        L("믿을 수 있는 프로젝트나 격리된 환경에서만 쓰고, 꼭 막아야 할 작업은 Claude Code의 deny 규칙으로 막으세요. deny 규칙은 자동 허용이어도 지켜져요.",
          "Use it only in projects you trust or in an isolated environment. Block what must never happen with Claude Code's permissions.deny rules, which are still enforced with auto-approve on.")
    }

    /// Returns true when the user confirms. `scope` names what gets auto-allowed, e.g. "모든 프로젝트".
    static func confirm(_ scope: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L("\(scope)에서 자동 허용을 켤까요?", "Turn on auto-approve for \(scope)?")
        alert.informativeText = [risks, exceptionsCaveat, advice].joined(separator: "\n\n")
        alert.addButton(withTitle: L("취소", "Cancel"))
        let on = alert.addButton(withTitle: L("자동 허용 켜기", "Turn on auto-approve"))
        on.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}

// MARK: Alerts

struct AlertsTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var alerts = AlertCenter.shared

    var body: some View {
        Form {
            Section(L("언제 알릴까요", "When to alert")) {
                AlertRow(title: L("허락을 기다릴 때", "Waiting for permission"), isOn: $settings.s.alerts.onPermission, sound: $settings.s.alerts.permissionSound)
                AlertRow(title: L("질문이 있을 때", "Has a question"), isOn: $settings.s.alerts.onQuestion, sound: $settings.s.alerts.questionSound)
                AlertRow(title: L("오래 걸린 일을 마쳤을 때", "Finished a long task"), isOn: $settings.s.alerts.onDone, sound: $settings.s.alerts.doneSound)
                Stepper(L("\(Int(settings.s.alerts.doneAfterSeconds))초 넘게 일했을 때만 완료 알림", "Only for tasks longer than \(Int(settings.s.alerts.doneAfterSeconds)) sec"),
                        value: $settings.s.alerts.doneAfterSeconds, in: 0...600, step: 10)
                    .disabled(!settings.s.alerts.onDone)
            }
            Section(L("어떻게 알릴까요", "How to alert")) {
                Toggle(L("소리 내기", "Play sound"), isOn: $settings.s.alerts.sound)
                Toggle(L("macOS 알림 띄우기", "Show macOS notifications"), isOn: Binding(get: { settings.s.alerts.notify }, set: { on in
                    settings.s.alerts.notify = on
                    if on, alerts.notificationStatus == .notDetermined { alerts.requestAuthorization() }
                }))
                if settings.s.alerts.notify {
                    switch alerts.notificationStatus {
                    case .denied:
                        HStack {
                            Text(L("시스템 설정에서 DotDesk 알림이 꺼져 있어요", "DotDesk notifications are off in System Settings")).font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button(L("알림 설정 열기", "Open Notification Settings")) { AlertCenter.openNotificationSettings() }
                        }
                    case .notDetermined:
                        Button(L("알림 허용하기", "Allow notifications")) { alerts.requestAuthorization() }
                    default:
                        Text(L("알림을 누르면 그 에이전트의 창으로 가요. 펫 말풍선 응답 모드에서는 알림에서 바로 허용·거부할 수 있어요.",
                                "Click a notification to jump to that agent's window. In speech bubble mode, you can Allow or Deny right from the notification."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(L("에이전트 창을 보고 있을 때는 조용히", "Stay quiet while you're looking at the agent's window"), isOn: $settings.s.alerts.skipWhenWatching)
            }
            Section(L("오래 기다리면", "If it waits too long")) {
                Toggle(L("펫이 화면 가운데로 와서 손을 흔들고 한 번 더 알리기", "Pet comes to the center of the screen, waves, and alerts again"), isOn: Binding(
                    get: { settings.s.alerts.callAfterSeconds > 0 },
                    set: { settings.s.alerts.callAfterSeconds = $0 ? 60 : 0 }))
                if settings.s.alerts.callAfterSeconds > 0 {
                    Stepper(L("\(Int(settings.s.alerts.callAfterSeconds))초 동안 답이 없으면", "After \(Int(settings.s.alerts.callAfterSeconds)) sec without a reply"),
                            value: $settings.s.alerts.callAfterSeconds, in: 15...600, step: 15)
                }
                Text(L("펫이 제자리에 고정되어 있으면 그 자리에서 손을 흔들어요. 메뉴바에서 알림 소리를 바로 끌 수 있어요.",
                        "If the pet is pinned in place, it waves where it is. You can mute alert sounds from the menu bar."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { alerts.refreshStatus() }
    }
}

struct AlertRow: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var sound: String

    var body: some View {
        HStack {
            Toggle(title, isOn: $isOn)
            Spacer()
            Picker(L("소리", "Sound"), selection: $sound) {
                Text(L("소리 없음", "No sound")).tag("")
                ForEach(AlertCenter.sounds, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            .onChange(of: sound) { _, name in if !name.isEmpty { AlertCenter.play(name) } }
            Button { AlertCenter.play(sound) } label: { Image(systemName: "speaker.wave.2") }
                .buttonStyle(.borderless)
                .disabled(sound.isEmpty)
                .help(L("들어 보기", "Preview sound"))
        }
    }
}

struct PermissionsTab: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Picker(L("권한 요청 처리", "Handle permission requests"), selection: Binding(get: { settings.s.permissions.mode }, set: { mode in
                    if mode == .autoAllow, settings.s.permissions.mode != .autoAllow,
                       !AutoAllowWarning.confirm(L("모든 프로젝트", "all projects")) { return }
                    settings.s.permissions.mode = mode
                })) {
                    ForEach(PermissionMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                switch settings.s.permissions.mode {
                case .passthrough:
                    Text(L("지금처럼 에이전트 창에서 허락해요. 펫은 손을 들고 기다리는 모습만 보여줘요.", "Approve in the agent's window as usual. The pet just raises its hand and waits."))
                        .font(.caption).foregroundStyle(.secondary)
                case .bubble:
                    Text(L("펫 위에 허용/거부 카드가 떠요. 시간 안에 답하지 않으면 원래대로 에이전트 창에서 물어봐요.", "An Allow/Deny card appears above the pet. If you don't answer in time, the agent's window asks as usual."))
                        .font(.caption).foregroundStyle(.secondary)
                case .autoAllow:
                    Label(L("모든 권한 요청을 묻지 않고 허용해요. \(AutoAllowWarning.risks)", "Allows every permission request without asking. \(AutoAllowWarning.risks)"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Text(AutoAllowWarning.advice).font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.s.permissions.mode != .passthrough {
                Section {
                    Stepper(L("말풍선 대기 시간: \(Int(settings.s.permissions.bubbleTimeout))초", "Speech bubble timeout: \(Int(settings.s.permissions.bubbleTimeout)) sec"),
                            value: $settings.s.permissions.bubbleTimeout, in: 15...600, step: 15)
                }
            }
            Section(L("자동 허용의 예외", "Auto-approve exceptions")) {
                Toggle(L("위험해 보이는 셸 명령은 자동 허용 대신 말풍선으로 묻기", "Ask in a speech bubble for dangerous-looking shell commands"), isOn: $settings.s.permissions.askForDangerous)
                TextEditor(text: Binding(get: { settings.s.permissions.dangerousPatterns.joined(separator: "\n") },
                                         set: { settings.s.permissions.dangerousPatterns = $0.components(separatedBy: "\n") }))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 110)
                Text(L("한 줄에 하나씩, 셸 명령에 이 글자가 그대로 들어 있으면 물어봐요.", "One per line. Asks when a shell command contains this exact text.")).font(.caption).foregroundStyle(.secondary)
                Text(AutoAllowWarning.exceptionsCaveat).font(.caption).foregroundStyle(.orange)
            }
            Section {
                Text(L("프로젝트마다 다르게 하려면 프로젝트 탭에서 바꾸세요. 펫·사무실 메뉴에서 세션 하나만 자동 허용으로 바꿀 수도 있어요.",
                        "To set this per project, use the Projects tab. You can also auto-approve a single session from the pet or office menu."))
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
    @State private var axTrusted = AXIsProcessTrusted()

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
                    TextField(L("다른 CLAUDE_CONFIG_DIR 추가", "Add another CLAUDE_CONFIG_DIR"), text: $newClaudeDir, prompt: Text("~/.claude-work"))
                    Button(L("추가", "Add")) {
                        let d = newClaudeDir.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty, !settings.s.claudeConfigDirs.contains(d) { settings.s.claudeConfigDirs.append(d) }
                        newClaudeDir = ""
                    }
                }
                Text(L("settings.json의 hooks에 DotDesk 항목만 추가해요(처음 한 번 .dotdesk.backup으로 백업). 데스크톱 앱의 Code 탭에도 적용되고, 이미 열려 있는 세션에도 바로 반영돼요.",
                        "Adds only DotDesk entries to the hooks in settings.json (with a one-time .dotdesk.backup). Also applies to the Code tab in the desktop app, and takes effect right away in sessions already open."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("사용량 한도", "Usage limits")) {
                ForEach(settings.s.claudeConfigDirs, id: \.self) { dir in
                    StatusLineRow(configDir: dir, refresh: refresh, message: $message, bump: { refresh += 1 })
                }
                Text(L("요금제의 5시간·주간 한도를 펫 말풍선과 사무실 컨텍스트 게이지 아래에 보여줘요. Claude는 .claude.json에 남은 마지막 조회값을 읽고, 상태줄을 연결하면 CLI 세션이 도는 동안 실시간으로 받아요. 쓰던 상태줄은 그대로 보이고, 연결을 끊으면 원래대로 돌아가요. Codex는 세션 기록 파일에서 읽어요.",
                        "Shows your plan's 5-hour and weekly limits under the context gauge in the pet's bubble and the office. For Claude, DotDesk reads the last lookup saved in .claude.json; connect the status line to get live values while a CLI session runs. Your own status line still shows, and disconnecting restores it. Codex limits come from its session log files."))
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
                    TextField(L("다른 CODEX_HOME 추가", "Add another CODEX_HOME"), text: $newCodexHome, prompt: Text("~/.codex-work"))
                    Button(L("추가", "Add")) {
                        let d = newCodexHome.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty, !settings.s.codexHomes.contains(d) { settings.s.codexHomes.append(d) }
                        newCodexHome = ""
                    }
                }
                Toggle(L("세션 기록 파일로도 지켜보기 (훅 없이 동작, 권한 응답은 불가)", "Also watch session log files (works without hooks; can't answer permission requests)"), isOn: $settings.s.watchCodexRollouts)
                Text(L("Codex는 새 훅을 처음 쓸 때 검토가 필요해요. 터미널에서 codex를 실행하고 /hooks에서 DotDesk 훅을 신뢰해 주세요.",
                        "Codex asks you to review new hooks before first use. Run codex in a terminal and trust the DotDesk hooks in /hooks."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Claude 앱 채팅", "Claude app chats")) {
                Toggle(L("Claude 데스크톱 앱의 채팅도 보여주기", "Also show chats in the Claude desktop app"), isOn: $settings.s.watchClaudeAppChats)
                if !axTrusted {
                    Button(L("손쉬운 사용 권한 주기", "Grant Accessibility access")) {
                        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                    }
                }
                Text(L("채팅은 Anthropic 서버에서 돌아서 훅이 없어요. 대신 손쉬운 사용 권한으로 Claude 앱 사이드바를 읽어, 답하는 중인 채팅을 사무실 'Claude 채팅' 구역에 보여줘요. 앱이 채팅 화면일 때만 보이고, Code 탭을 보는 동안에는 상태가 바뀌지 않아요.",
                        "Chats run on Anthropic's servers, so they have no hooks. Instead DotDesk reads the Claude app's sidebar with Accessibility access and shows chats that are replying in the office's \"Claude chats\" area. This only works while the app shows the Chat tab; status doesn't change while you're in the Code tab."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("에이전트 창으로 가기", "Jump to agent window")) {
                LabeledContent("Terminal · iTerm2") {
                    Text(L("탭까지 정확히 찾아요", "Finds the exact tab")).foregroundStyle(.secondary)
                }
                LabeledContent(L("그 밖의 앱 (VS Code, Cursor, Ghostty…)", "Other apps (VS Code, Cursor, Ghostty…)")) {
                    if axTrusted {
                        Label(L("프로젝트 창을 찾아요", "Finds the project window"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(L("손쉬운 사용 권한 주기", "Grant Accessibility access")) {
                            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                        }
                    }
                }
                Text(L("펫을 클릭하거나 사무실에서 캐릭터를 더블클릭하면 그 에이전트가 일하는 창으로 가요. Terminal과 iTerm2는 처음 한 번 제어 권한을 물어봐요. 다른 앱은 앱만 앞으로 가져오고, 손쉬운 사용 권한이 있으면 프로젝트 이름이 제목에 든 창을 골라요. tmux 안에서 돌면 그 창과 패널도 골라 줘요.",
                        "Click the pet or double-click a character in the office to jump to the window that agent is working in. Terminal and iTerm2 ask for permission to control them the first time. Other apps are just brought to the front, and with Accessibility access DotDesk picks the window whose title contains the project name. Inside tmux, it also selects the right window and pane."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in axTrusted = AXIsProcessTrusted() }
            Section(L("테스트", "Testing")) {
                Toggle(L("데모 에이전트 출근시키기", "Bring in a demo agent"), isOn: Binding(get: { store.demoRunning }, set: { _ in store.toggleDemo() }))
                LabeledContent(L("이벤트 서버", "Event server"), value: AppDelegate.shared.map { "127.0.0.1:\($0.serverPort)" } ?? "-")
                LabeledContent(L("훅 스크립트", "Hook script"), value: abbreviatePath(Runtime.hookScript.path))
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
                Button(L("훅 제거", "Remove hooks")) {
                    do { try HookInstaller.uninstall(at: url); message = nil } catch { message = error.localizedDescription }
                    bump()
                }
            } else {
                Button(L("훅 설치", "Install hooks")) {
                    do { try install(); message = nil } catch { message = error.localizedDescription }
                    bump()
                }
            }
            if let remove { Button(role: .destructive) { remove() } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
        }
        .id(refresh)
    }
}

/// Connects Claude Code's status line, whose input carries live plan usage limits.
struct StatusLineRow: View {
    let configDir: String
    let refresh: Int
    @Binding var message: String?
    let bump: () -> Void

    var body: some View {
        let installed = StatusLineInstaller.isInstalled(configDir: configDir)
        HStack {
            Image(systemName: installed ? "checkmark.circle.fill" : "circle").foregroundStyle(installed ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(abbreviatePath(expandPath(configDir)))
                Text(L("상태줄(statusLine)", "Status line")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(installed ? L("연결 끊기", "Disconnect") : L("상태줄 연결", "Connect status line")) {
                do {
                    if installed { try StatusLineInstaller.uninstall(configDir: configDir) } else { try StatusLineInstaller.install(configDir: configDir) }
                    message = nil
                } catch { message = error.localizedDescription }
                bump()
            }
        }
        .id(refresh)
    }
}

/// Each office decoration with how close it is to being earned.
struct DecorationList: View {
    @ObservedObject private var stats = DailyStats.shared

    var body: some View {
        let t = stats.totals
        ForEach(Decoration.allCases) { d in
            let got = stats.isUnlocked(d)
            let (cur, target) = d.progress(t)
            HStack(spacing: 8) {
                Image(systemName: got ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(got ? Color.green : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.name).foregroundStyle(got ? .primary : .secondary)
                    Text(d.goal).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if got, let date = stats.unlocked[d.rawValue] {
                    Text(date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView(value: min(cur, target), total: target).frame(width: 70)
                    Text("\(Int(cur))/\(Int(target))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

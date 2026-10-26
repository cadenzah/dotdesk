import AppKit
import SwiftUI

/// "에이전트 꾸미기" window: rename an agent and pick its character with a live preview.
struct AgentEditView: View {
    let title: String
    let subtitle: String
    let namePlaceholder: String
    /// What "자동" resolves to right now (project default or the session's auto pick).
    let autoRef: String
    let shirt: RGBA
    let save: (_ name: String, _ ref: String?) -> Void
    let cancel: () -> Void

    @State private var name: String
    @State private var ref: String?
    @State private var tab: String
    @FocusState private var nameFocused: Bool
    @ObservedObject private var sprites = SpriteLibrary.shared

    static let groups = ["기본 도트", "Pixel Agents", "포켓몬"]

    init(title: String, subtitle: String, name: String, namePlaceholder: String, ref: String?, autoRef: String, shirt: RGBA,
         save: @escaping (String, String?) -> Void, cancel: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.namePlaceholder = namePlaceholder
        self.autoRef = autoRef
        self.shirt = shirt
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: name)
        _ref = State(initialValue: ref)
        _tab = State(initialValue: SpriteLibrary.shared.group(of: ref ?? autoRef) ?? Self.groups[0])
    }

    var body: some View {
        let shown = ref ?? autoRef
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                PreviewStage(ref: shown, shirt: shirt)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.bold()).lineLimit(1)
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("이름").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        TextField(namePlaceholder, text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .onSubmit { save(name, ref) }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("캐릭터").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(sprites.displayName(shown)).font(.body.weight(.semibold)).lineLimit(1)
                            if ref == nil {
                                Text("자동").font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Button("자동으로 되돌리기") { ref = nil }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                let available = Self.groups.filter { g in sprites.choices.contains { $0.group == g } }
                if available.count > 1 {
                    Picker("", selection: $tab) {
                        ForEach(available, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68, maximum: 80), spacing: 8)], spacing: 8) {
                        ForEach(sprites.choices.filter { $0.group == tab }) { c in
                            CharacterTile(ref: c.ref, name: c.name, shirt: shirt, picked: ref == c.ref) { ref = c.ref }
                        }
                    }
                    .padding(10)
                }
                .frame(height: 236)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
            }
            .padding(20)

            HStack {
                Spacer()
                Button("취소", action: cancel).keyboardShortcut(.cancelAction)
                Button("저장") { save(name, ref) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 460)
        .onAppear { nameFocused = true }
    }
}

/// A little office corner where the chosen character cycles through its poses.
private struct PreviewStage: View {
    let ref: String
    let shirt: RGBA

    private static let poses: [(Pose, String)] = [(.walk, "걷기"), (.type, "타이핑"), (.read, "읽기")]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate * 8)
            let (pose, label) = Self.poses[(tick / 16) % Self.poses.count]
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    OfficeArt.wall.color
                    OfficeArt.wallTrim.color.frame(height: 3)
                    OfficeArt.floorA.color.frame(height: 44)
                }
                Ellipse().fill(.black.opacity(0.12)).frame(width: 46, height: 10).padding(.bottom, 22)
                CharacterThumb(ref: ref, shirt: shirt, size: 70, pose: pose, tick: tick)
                    .padding(.bottom, 26)
                Text(label).font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)
            }
            .frame(width: 132, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        }
    }
}

private struct CharacterTile: View {
    let ref: String
    let name: String
    let shirt: RGBA
    let picked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                CharacterThumb(ref: ref, shirt: shirt, size: 32)
                    .frame(height: 52)
                Text(name).font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
            }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(picked ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(picked ? Color.accentColor : Color.primary.opacity(hovering ? 0.18 : 0.06), lineWidth: picked ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
    }
}

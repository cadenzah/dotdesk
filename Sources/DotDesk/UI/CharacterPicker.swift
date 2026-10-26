import AppKit
import SwiftUI

/// Selection state for the agent edit dialog. `ref == nil` means automatic.
@MainActor
final class CharacterSelection: ObservableObject {
    @Published var ref: String?
    @Published private(set) var tick = 0
    private var timer: Timer?

    init(_ ref: String?) { self.ref = ref }

    /// Runs in `.common` modes so the preview keeps moving inside a modal alert.
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick += 1 }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Large animated preview of the chosen character plus a thumbnail grid to pick from.
struct CharacterPicker: View {
    @ObservedObject var selection: CharacterSelection
    /// What "자동" resolves to right now (project default or the session's auto pick).
    let autoRef: String
    let shirt: RGBA
    @ObservedObject private var sprites = SpriteLibrary.shared

    private static let poses: [(Pose, String)] = [(.walk, "걷기"), (.type, "타이핑"), (.read, "읽기")]

    var body: some View {
        let ref = selection.ref ?? autoRef
        let phase = (selection.tick / 16) % Self.poses.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CharacterThumb(ref: ref, shirt: shirt, size: 64, pose: Self.poses[phase].0, tick: selection.tick)
                    .frame(width: 84, height: 108)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sprites.displayName(ref)).font(.headline)
                    Text(selection.ref == nil ? "자동" : group(of: ref)).font(.caption).foregroundStyle(.secondary)
                    Text(Self.poses[phase].1).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    grid([(nil, "자동")])
                    let groups = Dictionary(grouping: sprites.choices, by: \.group)
                    ForEach(["기본 도트", "Pixel Agents", "포켓몬"], id: \.self) { g in
                        if let list = groups[g], !list.isEmpty {
                            Text(g).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                            grid(list.map { ($0.ref, $0.name) })
                        }
                    }
                }
                .padding(4)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        }
        .frame(width: 320)
        .onAppear { selection.start() }
        .onDisappear { selection.stop() }
    }

    private func grid(_ items: [(ref: String?, name: String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
            ForEach(items, id: \.ref) { item in
                let picked = selection.ref == item.ref
                Button { selection.ref = item.ref } label: {
                    CharacterThumb(ref: item.ref ?? autoRef, shirt: shirt, size: 30)
                        .frame(width: 44, height: 52)
                        .overlay(alignment: .bottomTrailing) {
                            if item.ref == nil {
                                Text("자동").font(.system(size: 8, weight: .bold)).padding(.horizontal, 3)
                                    .background(Capsule().fill(.background))
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(picked ? Color.accentColor.opacity(0.18) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(picked ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.name)
            }
        }
    }

    private func group(of ref: String) -> String {
        let base = ref.hasSuffix(":shiny") ? String(ref.dropLast(":shiny".count)) : ref
        return sprites.choices.first { $0.ref == base }?.group ?? ""
    }
}

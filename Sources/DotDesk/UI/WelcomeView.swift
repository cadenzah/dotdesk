import SwiftUI

/// First-run window: explains what connecting changes and installs the Claude Code hooks in one click.
struct WelcomeView: View {
    @ObservedObject private var status = IntegrationStatus.shared
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CharacterThumb(ref: "builtin:0", shirt: RGBA(0xff6b6b), size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DotDesk에 오신 걸 환영해요").font(.title2.bold())
                    Text("에이전트가 일하는 모습을 도트 캐릭터로 보여줘요.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("에이전트와 연결하기").font(.headline)
                Text("Claude Code가 일할 때마다 DotDesk에 알려 주도록 훅(hook)을 설치해요. 연결하기 전에는 캐릭터가 계속 쉬기만 해요.")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    point("doc.badge.plus", "~/.claude/settings.json의 hooks에 DotDesk 항목만 추가해요.")
                    point("checkmark.shield", "기존 설정과 다른 훅은 그대로 두고, 처음 한 번 settings.json.dotdesk.backup으로 백업해요. 파일 안 항목 순서는 정렬될 수 있어요.")
                    point("bolt", "터미널의 Claude Code와 Claude 데스크톱 앱의 Code 탭에, 이미 열려 있는 세션까지 바로 적용돼요.")
                    point("moon.zzz", "DotDesk가 꺼져 있으면 훅은 아무것도 하지 않고 바로 끝나서, 에이전트 작업에 영향을 주지 않아요.")
                    point("arrow.uturn.backward", "설정 > 연동에서 언제든 제거할 수 있어요.")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            if status.claudeConnected {
                Label("연결됐어요! 에이전트에게 일을 시키면 사무실에 출근해요.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let e = status.lastError {
                Text(e).foregroundStyle(.red).font(.callout)
            }
            Text("Codex는 설정 > 연동에서 따로 연결할 수 있어요. 연결하지 않아도 세션 기록 파일로 활동을 보여줘요.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("설정 열기") { AppDelegate.shared?.showSettings(tab: .integrations) }
                Spacer()
                if status.claudeConnected {
                    Button("시작하기") { close() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("나중에") { close() }
                    Button("Claude Code 연결하기") { status.installClaude() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

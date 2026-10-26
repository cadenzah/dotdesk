import SwiftUI

/// The day's summary card: headline numbers, time per project and hour, who worked, and the past week.
struct DailySummaryView: View {
    @ObservedObject private var stats = DailyStats.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selected: String?

    var body: some View {
        let days = stats.recentDays
        let d = days.first { $0.day == selected } ?? stats.today
        VStack(alignment: .leading, spacing: 14) {
            header(d)
            if d.isEmpty {
                Text("이날은 일한 기록이 없어요").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                tiles(d)
                if !d.projectSeconds.isEmpty { projects(d) }
                hours(d)
                if !d.crew.isEmpty { crew(d) }
            }
            Divider()
            week(days)
        }
        .padding(20)
        .frame(width: 460)
    }

    private func header(_ d: DayStats) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.day == stats.today.day ? "오늘의 기록" : "그날의 기록").font(.title2.bold())
                Text(Self.dateLabel(d.day)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !d.isEmpty { Text(Self.cheer(d)).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func tiles(_ d: DayStats) -> some View {
        let tests = d.testsPassed + d.testsFailed == 0 ? "-" : "\(d.testsPassed) / \(d.testsFailed)"
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "일한 시간", value: formatDuration(d.busySeconds),
                         note: d.agentSeconds > d.busySeconds + 60 ? "에이전트 합계 \(formatDuration(d.agentSeconds))" : nil)
                StatTile(title: "요청", value: "\(d.prompts)", note: "끝낸 작업 \(d.turnsDone)")
                StatTile(title: "고친 파일", value: "\(d.files.count)", note: "도구 \(d.toolCalls)번")
            }
            GridRow {
                StatTile(title: "테스트 통과 / 실패", value: tests, note: nil)
                StatTile(title: "긴 작업", value: "\(d.longTasks)", note: "5분 넘게 걸린 일")
                StatTile(title: "출력 토큰", value: d.outputTokens > 0 ? formatTokens(d.outputTokens) : "-", note: nil)
            }
        }
    }

    private func projects(_ d: DayStats) -> some View {
        let rows = d.projectSeconds.sorted { $0.value > $1.value }.prefix(5)
        let top = rows.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            Text("프로젝트별 시간").font(.headline)
            ForEach(Array(rows), id: \.key) { key, secs in
                HStack(spacing: 8) {
                    Text(settings.projectName(key)).font(.caption).lineLimit(1).frame(width: 110, alignment: .leading)
                    GeometryReader { g in
                        UnevenRoundedRectangle(bottomLeadingRadius: 0, bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(settings.projectColor(key).color)
                            .frame(width: max(4, g.size.width * secs / top))
                    }
                    .frame(height: 10)
                    Text(formatDuration(secs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .trailing)
                }
                .help("\(settings.projectName(key)) · 에이전트 \(formatDuration(secs))")
            }
        }
    }

    private func hours(_ d: DayStats) -> some View {
        let first = d.busyByHour.firstIndex { $0 > 0 } ?? 9
        let last = d.busyByHour.lastIndex { $0 > 0 } ?? 18
        let range = Array(min(first, 9)...max(last, min(first, 9) + 8))
        return VStack(alignment: .leading, spacing: 6) {
            Text("시간대별").font(.headline)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(range, id: \.self) { h in
                    let v = min(1, d.busyByHour[h] / 3600)
                    VStack(spacing: 3) {
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                            .fill(v > 0 ? Color.accentColor : Color.primary.opacity(0.08))
                            .frame(height: max(2, 44 * v))
                        Text(h % 3 == 0 ? "\(h)" : " ").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(h)시 · \(formatDuration(d.busyByHour[h]))")
                }
            }
            .frame(height: 60, alignment: .bottom)
        }
    }

    private func crew(_ d: DayStats) -> some View {
        let list = d.crew.sorted { ($0.value.projectKey, $0.value.name) < ($1.value.projectKey, $1.value.name) }.prefix(8)
        return VStack(alignment: .leading, spacing: 6) {
            Text("함께한 동료").font(.headline)
            HStack(spacing: 12) {
                ForEach(Array(list), id: \.key) { _, m in
                    VStack(spacing: 2) {
                        CharacterThumb(ref: m.character, shirt: settings.projectColor(m.projectKey), size: 26)
                        Text(m.name).font(.caption2).lineLimit(1)
                    }
                    .help(settings.projectName(m.projectKey))
                }
            }
        }
    }

    private func week(_ days: [DayStats]) -> some View {
        let cal = Calendar.current
        let keys = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()).map(DailyStats.key) }
        let byKey = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let top = max(3600, keys.compactMap { byKey[$0]?.busySeconds }.max() ?? 0)
        let current = selected ?? stats.today.day
        return VStack(alignment: .leading, spacing: 6) {
            Text("지난 7일").font(.headline)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(keys, id: \.self) { k in
                    let secs = byKey[k]?.busySeconds ?? 0
                    Button { selected = k } label: {
                        VStack(spacing: 3) {
                            Text(secs > 0 ? formatDuration(secs) : "").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                                .fill(secs > 0 ? Color.accentColor.opacity(k == current ? 1 : 0.45) : Color.primary.opacity(0.08))
                                .frame(height: max(2, 50 * secs / top))
                            Text(Self.weekday(k)).font(.caption2.weight(k == current ? .bold : .regular))
                                .foregroundStyle(k == current ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(Self.dateLabel(k)) · \(formatDuration(secs))")
                }
            }
            .frame(height: 84, alignment: .bottom)
        }
    }

    private static func date(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    static func dateLabel(_ key: String) -> String {
        guard let d = date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f.string(from: d)
    }

    private static func weekday(_ key: String) -> String {
        guard let d = date(key) else { return "" }
        if key == DailyStats.key(Date()) { return "오늘" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f.string(from: d)
    }

    private static func cheer(_ d: DayStats) -> String {
        if d.busySeconds >= 6 * 3600 { return "긴 하루였어요, 푹 쉬어요" }
        if d.testsPassed >= 5 { return "테스트가 잘 통과한 날이에요" }
        if d.longTasks > 0 { return "큰일을 해냈어요" }
        return "오늘도 수고했어요"
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(note ?? " ").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

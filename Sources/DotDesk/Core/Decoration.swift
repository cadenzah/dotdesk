import Foundation

/// Office decorations earned by working with the agents over time.
enum Decoration: String, CaseIterable, Identifiable {
    case frame, lights, lamp, trophies, cat, plaque
    var id: String { rawValue }

    var name: String {
        switch self {
        case .frame: return "그림 액자"
        case .lights: return "줄 전구"
        case .lamp: return "스탠드 조명"
        case .trophies: return "트로피 선반"
        case .cat: return "창가 고양이"
        case .plaque: return "100시간 명패"
        }
    }

    var goal: String {
        switch self {
        case .frame: return "첫 작업 끝내기"
        case .lights: return "3일 동안 함께 일하기"
        case .lamp: return "요청 100번"
        case .trophies: return "테스트 통과 10번 (50번, 200번이면 트로피가 늘어요)"
        case .cat: return "5분 넘게 걸린 긴 작업 10번"
        case .plaque: return "함께 일한 시간 100시간"
        }
    }

    /// Where the totals stand against the goal.
    func progress(_ t: Totals) -> (current: Double, target: Double) {
        switch self {
        case .frame: return (Double(t.turnsDone), 1)
        case .lights: return (Double(t.activeDays), 3)
        case .lamp: return (Double(t.prompts), 100)
        case .trophies: return (Double(t.testsPassed), 10)
        case .cat: return (Double(t.longTasks), 10)
        case .plaque: return (t.busySeconds / 3600, 100)
        }
    }

    func isMet(_ t: Totals) -> Bool {
        let p = progress(t)
        return p.current >= p.target
    }

    /// Trophies on the shelf: one at 10 passes, two at 50, three at 200.
    static func trophyCount(_ t: Totals) -> Int {
        t.testsPassed >= 200 ? 3 : t.testsPassed >= 50 ? 2 : t.testsPassed >= 10 ? 1 : 0
    }
}

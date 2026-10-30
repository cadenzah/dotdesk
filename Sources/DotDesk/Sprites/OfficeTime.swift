import Foundation

/// The time of day and year as the office shows it: the sky in the windows, how dark the room is, the season.
struct OfficeTime {
    enum Phase { case night, dawn, day, afternoon, sunset, dusk }
    enum Season {
        case spring, summer, autumn, winter

        /// What drifts past the window, and how much of it.
        var particle: (RGBA, Int)? {
            switch self {
            case .winter: return (RGBA(0xffffff), 6)
            case .spring: return (RGBA(0xfcc2d7), 4)
            case .autumn: return (RGBA(0xf08c00), 3)
            case .summer: return nil
            }
        }
    }
    enum Holiday { case halloween, christmas }

    let hour: Double
    let phase: Phase
    let season: Season
    let holiday: Holiday?

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        hour = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        switch hour {
        case 5..<7: phase = .dawn
        case 7..<16.5: phase = .day
        case 16.5..<18: phase = .afternoon
        case 18..<19.5: phase = .sunset
        case 19.5..<20.5: phase = .dusk
        default: phase = .night
        }
        let month = c.month ?? 6, day = c.day ?? 1
        switch month {
        case 3...5: season = .spring
        case 6...8: season = .summer
        case 9...11: season = .autumn
        default: season = .winter
        }
        if month == 10, day >= 24 { holiday = .halloween }
        else if month == 12, day <= 25 { holiday = .christmas }
        else { holiday = nil }
    }

    /// Too dark out to read by: lamps glow and the window cat sleeps.
    var dark: Bool { phase == .night || phase == .dusk }

    /// Sky colours at the top of the window and near the horizon.
    var sky: (RGBA, RGBA) {
        switch phase {
        case .night: return (RGBA(0x1b2550), RGBA(0x2b3a67))
        case .dawn: return (RGBA(0x5c6bb0), RGBA(0xffb38a))
        case .day: return (RGBA(0x74c0fc), RGBA(0xa5d8ff))
        case .afternoon: return (RGBA(0x91c8f6), RGBA(0xffd8a8))
        case .sunset: return (RGBA(0x7a5fb0), RGBA(0xff922b))
        case .dusk: return (RGBA(0x2b3a67), RGBA(0x8a5a9e))
        }
    }

    /// Where the sun (6:00–19:30) or moon (19:30–6:00) is along its arc, 0 at the left edge to 1 at the right.
    var celestial: (Double, Bool)? {
        if hour >= 6, hour < 19.5 { return ((hour - 6) / 13.5, false) }
        let h = hour >= 19.5 ? hour - 19.5 : hour + 4.5
        return (h / 10.5, true)
    }

    /// How much the room dims, 0 in daylight.
    var shade: CGFloat {
        switch phase {
        case .night: return 0.22
        case .dusk: return 0.14
        case .sunset: return 0.06
        case .dawn: return 0.1
        default: return 0
        }
    }

    /// Working past ten at night or before five in the morning.
    var lateNight: Bool { hour >= 22 || hour < 5 }
}

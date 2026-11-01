import SwiftUI

/// The nine task types (frontend/src/lib/taskTypes.ts) with the web's on-glass tints (design/tokens.css).
enum TaskKind: String, CaseIterable, Identifiable {
    case study, work, reading, fitness, meeting, habit, errand, personal, other

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .study: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .reading: "book.fill"
        case .fitness: "dumbbell.fill"
        case .meeting: "person.2.fill"
        case .habit: "repeat"
        case .errand: "bag.fill"
        case .personal: "heart.fill"
        case .other: "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .study: Palette.indigo
        case .work: Palette.cyan
        case .reading: Palette.orange
        case .fitness: Palette.pink
        case .meeting: Palette.purple
        case .habit: Palette.mint
        case .errand: Palette.brown
        case .personal: Palette.yellow
        case .other: Palette.gray
        }
    }
}

enum Palette {
    static let indigo = Color(hex: 0x8F8CFF)
    static let cyan = Color(hex: 0x5CCBFF)
    static let orange = Color(hex: 0xFFAA3D)
    static let pink = Color(hex: 0xFF6F91)
    static let purple = Color(hex: 0xD08CFF)
    static let mint = Color(hex: 0x5EE6DD)
    static let brown = Color(hex: 0xC9A27A)
    static let yellow = Color(hex: 0xFFD84D)
    static let gray = Color(hex: 0xA8ADBD)
    static let teal = Color(hex: 0x62D2E6)
    static let red = Color(hex: 0xFF7A70)
    static let redText = Color(hex: 0xFFBDB6)
    /// Lime: "now / today / selected / live" only.
    static let signal = Color(hex: 0xC6F432)
    static let flag = Color(hex: 0xFFC46B)
    /// Dark text on white, lime and tint discs.
    static let ink = Color(hex: 0x0B1020)

    // the environment behind the glass (tokens.css --env-*)
    static let envTop = Color(hex: 0x0A4E86)
    static let envBase = Color(hex: 0x0B74AA)
    static let envDeep = Color(hex: 0x1A2C6A)
    static let envPlum = Color(hex: 0x6A1F5C)
    static let envMagenta = Color(hex: 0xB02E6E)
    static let envCoral = Color(hex: 0xCC4F62)

    static let sectionTints: [Color] = [indigo, cyan, orange, pink, purple, mint, teal, brown]

    /// A stable colour per checklist section, same hash as the web, so a box keeps its colour.
    static func tint(forSection name: String) -> Color {
        if name == "Missed" { return red }
        var hash: Int32 = 0
        for unit in name.utf16 { hash = hash &* 31 &+ Int32(unit) }
        return sectionTints[Int(hash.magnitude) % sectionTints.count]
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

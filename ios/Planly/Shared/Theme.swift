//
//  Theme.swift
//  Planly (shared)
//
//  The website's dark "glass" palette (frontend/src/design/tokens.css) and per-type styling.
//

import SwiftUI

extension Color {
    /// A colour from a 0xRRGGBB literal.
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

nonisolated enum Palette {
    static let indigo = Color(hex: 0x8F8CFF)
    static let cyan = Color(hex: 0x5CCBFF)
    static let orange = Color(hex: 0xFFAA3D)
    static let pink = Color(hex: 0xFF6F91)
    static let purple = Color(hex: 0xD08CFF)
    static let mint = Color(hex: 0x5EE6DD)
    static let teal = Color(hex: 0x62D2E6)
    static let brown = Color(hex: 0xC9A27A)
    static let yellow = Color(hex: 0xFFD84D)
    static let gray = Color(hex: 0xA8ADBD)

    static let red = Color(hex: 0xFF7A70)
    static let lime = Color(hex: 0xC6F432)
    static let flag = Color(hex: 0xFFC46B)
    /// Dark ink for text and glyphs on a solid tint.
    static let ink = Color(hex: 0x0B1020)

    static let label = Color.white
    static let secondary = Color.white.opacity(0.84)
    static let tertiary = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.18)

    /// The full-screen backdrop, top-leading to bottom-trailing.
    static let backdrop: [Color] = [
        Color(hex: 0x0A4E86), Color(hex: 0x0B74AA), Color(hex: 0x1A2C6A),
        Color(hex: 0x6A1F5C), Color(hex: 0xB02E6E), Color(hex: 0xCC4F62),
    ]

    private static let sectionTints: [Color] = [indigo, cyan, orange, pink, purple, mint, teal, brown]

    /// A stable colour per section name (the website's `h = h*31 + utf16` hash), so a section keeps
    /// its colour across weeks and devices.
    static func sectionTint(_ section: String) -> Color {
        if section == "Missed" { return red }
        var hash: Int32 = 0
        for unit in section.utf16 { hash = hash &* 31 &+ Int32(unit) }
        return sectionTints[Int(hash.magnitude % UInt32(sectionTints.count))]
    }
}

extension TaskType {
    nonisolated var label: String { rawValue.capitalized }

    nonisolated var symbol: String {
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

    nonisolated var color: Color {
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

//
//  Glass.swift
//  Planly
//
//  The website's glass look: a full-screen gradient environment with translucent cards over it.
//

import SwiftUI

/// The full-screen gradient behind every screen.
struct Backdrop: View {
    var body: some View {
        LinearGradient(colors: Palette.backdrop, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Color.black.opacity(0.12))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// A translucent card with a hairline edge.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.06))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }

    /// Puts a screen over the gradient, with dark navigation bars that let the gradient show through.
    func planlyScreen() -> some View {
        background(Backdrop())
            .scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// A small rounded label, e.g. a duration or "Free · 1h".
struct Pill: View {
    var text: String
    var color: Color = Palette.secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.12)))
    }
}

/// A round tick box in a tint colour.
struct TickBox: View {
    var done: Bool
    var tint: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? tint : Palette.tertiary, lineWidth: 1.75)
                .background(Circle().fill(done ? tint : .clear))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// A large, light display title like the website's headings.
struct DisplayTitle: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.largeTitle.weight(.light))
            .foregroundStyle(Palette.label)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Animation that respects Reduce Motion.
@MainActor
func planlyAnimation(_ reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12)
}

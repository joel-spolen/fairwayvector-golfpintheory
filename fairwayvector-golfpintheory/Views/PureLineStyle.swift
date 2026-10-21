import SwiftUI

/// Presentation-only palette for the experimental home, course and handicap screens.
/// Deliberately separate from the shared Practice design system.
enum PureLineStyle {
    // Opaque dark teal keeps white action labels readable (WCAG contrast > 6:1).
    static let accent = Color(red: 0.0, green: 0.40, blue: 0.36)
    static let pressedAccent = Color(red: 0.0, green: 0.32, blue: 0.29)
    static let ink = Color(red: 0.10, green: 0.15, blue: 0.16)
    static let muted = Color(red: 0.40, green: 0.46, blue: 0.47)
    static let canvas = Color.white
    static let surface = Color(red: 0.96, green: 0.98, blue: 0.98)
    static let line = Color(red: 0.88, green: 0.92, blue: 0.91)
}

/// Root navigation only. Place inside the feature's stack, never above it.
struct PureLineHomeButton: View {
    let onHome: () -> Void

    var body: some View {
        HStack {
            Button(action: onHome) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Home")
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("return-home-button")
            Spacer()
        }
        .padding(.horizontal, 20)
        .foregroundStyle(PureLineStyle.accent)
        .background(PureLineStyle.canvas)
    }
}

struct PureLinePageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold)).tracking(-0.6)
                .foregroundStyle(PureLineStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func pureLineCard(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .foregroundStyle(PureLineStyle.ink)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(PureLineStyle.line.opacity(0.6), lineWidth: 1)
            }
    }
}

struct PureLinePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fillsWidth = true
    var minimumHeight: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : PureLineStyle.ink)
            .tint(isEnabled ? Color.white : PureLineStyle.ink)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minimumHeight)
            .background(
                isEnabled
                    ? (configuration.isPressed ? PureLineStyle.pressedAccent : PureLineStyle.accent)
                    : PureLineStyle.line,
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
}
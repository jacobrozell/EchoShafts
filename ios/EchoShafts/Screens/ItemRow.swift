import SwiftUI

struct ItemRow: View {
    var name: String
    var line: String
    var dimmed = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(dimmed ? Color(hex: 0xb7aa9c) : Color(hex: 0xf3eadf))
                if !line.isEmpty {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: 0xb7aa9c))
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                PanelButton(title: actionTitle, action: action)
            }
        }
        .frame(minHeight: 44)
    }
}

struct PanelButton: View {
    var title: String
    var primary = false
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(primary ? .semibold : .regular))
                .foregroundStyle(primary ? Color.white : Color(hex: 0xf3eadf))
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 14)
                .background(primary ? Color(hex: 0xc8343c) : Color(hex: 0x221b16))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: primary ? 0x8e242c : 0x3a2e26), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(enabled ? 1 : 0.45)
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

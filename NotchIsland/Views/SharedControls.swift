import SwiftUI

// Controls shared by the Storage and Dev tabs.

/// A destructive button that needs a second click within a few seconds.
struct ConfirmButton: View {
    var title: LocalizedStringKey?
    var symbol: String?
    let confirmTitle: LocalizedStringKey
    let action: () -> Void
    @State private var isArmed = false

    var body: some View {
        Button {
            if isArmed {
                isArmed = false
                action()
            } else {
                isArmed = true
            }
        } label: {
            Group {
                if isArmed {
                    Text(confirmTitle)
                } else if let symbol {
                    Image(systemName: symbol)
                } else if let title {
                    Text(title)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isArmed ? .white : .white.opacity(0.85))
            .padding(.horizontal, isArmed || title != nil ? 8 : 4)
            .frame(height: 20)
            .background(Capsule().fill(isArmed ? Color.red : .white.opacity(title != nil ? 0.12 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isArmed)
        .task(id: isArmed) {
            guard isArmed else { return }
            try? await Task.sleep(for: .seconds(3))
            isArmed = false
        }
    }
}

extension View {
    func rowStyle(isHovering: Bool) -> some View {
        font(.system(size: 11))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.16 : 0.06))
            )
            .contentShape(Rectangle())
    }

    func pillStyle() -> some View {
        font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(0.12)))
            .contentShape(Capsule())
    }
}

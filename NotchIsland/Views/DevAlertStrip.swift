import AppKit
import SwiftUI

/// A finished terminal command or agent turn, under the notch while idle.
struct DevAlertStripView: View {
    let event: DevEvent
    let notchHeight: CGFloat

    static let height: CGFloat = 26
    private static let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    /// Icon, spacing and side padding around the text.
    private static let chrome: CGFloat = 16 + 6 + 6 + 32

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 6) {
                Image(systemName: event.status.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.status.tint)
                    .symbolEffect(.bounce, value: event.id)
                Text(verbatim: Self.headline(event))
                    .font(Font(Self.font))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = event.detail {
                    Text(verbatim: detail)
                        .font(Font(Self.detailFont))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .id(event.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.3), value: event.id)
    }

    /// "Claude Code · Finished", or the command for terminal events.
    static func headline(_ event: DevEvent) -> String {
        event.isAgent ? "\(event.sourceName) · \(event.title)" : event.title
    }

    static func width(for event: DevEvent) -> CGFloat {
        let headline = (headline(event) as NSString).size(withAttributes: [.font: font]).width
        let detail = event.detail.map { ($0 as NSString).size(withAttributes: [.font: detailFont]).width + 6 } ?? 0
        // Keep it compact; long details are truncated.
        return ceil(min(headline, 280) + min(detail, 220) + chrome)
    }
}

extension DevEventStatus {
    var tint: Color {
        switch self {
        case .success: .green
        case .failure: .red
        case .attention: .orange
        case .working: .blue
        case .info: .white
        }
    }
}

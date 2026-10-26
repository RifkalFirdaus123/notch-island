import AppKit
import SwiftUI

/// One line of lyrics under the notch while the island is idle.
struct LyricStripView: View {
    let line: String
    let notchHeight: CGFloat
    let stripHeight: CGFloat
    var tint: Color

    static let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            ZStack {
                Text(line)
                    .font(Font(Self.font))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 14)
                    .id(line)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity)
            .frame(height: stripHeight)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.3), value: line)
    }

    /// Width the text needs, including padding.
    static func textWidth(_ line: String) -> CGFloat {
        ceil((line as NSString).size(withAttributes: [.font: font]).width) + 28
    }
}

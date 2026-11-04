import AppKit
import SwiftUI

/// One line of lyrics under the notch while the island is idle.
struct LyricStripView: View {
    let line: String
    let notchHeight: CGFloat
    let stripHeight: CGFloat
    var mood: LyricMood = .neutral

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            ZStack {
                Text(line)
                    .font(Font(mood.font))
                    .foregroundStyle(mood.gradient)
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
        .animation(.easeInOut(duration: 0.4), value: mood)
    }

    /// Width the text needs in the mood's font, including padding.
    static func textWidth(_ line: String, mood: LyricMood) -> CGFloat {
        ceil((line as NSString).size(withAttributes: [.font: mood.font]).width) + 28
    }
}

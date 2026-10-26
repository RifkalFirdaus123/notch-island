import SwiftUI

/// Home tab: now playing on the left, clock and battery on the right.
struct HomeTabView: View {
    @ObservedObject var clock: ClockService
    @ObservedObject var battery: BatteryService
    let nowPlaying: NowPlayingService

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            NowPlayingView(nowPlaying: nowPlaying)

            VStack(alignment: .trailing, spacing: 2) {
                Text(clock.now, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(clock.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 8)
                if let status = battery.status {
                    BatteryIndicator(status: status, showsDetail: true)
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .animation(.default, value: clock.now)
        }
    }
}

struct BatteryIndicator: View {
    let status: BatteryStatus
    var showsDetail = false

    private var tint: Color {
        if status.isCharging { return .green }
        if status.isLow { return .red }
        return .white
    }

    private var detail: LocalizedStringKey {
        if status.isCharging { return "Charging" }
        if status.isPluggedIn { return status.isCharged ? "Fully charged" : "Plugged in" }
        return "On battery"
    }

    var body: some View {
        HStack(spacing: 5) {
            if showsDetail {
                Text(detail)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(verbatim: "\(status.level)%")
                .monospacedDigit()
            Image(systemName: status.symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

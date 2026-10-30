import SwiftUI

/// Home tab: now playing on the left; clock, system stats and battery on
/// the right.
struct HomeTabView: View {
    @ObservedObject var clock: ClockService
    @ObservedObject var battery: BatteryService
    @ObservedObject var systemStats: SystemStatsService
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
                if let stats = systemStats.stats {
                    SystemStatsView(stats: stats, thermalState: systemStats.thermalState)
                        .padding(.top, 6)
                }
                Spacer(minLength: 6)
                if let status = battery.status {
                    BatteryIndicator(
                        status: status,
                        showsDetail: true,
                        temperature: systemStats.stats?.batteryTemperature
                    )
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .animation(.default, value: clock.now)
        }
        .onAppear { systemStats.beginObserving() }
        .onDisappear { systemStats.endObserving() }
    }
}

/// CPU load and temperature, then memory and startup disk in use.
struct SystemStatsView: View {
    let stats: SystemStats
    let thermalState: ProcessInfo.ThermalState

    private static let bytesPerGB = Double(1 << 30)

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 5) {
                Text(verbatim: "CPU")
                    .foregroundStyle(.white.opacity(0.5))
                Text(verbatim: stats.cpuUsage.map { "\($0)%" } ?? "–")
                    .contentTransition(.numericText())
                if let temperature = stats.cpuTemperature {
                    TemperatureLabel(celsius: temperature, tint: cpuTint(temperature))
                }
            }
            HStack(spacing: 5) {
                Text(verbatim: "RAM")
                    .foregroundStyle(.white.opacity(0.5))
                Text(verbatim: memoryText)
                    .contentTransition(.numericText())
            }
            if let storage = stats.storage {
                HStack(spacing: 5) {
                    Text(verbatim: "SSD")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(verbatim: storageText(used: storage.used, total: storage.total))
                        .foregroundStyle(storageTint(used: storage.used, total: storage.total))
                        .contentTransition(.numericText())
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .animation(.default, value: stats)
        .accessibilityElement(children: .combine)
    }

    private var memoryText: String {
        let used = Double(stats.memoryUsed) / Self.bytesPerGB
        let total = (Double(stats.memoryTotal) / Self.bytesPerGB).rounded()
        return "\(used.formatted(.number.precision(.fractionLength(1)))) / \(Int(total)) GB"
    }

    /// Decimal units, matching how Finder and System Settings report disks.
    private func storageText(used: Int64, total: Int64) -> String {
        let usedGB = Double(used) / 1e9
        let totalGB = Double(total) / 1e9
        let totalText = totalGB >= 1000
            ? "\((totalGB / 1000).formatted(.number.precision(.fractionLength(0...1)))) TB"
            : "\(Int(totalGB.rounded())) GB"
        return "\(Int(usedGB.rounded())) GB / \(totalText)"
    }

    /// Warn as the disk fills up: macOS slows down with little free space.
    private func storageTint(used: Int64, total: Int64) -> Color {
        let fraction = Double(used) / Double(total)
        if fraction >= 0.95 { return .red }
        if fraction >= 0.85 { return .orange }
        return .white
    }

    /// The system's thermal state wins: it reflects actual throttling.
    private func cpuTint(_ celsius: Double) -> Color {
        switch thermalState {
        case .critical: return .red
        case .serious: return .orange
        default: break
        }
        if celsius >= 95 { return .red }
        if celsius >= 80 { return .orange }
        return .white
    }
}

struct TemperatureLabel: View {
    let celsius: Double
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 10, weight: .semibold))
            Text(verbatim: "\(Int(celsius.rounded()))°")
        }
        .foregroundStyle(tint)
    }
}

struct BatteryIndicator: View {
    let status: BatteryStatus
    var showsDetail = false
    /// Degrees Celsius, shown in front of the detail when known.
    var temperature: Double?

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
            if showsDetail, let temperature {
                TemperatureLabel(celsius: temperature, tint: temperature >= 45 ? .orange : .white.opacity(0.5))
            }
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

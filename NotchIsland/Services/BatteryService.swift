import Combine
import Foundation
import IOKit.ps

struct BatteryStatus: Equatable {
    /// 0–100.
    var level: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isCharged: Bool

    static let lowLevel = 20

    var isLow: Bool { level <= Self.lowLevel && !isPluggedIn }

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Where battery readings come from; swapped for a fake in tests.
protocol BatterySource: AnyObject {
    /// Nil when the Mac has no internal battery.
    func currentStatus() -> BatteryStatus?
    /// Calls `handler` on the main thread whenever power source info changes.
    func startObserving(_ handler: @escaping () -> Void)
}

final class BatteryService: ObservableObject {
    @Published private(set) var status: BatteryStatus?

    private let source: BatterySource

    init(source: BatterySource = IOKitBatterySource()) {
        self.source = source
    }

    func start() {
        refresh()
        source.startObserving { [weak self] in self?.refresh() }
    }

    func refresh() {
        let newStatus = source.currentStatus()
        if newStatus != status { status = newStatus }
    }
}

/// Reads the internal battery via IOPowerSources and gets change
/// notifications from the system instead of polling.
final class IOKitBatterySource: BatterySource {
    private var runLoopSource: CFRunLoopSource?
    private var handler: (() -> Void)?

    func currentStatus() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryStatus(
                level: maximum > 0 ? min(100, current * 100 / maximum) : 0,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }

    func startObserving(_ handler: @escaping () -> Void) {
        guard runLoopSource == nil else { return }
        self.handler = handler

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(Self.powerSourceChanged, context)?
                .takeRetainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    // Runs on the main run loop, where the source was added.
    private nonisolated static let powerSourceChanged: IOPowerSourceCallbackType = { context in
        // Pass the address as an Int (Sendable); it is only turned back into
        // the object on the main thread.
        let address = Int(bitPattern: context)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            let source = Unmanaged<IOKitBatterySource>.fromOpaque(pointer).takeUnretainedValue()
            source.handler?()
        }
    }
}

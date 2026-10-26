import Combine
import Darwin
import Foundation

struct SystemStats: Equatable {
    /// 0–100, averaged over all cores since the previous reading.
    var cpuUsage: Int?
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    /// Degrees Celsius; nil when the sensors can't be read.
    var cpuTemperature: Double?
    var batteryTemperature: Double?

    var memoryFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }
}

/// Where readings come from; swapped for a fake in tests.
protocol SystemStatsSource: AnyObject {
    func currentStats() -> SystemStats
}

/// Polls CPU, memory and temperatures, but only while a view showing them
/// is on screen, so the app stays idle the rest of the time.
final class SystemStatsService: ObservableObject {
    @Published private(set) var stats: SystemStats?
    /// The system's own throttling level; drives the temperature tint.
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState

    static let pollInterval: Duration = .seconds(2)

    private let source: SystemStatsSource
    private var pollTask: Task<Void, Never>?
    private var viewers = 0

    init(source: SystemStatsSource = MachSystemStatsSource()) {
        self.source = source
    }

    /// Call from `onAppear`; balanced by `endObserving` in `onDisappear`.
    func beginObserving() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func endObserving() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        let newStats = source.currentStats()
        if newStats != stats { stats = newStats }
        let newThermal = ProcessInfo.processInfo.thermalState
        if newThermal != thermalState { thermalState = newThermal }
    }
}

/// CPU and memory from Mach host statistics; temperatures from the Apple
/// Silicon HID sensors.
final class MachSystemStatsSource: SystemStatsSource {
    private var previousTicks: [UInt32]?
    private let temperatures = HIDTemperatureReader()

    init() {
        // Prime the tick counters so the first real reading has a baseline.
        _ = cpuUsage()
    }

    func currentStats() -> SystemStats {
        let memory = memoryUsage()
        let sensors = temperatures.read()
        return SystemStats(
            cpuUsage: cpuUsage(),
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            cpuTemperature: sensors.cpu,
            batteryTemperature: sensors.battery
        )
    }

    /// Busy share of the ticks elapsed since the last call; nil on the first.
    private func cpuUsage() -> Int? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }

        // Counters wrap, so subtract with overflow.
        let delta = zip(ticks, previous).map { $0 &- $1 }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        let idle = delta[Int(CPU_STATE_IDLE)]
        return Int((Double(total - idle) / Double(total) * 100).rounded())
    }

    /// "Memory Used" as Activity Monitor counts it: app + wired + compressed.
    private func memoryUsage() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }

        let appPages = UInt64(info.internal_page_count) - UInt64(min(info.purgeable_count, info.internal_page_count))
        let pages = appPages + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        return (min(total, pages * UInt64(getpagesize())), total)
    }
}

/// Reads temperature sensors through IOHIDEventSystemClient. That API is
/// private, so it's looked up at runtime and simply yields nil if a future
/// macOS removes or renames it.
final class HIDTemperatureReader {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField = Int32(15 << 16)
    /// Per-core die sensors of the main PMU ("PMU2" sits on the other die).
    private static let cpuSensorPrefix = "PMU tdie"
    private static let batterySensorName = "gas gauge battery"
    private static let plausibleRange = 1.0...130.0

    private struct API {
        let copyServices: CopyServices
        let copyProperty: CopyProperty
        let copyEvent: CopyEvent
        let getFloatValue: GetFloatValue
    }

    private let api: API?
    /// Sensor services keyed by product name, found once at startup.
    private var services: [(name: String, service: AnyObject)] = []
    private var client: AnyObject?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatValue = dlsym(handle, "IOHIDEventGetFloatValue")
        else {
            api = nil
            return
        }
        let api = API(
            copyServices: unsafeBitCast(copyServices, to: CopyServices.self),
            copyProperty: unsafeBitCast(copyProperty, to: CopyProperty.self),
            copyEvent: unsafeBitCast(copyEvent, to: CopyEvent.self),
            getFloatValue: unsafeBitCast(getFloatValue, to: GetFloatValue.self)
        )
        self.api = api

        guard let client = unsafeBitCast(create, to: CreateClient.self)(kCFAllocatorDefault)?
                .takeRetainedValue()
        else { return }
        // Vendor usage page / temperature sensor usage.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        unsafeBitCast(setMatching, to: SetMatching.self)(client, matching)
        self.client = client

        let list = api.copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        services = list.compactMap { service in
            guard let name = api.copyProperty(service, "Product" as CFString)?
                    .takeRetainedValue() as? String,
                  name.hasPrefix(Self.cpuSensorPrefix) || name == Self.batterySensorName
            else { return nil }
            return (name, service)
        }
    }

    func read() -> (cpu: Double?, battery: Double?) {
        guard let api else { return (nil, nil) }
        var cpuReadings: [Double] = []
        var batteryReading: Double?

        for (name, service) in services {
            guard let event = api.copyEvent(service, Self.temperatureEventType, 0, 0)?
                    .takeRetainedValue()
            else { continue }
            let value = api.getFloatValue(event, Self.temperatureField)
            guard Self.plausibleRange.contains(value) else { continue }
            if name == Self.batterySensorName {
                batteryReading = value
            } else {
                cpuReadings.append(value)
            }
        }

        let cpu = cpuReadings.isEmpty ? nil : cpuReadings.reduce(0, +) / Double(cpuReadings.count)
        return (cpu, batteryReading)
    }
}

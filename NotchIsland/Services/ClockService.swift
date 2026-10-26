import AppKit
import Combine

/// Publishes the current time, ticking once at the start of each minute.
/// Formatting is left to the views so it follows the system 12/24-hour
/// setting and locale.
final class ClockService: ObservableObject {
    @Published private(set) var now: Date

    private let currentDate: () -> Date
    private var tickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(currentDate: @escaping () -> Date = Date.init) {
        self.currentDate = currentDate
        now = currentDate()
    }

    func start() {
        refresh()

        // Clock or time zone changed, locale (incl. 12/24h) changed, or woke
        // from sleep: refresh and realign the minute tick.
        let center = NotificationCenter.default
        Publishers.MergeMany(
            center.publisher(for: .NSSystemClockDidChange),
            center.publisher(for: .NSSystemTimeZoneDidChange),
            center.publisher(for: NSLocale.currentLocaleDidChangeNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.refresh() }
        .store(in: &cancellables)
    }

    func refresh() {
        now = currentDate()
        scheduleTick()
    }

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = Self.secondsUntilNextMinute(after: self?.currentDate() ?? Date())
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.now = self.currentDate()
            }
        }
    }

    /// Time zone offsets are whole minutes, so minute boundaries line up
    /// with the reference date.
    nonisolated static func secondsUntilNextMinute(after date: Date) -> TimeInterval {
        let intoMinute = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        // Small margin so we land just after the boundary, not before it.
        return 60 - intoMinute + 0.05
    }
}

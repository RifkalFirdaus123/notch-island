import AppKit
import Combine
import Foundation
import UserNotifications

enum PomodoroPhase: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }
}

enum PomodoroTimerState: Equatable {
    case idle
    case running
    case paused
    case completed
}

@MainActor
final class PomodoroService: ObservableObject {
    @Published var phase: PomodoroPhase = .focus
    @Published var state: PomodoroTimerState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var totalDuration: TimeInterval = 25 * 60
    @Published var completedSessions: Int = 0

    private var timer: Timer?
    private var targetEndTime: Date?
    private var cancellables = Set<AnyCancellable>()

    init() {
        requestNotificationPermission()
        loadDurations()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.state == .idle else { return }
                self.loadDurations()
            }
            .store(in: &cancellables)
    }

    deinit {
        timer?.invalidate()
    }

    var isActive: Bool {
        state == .running || state == .paused
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(1.0, max(0.0, 1.0 - (timeRemaining / totalDuration)))
    }

    var formattedTime: String {
        let total = Int(ceil(timeRemaining))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var targetInterval: Int {
        let val = UserDefaults.standard.integer(forKey: SettingsKeys.pomodoroLongBreakInterval)
        return val > 0 ? val : 4
    }

    var nextPhase: PomodoroPhase {
        switch phase {
        case .focus:
            let nextCompleted = completedSessions + 1
            return (nextCompleted % targetInterval == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    func playPause() {
        switch state {
        case .running:
            pause()
        case .idle, .paused, .completed:
            start()
        }
    }

    func start() {
        guard state != .running else { return }
        if state == .completed || timeRemaining <= 0 {
            timeRemaining = duration(for: phase)
            totalDuration = timeRemaining
        }
        state = .running
        targetEndTime = Date().addingTimeInterval(timeRemaining)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        if let target = targetEndTime {
            timeRemaining = max(0, target.timeIntervalSinceNow)
        }
        targetEndTime = nil
        timer?.invalidate()
        timer = nil
        state = .paused
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        targetEndTime = nil
        state = .idle
        timeRemaining = duration(for: phase)
        totalDuration = timeRemaining
    }

    func skip() {
        timer?.invalidate()
        timer = nil
        targetEndTime = nil
        let upcoming = nextPhase
        if phase == .focus {
            completedSessions += 1
        }
        phase = upcoming
        state = .idle
        timeRemaining = duration(for: phase)
        totalDuration = timeRemaining
    }

    func setPhase(_ newPhase: PomodoroPhase) {
        guard phase != newPhase else { return }
        timer?.invalidate()
        timer = nil
        targetEndTime = nil
        phase = newPhase
        state = .idle
        timeRemaining = duration(for: newPhase)
        totalDuration = timeRemaining
    }

    // MARK: - Private Helpers

    private func tick() {
        guard state == .running, let target = targetEndTime else { return }
        let remaining = target.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            completeCurrentPhase()
        } else {
            timeRemaining = remaining
        }
    }

    private func completeCurrentPhase() {
        timer?.invalidate()
        timer = nil
        targetEndTime = nil
        state = .completed

        sendNotificationAndSound()

        let upcoming = nextPhase
        if phase == .focus {
            completedSessions += 1
        }
        phase = upcoming
        timeRemaining = duration(for: upcoming)
        totalDuration = timeRemaining
    }

    private func duration(for phase: PomodoroPhase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus:
            let val = UserDefaults.standard.integer(forKey: SettingsKeys.pomodoroWorkMinutes)
            minutes = val > 0 ? val : 25
        case .shortBreak:
            let val = UserDefaults.standard.integer(forKey: SettingsKeys.pomodoroShortBreakMinutes)
            minutes = val > 0 ? val : 5
        case .longBreak:
            let val = UserDefaults.standard.integer(forKey: SettingsKeys.pomodoroLongBreakMinutes)
            minutes = val > 0 ? val : 15
        }
        return TimeInterval(minutes * 60)
    }

    private func loadDurations() {
        let dur = duration(for: phase)
        totalDuration = dur
        timeRemaining = dur
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotificationAndSound() {
        if NSSound(named: "Glass")?.play() != true {
            NSSound.beep()
        }

        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        if phase == .focus {
            content.title = String(localized: "Focus Session Finished!")
            content.body = String(localized: "Great job! Time for a well-deserved break.")
        } else {
            content.title = String(localized: "Break Ended!")
            content.body = String(localized: "Ready to get back to focusing?")
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pomodoro-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

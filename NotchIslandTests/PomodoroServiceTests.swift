import Foundation
import Testing
#if canImport(NotchIsland)
@testable import NotchIsland
#endif

@MainActor
struct PomodoroServiceTests {
    @Test func initialStateDefaults() {
        SettingsKeys.registerDefaults()
        let service = PomodoroService()

        #expect(service.phase == .focus)
        #expect(service.state == .idle)
        #expect(service.isActive == false)
        #expect(service.formattedTime == "25:00")
        #expect(service.completedSessions == 0)
    }

    @Test func startAndPauseTransitions() {
        SettingsKeys.registerDefaults()
        let service = PomodoroService()

        service.start()
        #expect(service.state == .running)
        #expect(service.isActive == true)

        service.pause()
        #expect(service.state == .paused)
        #expect(service.isActive == true)

        service.reset()
        #expect(service.state == .idle)
        #expect(service.isActive == false)
        #expect(service.formattedTime == "25:00")
    }

    @Test func phaseProgression() {
        SettingsKeys.registerDefaults()
        let service = PomodoroService()

        // Focus session 1 -> skip -> short break
        #expect(service.nextPhase == .shortBreak)
        service.skip()
        #expect(service.completedSessions == 1)
        #expect(service.phase == .shortBreak)
        #expect(service.formattedTime == "05:00")

        // Short break -> skip -> Focus session 2
        #expect(service.nextPhase == .focus)
        service.skip()
        #expect(service.phase == .focus)

        // Session 2 -> short break
        service.skip()
        #expect(service.completedSessions == 2)
        #expect(service.phase == .shortBreak)

        // Short break -> Session 3
        service.skip()
        #expect(service.phase == .focus)

        // Session 3 -> short break
        service.skip()
        #expect(service.completedSessions == 3)
        #expect(service.phase == .shortBreak)

        // Short break -> Session 4
        service.skip()
        #expect(service.phase == .focus)
        #expect(service.nextPhase == .longBreak)

        // Session 4 -> long break (target interval 4)
        service.skip()
        #expect(service.completedSessions == 4)
        #expect(service.phase == .longBreak)
        #expect(service.formattedTime == "15:00")
    }

    @Test func manualPhaseSwitching() {
        SettingsKeys.registerDefaults()
        let service = PomodoroService()

        service.setPhase(.longBreak)
        #expect(service.phase == .longBreak)
        #expect(service.formattedTime == "15:00")

        service.setPhase(.shortBreak)
        #expect(service.phase == .shortBreak)
        #expect(service.formattedTime == "05:00")

        service.setPhase(.focus)
        #expect(service.phase == .focus)
        #expect(service.formattedTime == "25:00")
    }

    @Test func dynamicTabSplitting() {
        SettingsKeys.registerDefaults()
        let battery = BatteryService()
        let clock = ClockService()
        let nowPlaying = NowPlayingService()
        let shelf = ShelfService()
        let pomodoro = PomodoroService()

        let vm = IslandViewModel(
            battery: battery,
            systemStats: SystemStatsService(),
            clock: clock,
            camera: CameraService(),
            shelf: shelf,
            projects: ProjectsService(),
            nowPlaying: nowPlaying,
            pomodoro: pomodoro
        )

        // With all tabs enabled (Home, Pomodoro, Camera, Shelf, Projects):
        // First 3 should be left ear: Home, Pomodoro, Camera
        // Remaining 2 should be right ear: Shelf, Projects
        #expect(vm.leftEarTabs.count <= 3)
        #expect(vm.leftEarTabs == [.home, .pomodoro, .camera])
        #expect(vm.rightEarTabs == [.shelf, .projects])
    }
}

import SwiftUI

/// Pomodoro timer tab: full focus/break cycles with progress ring and session tracking.
struct PomodoroTabView: View {
    @ObservedObject var pomodoro: PomodoroService

    private var accentColor: Color {
        switch pomodoro.phase {
        case .focus:
            return Color(red: 1.0, green: 0.35, blue: 0.3) // Tomato red / coral
        case .shortBreak:
            return Color(red: 0.3, green: 0.8, blue: 0.5) // Fresh green
        case .longBreak:
            return Color(red: 0.3, green: 0.6, blue: 1.0) // Relaxing blue
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Phase switcher pills
            HStack(spacing: 6) {
                ForEach(PomodoroPhase.allCases) { phase in
                    Button {
                        pomodoro.setPhase(phase)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: phase.symbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(phase.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(pomodoro.phase == phase ? accentColor.opacity(0.3) : .white.opacity(0.06))
                        )
                        .overlay(
                            Capsule().stroke(pomodoro.phase == phase ? accentColor.opacity(0.6) : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(pomodoro.phase == phase ? .white : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Main timer card
            HStack(spacing: 24) {
                // Circular Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 6)
                        .frame(width: 82, height: 82)

                    Circle()
                        .trim(from: 0, to: CGFloat(pomodoro.progress))
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 82, height: 82)
                        .animation(.easeInOut(duration: 0.25), value: pomodoro.progress)

                    VStack(spacing: 2) {
                        Text(pomodoro.formattedTime)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Text(statusLabel)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(statusColor)
                            .tracking(0.5)
                    }
                }

                // Controls & Cycle Stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Session")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))

                        HStack(spacing: 4) {
                            ForEach(0..<pomodoro.targetInterval, id: \.self) { idx in
                                let completedInCycle = pomodoro.completedSessions % pomodoro.targetInterval
                                Circle()
                                    .fill(idx < completedInCycle ? accentColor : .white.opacity(0.2))
                                    .frame(width: 7, height: 7)
                            }
                        }

                        Text("(\(pomodoro.completedSessions))")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    HStack(spacing: 12) {
                        // Play/Pause button
                        Button {
                            pomodoro.playPause()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: pomodoro.state == .running ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(pomodoro.state == .running ? "Pause" : (pomodoro.state == .paused ? "Resume" : "Start"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(accentColor)
                            )
                        }
                        .buttonStyle(.plain)

                        // Skip button
                        Button {
                            pomodoro.skip()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help(Text("Skip to next phase"))

                        // Reset button
                        Button {
                            pomodoro.reset()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help(Text("Reset timer"))
                    }

                    // Next phase label
                    Text(nextPhaseDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLabel: String {
        switch pomodoro.state {
        case .idle: return "READY"
        case .running: return "FOCUSING"
        case .paused: return "PAUSED"
        case .completed: return "DONE"
        }
    }

    private var statusColor: Color {
        switch pomodoro.state {
        case .idle: return .white.opacity(0.5)
        case .running: return accentColor
        case .paused: return .orange
        case .completed: return .green
        }
    }

    private var nextPhaseDescription: String {
        switch pomodoro.phase {
        case .focus:
            let nextCompleted = pomodoro.completedSessions + 1
            let isLong = (nextCompleted % pomodoro.targetInterval == 0)
            return "Next: \(isLong ? "Long Break (15m)" : "Short Break (5m)")"
        case .shortBreak, .longBreak:
            return "Next: Focus Session"
        }
    }
}

import SwiftUI

/// Two cyan rectangular eyes. Idle they wander through random expressions;
/// while music plays a compact headset appears and the robot bobs along,
/// with eyes tinted by the song's mood when one is known.
struct RobotBuddyView: View {
    /// 1 is the 36pt-tall design; smaller shrinks the eyes and headset.
    let scale: CGFloat
    let isListening: Bool
    /// Only tints the eyes; neutral keeps them cyan.
    let mood: LyricMood
    /// An ad is playing: red, smug eyes and a head held high.
    var isAngry = false
    /// A video that isn't music is playing: it watches, munching popcorn.
    var isWatching = false
    /// Nothing playing: wanders just outside this notch doing random little
    /// acts instead of the usual idle loop. The view then fills the area
    /// around the notch, its top center at the notch's top center.
    var peek: PeekArea?

    struct PeekArea {
        var notchSize: CGSize
        /// Screen point of the notch's top center, for eyeing the cursor.
        var notchTopCenter: CGPoint?
        /// The robot's scale, so it keeps clear of the notch at any size.
        var scale: CGFloat = 0.5
    }

    private var mode: Mode { Mode(isListening: isListening, isAngry: isAngry, mood: mood, isWatching: isWatching && isListening) }

    var body: some View {
        let mode = self.mode
        let interval: Double = peek != nil ? 1 / 20 : mode.active || RobotTransitions.shared.isChanging ? 1 / 24 : 1 / 15
        TimelineView(.animation(minimumInterval: interval)) { context in
          GeometryReader { geometry in
            let t = context.date.timeIntervalSinceReferenceDate
            let peeked = peek.map { RobotPeek.shared.frame(at: t, area: PeekArea(notchSize: $0.notchSize, notchTopCenter: $0.notchTopCenter, scale: scale)) }
            let frame = peeked?.frame ?? RobotTransitions.shared.frame(for: mode, at: t)
            let pose = frame.pose
            let shape = frame.shape

            ZStack {
            ZStack {
                EyesView(shape: shape, scale: scale)
                // On top, so a cup is never hidden behind an eye.
                HeadsetView(tint: shape.color, scale: scale, pulse: frame.pulse)
                    .opacity(frame.headset)
                    .offset(y: (1 - frame.headset) * -8 * scale)
                    .scaleEffect(0.6 + 0.4 * frame.headset)
                if let badge = frame.badge, frame.badgeAlpha > 0.02 {
                    // Beside the eyes, a little raised.
                    Text(verbatim: badge)
                        .font(.system(size: 18 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(shape.color)
                        .opacity(min(1, frame.badgeAlpha))
                        .offset(x: 25 * scale * frame.badgeSide, y: -8 * scale)
                }
            }
            .frame(width: Self.faceWidth * scale, height: peeked == nil ? nil : Self.peekFaceHeight * scale)
            .scaleEffect(x: 1 - (pose.squash - 1) * 0.5, y: pose.squash, anchor: .bottom)
            .rotationEffect(.degrees(pose.rotation))
            .offset(x: pose.x * scale, y: pose.y * scale)
            // Watching: the eyes rise to peek over the snacks.
            .offset(y: -Self.watchingLift(height: geometry.size.height, scale: scale) * scale * frame.snacks)
                if frame.snacks > 0.02 {
                    // In front of the eyes and held still while the head bobs.
                    SnacksView(scale: scale, t: t)
                        .frame(width: Self.faceWidth * scale)
                        .opacity(min(1, frame.snacks))
                        .offset(y: (1 - frame.snacks) * 6 * scale)
                }
            }
            // Puts the point between the eyes where the peek says it is.
            .offset(x: peeked?.position.x ?? 0, y: (peeked?.position.y ?? 0) - (peeked == nil ? 0 : Self.peekFaceHeight * scale * 0.56))
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: peeked == nil ? .center : .top)
          }
        }
    }

    /// Height of a peeking face in design points; the eyes sit at 0.56 of it.
    private static let peekFaceHeight: CGFloat = 48

    /// Width of the face including the headset, in design points.
    private static let faceWidth: CGFloat = 60
    /// Design points the eyes rise while watching, to peek over the snacks:
    /// eyes and snacks together are then centered in a view `height` tall.
    nonisolated static func watchingLift(height: CGFloat, scale: CGFloat) -> CGFloat {
        let h = height / scale
        // The eyes start at 0.56 of the height; the group spans 9 above them to 28 below.
        return h * 0.56 - (h / 2 - 9.5)
    }

    fileprivate static func frame(for mode: Mode, at t: Double) -> Frame {
        if mode.isWatching && !mode.isAngry { return Snacks.frame(at: t) }
        let vibe = mode.vibe
        let phase = t * vibe.bpm / 60
        let pose = self.pose(atBeat: phase, vibe: vibe)
        let shape = eyes(at: t, mode: mode, lookSway: pose.look)
        let frame = Frame(pose: pose, shape: shape, pulse: mode.hasHeadset ? abs(sin(.pi * phase)) : 0,
                          headset: mode.hasHeadset ? 1 : 0)
        return frame
    }

    // MARK: - Dancing

    /// Beats each move lasts before the next one takes over.
    private static let beatsPerMove = 4.0

    /// The head's pose at a beat: the current move, blended in from the
    /// previous one so the change reads as a transition, not a jump.
    private static func pose(atBeat beat: Double, vibe: Vibe) -> Pose {
        let moves = vibe.moves
        let segment = floor(beat / Self.beatsPerMove)
        let into = (beat - segment * Self.beatsPerMove) / (vibe.isIdle ? 1 : 0.5)
        let current = moves[Self.pick(Int(segment) &+ 7, count: moves.count)]
        let previous = moves[Self.pick(Int(segment) &+ 6, count: moves.count)]
        return previous.pose(at: beat, vibe: vibe).mixed(with: current.pose(at: beat, vibe: vibe), by: Self.ease(into))
    }

    // MARK: - Expressions

    private static func eyes(at t: Double, mode: Mode, lookSway: Double) -> EyeShape {
        let vibe = mode.vibe
        let length = mode.active ? 4 * 60 / vibe.bpm : 3.2
        let segment = floor(t / length)
        let into = (t - segment * length) / (mode.active ? 0.22 : 0.4)

        let list = vibe.expressions
        let current = list[Self.pick(Int(segment), count: list.count)]
        let previous = list[Self.pick(Int(segment) - 1, count: list.count)]
        var shape = previous.mixed(with: current, by: Self.ease(into))
        shape.lookX += lookSway
        if mode.active {
            // Keep the eyes between the headset's cups, wide ones included.
            let room = max(0, RobotLayout.eyeSpan - shape.width)
            shape.lookX = min(room, max(-room, shape.lookX))
        }
        (shape.red, shape.green, shape.blue) = mode.eyeColor
        return shape
    }

    // MARK: - Blinking

    private static let blinkWindow = 3.7

    /// Height multiplier for one quick blink starting `d` seconds ago.
    fileprivate static func blink(_ d: Double) -> Double {
        d >= 0 && d < 0.14 ? max(0.08, abs(d - 0.07) / 0.07) : 1
    }

    /// One blink at a random moment in every few seconds, sometimes a double.
    fileprivate static func blinkAmount(at t: Double) -> Double {
        let window = floor(t / blinkWindow)
        let local = t - window * blinkWindow
        let start = 0.3 + Double(pick(Int(window) &+ 11, count: 100)) / 100 * 2.9
        var amount = blink(local - start)
        if pick(Int(window) &+ 13, count: 4) == 0 { amount = min(amount, blink(local - start - 0.22)) }
        return amount
    }

    /// Cheap deterministic hash so a segment always picks the same entry.
    fileprivate nonisolated static func pick(_ index: Int, count: Int) -> Int {
        var x = UInt64(bitPattern: Int64(index)) &* 6364136223846793005 &+ 1442695040888963407
        x ^= x >> 29
        return Int(x % UInt64(count))
    }

    nonisolated static func ease(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}

/// What the robot is reacting to; a change sets off a double take.
private struct Mode: Equatable {
    var isListening: Bool
    var isAngry: Bool
    var mood: LyricMood
    var isWatching = false

    var active: Bool { isListening || isAngry }
    var vibe: Vibe { isAngry ? .smug : isListening ? .make(mood) : .idle }
    /// The headset is for music; popcorn replaces it for videos.
    var hasHeadset: Bool { isListening && !isWatching && !isAngry }

    var eyeColor: (Double, Double, Double) {
        if isAngry { return (1, 0.1, 0.08) }
        return isListening && !isWatching && mood != .neutral ? mood.eyeColor : (0.2, 0.95, 1)
    }
}

/// Everything drawn for one moment; blends linearly between two.
private struct Frame {
    var pose: Pose
    var shape: EyeShape
    /// Headset cup pulse, 0...1.
    var pulse: Double
    /// How far the headset is on, 0...1.
    var headset: Double
    /// A little symbol above the eyes — "?", "!", "♥", "z" — and how visible it is.
    var badge: String? = nil
    var badgeAlpha = 0.0
    /// Which side of the eyes the badge floats on: away from the notch.
    var badgeSide = 1.0
    /// How far the soda and popcorn are in hand, 0...1.
    var snacks = 0.0

    func mixed(with other: Frame, by f: Double) -> Frame {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        let a = badge == nil ? 0 : badgeAlpha, b = other.badge == nil ? 0 : other.badgeAlpha
        return Frame(pose: pose.mixed(with: other.pose, by: f), shape: shape.mixed(with: other.shape, by: f),
                     pulse: m(pulse, other.pulse), headset: m(headset, other.headset),
                     badge: f < 0.5 ? badge ?? other.badge : other.badge ?? badge, badgeAlpha: m(a, b),
                     badgeSide: f < 0.5 ? badgeSide : other.badgeSide, snacks: m(snacks, other.snacks))
    }

    func blinking(at t: Double) -> Frame {
        var frame = self
        frame.shape.height *= RobotBuddyView.blinkAmount(at: t)
        return frame
    }
}

/// Remembers recent mode changes outside any one view: the island rebuilds
/// the robot whenever the lyric strip comes or goes, which is exactly when an
/// ad starts or a song changes, so view state would forget the change.
@MainActor
private final class RobotTransitions {
    static let shared = RobotTransitions()

    /// Seconds of the "huh?" double take: it freezes mid-move, eyes wide,
    /// glancing aside, then blinks twice as if checking it saw right.
    private static let noticeLength = 1.0
    /// When, into the double take, the old mode starts fading out.
    private static let blendStart = 0.7
    /// Seconds pose, expression, color and headset take to settle.
    private static let blendLength = 2.2
    /// Seconds the eye color takes: slower than the rest, so it drifts.
    private static let colorLength = 4.0

    /// Each mode the robot has switched to and when; the first is fully settled.
    private var layers: [(mode: Mode, start: Double)] = []

    var isChanging: Bool { layers.count > 1 }

    func frame(for mode: Mode, at t: Double) -> Frame {
        if layers.last?.mode != mode { layers.append((mode, t)) }
        // Once a change has fully settled, everything before it is hidden.
        if let settled = layers.lastIndex(where: { t - $0.start >= Self.blendStart + max(Self.blendLength, Self.colorLength) }), settled > 0 {
            layers.removeFirst(settled)
        }
        return frame(upTo: layers.count - 1, at: t).blinking(at: t)
    }

    private func frame(upTo index: Int, at t: Double) -> Frame {
        let layer = layers[index]
        let target = RobotBuddyView.frame(for: layer.mode, at: t)
        guard index > 0 else { return target }

        let elapsed = t - layer.start
        // What it was doing, frozen the moment it noticed.
        let before = frame(upTo: index - 1, at: min(t, layer.start))
        var blended = before.mixed(with: target, by: RobotBuddyView.ease((elapsed - Self.blendStart) / Self.blendLength))
        let color = RobotBuddyView.ease((elapsed - Self.blendStart) / Self.colorLength)
        blended.shape.red = before.shape.red + (target.shape.red - before.shape.red) * color
        blended.shape.green = before.shape.green + (target.shape.green - before.shape.green) * color
        blended.shape.blue = before.shape.blue + (target.shape.blue - before.shape.blue) * color

        // Rises quickly, holds, then eases off over the double take.
        let x = min(1, max(0, elapsed / Self.noticeLength))
        let surprise = x < 0.25 ? RobotBuddyView.ease(x / 0.25) : 1 - RobotBuddyView.ease((x - 0.6) / 0.4)
        var startled = EyeShape.surprised
        (startled.red, startled.green, startled.blue) = (blended.shape.red, blended.shape.green, blended.shape.blue)
        startled.lookX = RobotBuddyView.pick(Int(layer.start), count: 2) == 0 ? -2.5 : 2.5
        blended.shape = blended.shape.mixed(with: startled, by: surprise * 0.85)
        blended.pose.y -= 1.5 * surprise
        blended.pose.squash += 0.06 * surprise
        blended.pose.rotation *= 1 - surprise * 0.7

        let blinkAt = Self.noticeLength * 0.6
        blended.shape.height *= min(RobotBuddyView.blink(elapsed - blinkAt), RobotBuddyView.blink(elapsed - blinkAt - 0.22))
        return blended
    }
}

/// Lets the window controller find the peeking robot on screen and poke it.
@MainActor
enum PeekingRobotTouch {
    /// True when the robot is on screen, out of the notch, under `point`.
    static func contains(_ point: CGPoint) -> Bool {
        RobotPeek.shared.hitRect?.contains(point) ?? false
    }

    static func poke() { RobotPeek.shared.poke() }
}

/// The idle robot loitering just outside the notch. Every few seconds it
/// picks a new act at random — eyeing the cursor, blushing, vibing to
/// nothing, dozing off, ducking into the notch for a moment, walking along
/// its edge to somewhere else — and blends into it. Poked, it reacts.
@MainActor
private final class RobotPeek {
    static let shared = RobotPeek()

    private enum Act: CaseIterable {
        case rest, glance, followCursor, suspicious, blush, vibe, sleepy, surprised
        case hide, walk, leanOut, giggle, lookUp
        // Reactions to a poke, never picked on their own.
        case angry, happy, confused, love, startled

        static let reactions: [Act] = [.angry, .happy, .confused, .love, .startled, .blush]

        var weight: Double {
            switch self {
            case .rest: 2.2
            case .followCursor: 2.6
            case .walk: 2.4
            case .glance, .vibe: 1.5
            case .blush, .leanOut: 1.2
            case .suspicious, .giggle, .lookUp, .hide: 1
            case .sleepy: 0.9
            case .surprised: 0.7
            case .angry, .happy, .confused, .love, .startled: 0
            }
        }

        var duration: ClosedRange<Double> {
            switch self {
            case .rest: 2.5...6
            case .glance: 1.8...3.5
            case .followCursor: 4...9
            case .suspicious: 2.5...4
            case .blush: 2.5...4
            case .vibe: 4...8
            case .sleepy: 5...9
            case .surprised: 1.4...2
            case .hide: 1.6...3
            case .walk: 1.2...6 // Set from the distance walked.
            case .leanOut: 2.5...4
            case .giggle: 1.8...2.6
            case .lookUp: 2...3.5
            case .angry: 2...2.6
            case .happy, .love: 1.8...2.4
            case .confused: 2.2...3
            case .startled: 1.4...1.8
            }
        }

        /// Eye color for the mood.
        var tint: (Double, Double, Double) {
            switch self {
            case .angry: (1, 0.22, 0.16)
            case .happy, .giggle, .vibe: (1, 0.85, 0.3)
            case .blush, .love: (1, 0.5, 0.78)
            case .confused: (0.72, 0.55, 1)
            case .sleepy: (0.4, 0.55, 1)
            case .suspicious: (1, 0.6, 0.22)
            case .surprised, .startled: (0.85, 1, 1)
            default: (0.2, 0.95, 1)
            }
        }
    }

    /// The path it walks around the notch: down the left side, round the
    /// corner, along the bottom and up the right side, just far enough out
    /// that not even the eyes' glow touches the notch. Places on it are
    /// fractions of its length, 0...1.
    private struct Outline {
        let notch: CGSize
        let scale: CGFloat
        let points: [CGPoint]
        /// Running length up to each point.
        let lengths: [Double]

        init(notch: CGSize, scale: CGFloat) {
            self.notch = notch
            self.scale = scale
            let w = notch.width / 2, h = notch.height
            // Half the face plus a hair, sideways and downward.
            let side = 24 * scale, below = 16 * scale
            points = [
                CGPoint(x: -w - side, y: h * 0.3), CGPoint(x: -w - side, y: h - 3),
                CGPoint(x: -w - side * 0.7, y: h + below * 0.8), CGPoint(x: -w + 10, y: h + below),
                CGPoint(x: w - 10, y: h + below), CGPoint(x: w + side * 0.7, y: h + below * 0.8),
                CGPoint(x: w + side, y: h - 3), CGPoint(x: w + side, y: h * 0.3),
            ]
            var running = [0.0]
            for i in 1..<points.count {
                running.append(running[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            lengths = running
        }

        var total: Double { lengths.last ?? 1 }
        private func fraction(_ index: Int) -> Double { lengths[index] / total }

        func point(at u: Double) -> CGPoint {
            let d = min(1, max(0, u)) * total
            for i in 1..<points.count where d <= lengths[i] || i == points.count - 1 {
                let span = lengths[i] - lengths[i - 1]
                let f = span > 0 ? (d - lengths[i - 1]) / span : 0
                return CGPoint(x: points[i - 1].x + (points[i].x - points[i - 1].x) * f,
                               y: points[i - 1].y + (points[i].y - points[i - 1].y) * f)
            }
            return points[0]
        }

        /// Somewhere inside the notch, for ducking into it from `point`.
        func inside(from point: CGPoint) -> CGPoint {
            let w = notch.width / 2 - 32 * scale
            return CGPoint(x: min(w, max(-w, point.x)), y: notch.height * 0.4)
        }

        /// A random place, half the time along the bottom, else on a side,
        /// at least a short walk from `current`.
        func randomSpot(avoiding current: Double? = nil) -> Double {
            var u: Double
            var tries = 0
            repeat {
                let roll = Double.random(in: 0..<1)
                u = roll < 0.25 ? .random(in: 0...fraction(1))
                    : roll < 0.5 ? .random(in: fraction(6)...1)
                    : .random(in: fraction(3)...fraction(4))
                tries += 1
            } while tries < 20 && current.map { abs($0 - u) * total < 40 } ?? false
            return u
        }
    }

    /// Seconds a new act takes to blend in from where the last one left off.
    private static let blendLength = 0.45
    /// Points per second it walks.
    private static let walkSpeed = 45.0

    private var act: Act = .rest
    private var start = 0.0
    private var end = 0.0
    private var outline = Outline(notch: CGSize(width: 200, height: 32), scale: 0.5)
    /// Where it stands on the outline, and where a walk ends up.
    private var spot = 0.5
    private var target = 0.5
    /// Where it was on the outline in the last frame, and how far ducked in.
    private var currentU = 0.5
    private var depth = 0.0
    /// Moving or glancing right (+1) or left (-1).
    private var heading = 1.0
    /// Per-act dice: which side it leans to, how fast it vibes.
    private var side = 1.0
    private var bpm = 100.0
    /// The last frame drawn, and where the current act blends in from.
    private var last: Frame?
    private var from: Frame?
    /// Smoothed glance toward the cursor, in design points.
    private var look = (x: 0.0, y: 0.0)
    private var lastT = 0.0
    private var recentPokes: [Double] = []
    /// Screen rect that counts as touching it, when it's out and drawn.
    private(set) var hitRect: CGRect?

    func frame(at t: Double, area: RobotBuddyView.PeekArea) -> (frame: Frame, position: CGPoint) {
        if outline.notch != area.notchSize || outline.scale != area.scale {
            outline = Outline(notch: area.notchSize, scale: area.scale)
        }
        // Back after a long time hidden: start calm, somewhere new.
        if t - lastT > 2 {
            spot = outline.randomSpot()
            begin(.rest, at: t, blendFrom: nil)
        }
        let dt = min(0.2, max(0, t - lastT))
        lastT = t
        if t >= end {
            if act == .walk { spot = target }
            begin(next(), at: t, blendFrom: last)
        }

        let elapsed = t - start, length = end - start
        let place = position(elapsed: elapsed, length: length)
        let screen = area.notchTopCenter.map { CGPoint(x: $0.x + place.x, y: $0.y - place.y) }
        hitRect = depth < 0.4 ? screen.map { CGRect(x: $0.x - 28 * area.scale, y: $0.y - 20 * area.scale, width: 56 * area.scale, height: 40 * area.scale) } : nil
        trackCursor(from: screen, dt: dt)

        var frame = frame(for: act, elapsed: elapsed, length: length)
        if let from {
            frame = from.mixed(with: frame, by: RobotBuddyView.ease(elapsed / Self.blendLength))
        }
        last = frame
        return (frame.blinking(at: t), place)
    }

    /// Clicked: a random reaction, but woken from a nap, or poked again and
    /// again, it gets angry.
    func poke() {
        let t = Date().timeIntervalSinceReferenceDate
        guard t - lastT < 1 else { return }
        let asleep = act == .sleepy && t < end - 0.7
        recentPokes = recentPokes.filter { t - $0 < 3 } + [t]
        let reaction: Act = asleep || recentPokes.count >= 4
            ? .angry
            : Act.reactions.filter { $0 != act }.randomElement() ?? .happy
        // A walk stops where it is.
        spot = currentU
        begin(reaction, at: t, blendFrom: last)
    }

    private func next() -> Act {
        let options = Act.allCases.filter { $0 != act && $0.weight > 0 }
        var roll = Double.random(in: 0..<options.reduce(0) { $0 + $1.weight })
        for option in options {
            roll -= option.weight
            if roll < 0 { return option }
        }
        return .rest
    }

    private func begin(_ act: Act, at t: Double, blendFrom frame: Frame?) {
        self.act = act
        start = t
        end = t + Double.random(in: act.duration)
        side = Bool.random() ? 1 : -1
        bpm = Double.random(in: 88...124)
        if act == .walk {
            target = outline.randomSpot(avoiding: spot)
            let distance = abs(target - spot) * outline.total
            end = t + min(6, max(1.2, distance / Self.walkSpeed))
        }
        from = frame
    }

    /// Where it is during the current act, relative to the notch's top
    /// center, y down. Every act starts and ends at its spot, fully out, so
    /// switching acts never jumps.
    private func position(elapsed e: Double, length: Double) -> CGPoint {
        let ease = RobotBuddyView.ease
        let p = length > 0 ? min(1, e / length) : 1
        var u = spot
        var hop = 0.0
        depth = 0

        switch act {
        case .walk:
            // Walks along the edge with a little hop in each step.
            u = spot + (target - spot) * ease(p)
            let walked = abs(u - spot) * outline.total
            hop = 1.3 * abs(sin(.pi * walked / 7)) * ease(e / 0.2) * ease((length - e) / 0.2)
        case .hide:
            // Ducks into the notch, waits a moment, peeks back out.
            depth = ease(p / 0.25) * (1 - ease((p - 0.65) / 0.3))
        default:
            break
        }
        currentU = u

        var point = outline.point(at: u)
        let ahead = outline.point(at: u + (act == .walk && target < spot ? -0.01 : 0.01))
        if act == .walk, abs(ahead.x - point.x) > 0.3 { heading = ahead.x > point.x ? 1 : -1 }
        point.y -= hop

        let inside = outline.inside(from: point)
        if act == .leanOut {
            // Leans a little further out to look around.
            let out = ease(e / 0.5) * ease((length - e) / 0.5)
            let dx = point.x - inside.x, dy = point.y - inside.y, d = max(1, hypot(dx, dy))
            point.x += dx / d * 4 * out
            point.y += dy / d * 4 * out
        }
        return CGPoint(x: point.x + (inside.x - point.x) * depth, y: point.y + (inside.y - point.y) * depth)
    }

    private func trackCursor(from anchor: CGPoint?, dt: Double) {
        var target = (x: 0.0, y: 0.0)
        if let anchor {
            let mouse = NSEvent.mouseLocation
            // Screen y grows upward; the eyes' y grows downward.
            let dx = mouse.x - anchor.x, dy = anchor.y - mouse.y
            target = (3.5 * dx / (abs(dx) + 160), 3 * dy / (abs(dy) + 120))
        }
        let k = min(1, dt * 7)
        look.x += (target.x - look.x) * k
        look.y += (target.y - look.y) * k
    }

    private func frame(for act: Act, elapsed e: Double, length: Double) -> Frame {
        let ease = RobotBuddyView.ease
        let p = length > 0 ? min(1, e / length) : 1
        // Eases in over the first part and back out over the last.
        let hold = ease(e / 0.5) * ease((length - e) / 0.5)
        // Away from the notch: toward the screen on a side, either way below it.
        let here = outline.point(at: currentU)
        let outward: Double = here.x < -outline.notch.width / 2 ? -1 : here.x > outline.notch.width / 2 ? 1 : side
        var shape = EyeShape.neutral
        var pose = Pose()
        var badge: String?
        var badgeAlpha = 0.0

        switch act {
        case .rest:
            let breath = 0.5 + 0.5 * sin(e * 1.7)
            pose = Pose(y: -0.6 * breath, squash: 1 + 0.025 * breath)

        case .glance:
            shape.lookX = 3 * side
            shape.lookY = side > 0 ? 0.5 : -1
            pose = Pose(x: side * 1.2, rotation: side * 3 * hold)

        case .followCursor:
            shape = EyeShape(width: 12.5, height: 16)
            shape.lookX = look.x
            shape.lookY = look.y
            pose = Pose(x: look.x * 0.5, rotation: look.x * 1.2)

        case .suspicious:
            shape = .suspicious
            shape.lookX = look.x
            shape.lookY = look.y
            pose = Pose(x: look.x * 0.4, rotation: -side * 5 * hold, squash: 1 - 0.03 * hold)

        case .blush:
            shape = EyeShape(height: 13, lookX: 2 * side, lookY: 1.5, cheek: 0.85, blush: 1)
            // A shy little wiggle when it starts, then it leans away.
            let wiggle = 3 * sin(e * 14) * max(0, 1 - e / 0.8)
            pose = Pose(y: 0.5 * hold, rotation: side * 7 * hold + wiggle, squash: 0.97)

        case .vibe:
            let beat = e * bpm / 60
            let s = sin(.pi * beat)
            shape = Int(beat / 4) % 2 == 0
                ? EyeShape(height: 13, lid: 0.25, cheek: 0.5)
                : EyeShape(height: 14, cheek: 0.8)
            shape.lookX = 1.5 * s
            pose = Pose(x: 1.5 * s * hold, y: -2.2 * abs(s) * hold, rotation: 6 * s * hold,
                        squash: 1 + 0.04 * abs(s) * hold)
            badge = Int(beat / 2) % 2 == 0 ? "♪" : "♫"
            badgeAlpha = hold * 0.9

        case .sleepy:
            // Lids droop, the head nods off... then it jolts awake.
            let wake = ease((e - (length - 0.7)) / 0.15)
            let doze = ease(e / 2.5)
            let nod = 0.5 + 0.5 * sin(e * 1.2)
            var asleep = EyeShape(height: 15, lookY: 1, lid: 0.45 + 0.4 * doze)
            asleep.lookX = -side
            var awake = EyeShape.surprised
            awake.lookX = 2 * side
            shape = asleep.mixed(with: awake, by: wake)
            let drowsy = Pose(y: 1.2 * doze + 0.6 * nod * doze, rotation: side * 9 * doze, squash: 1 - 0.04 * doze)
            pose = drowsy.mixed(with: Pose(y: -1.5, squash: 1.06), by: wake)
            badge = wake > 0.5 ? "!" : "z"
            badgeAlpha = wake > 0.5 ? 1 - ease((e - length + 0.4) / 0.4) : ease((e - 1.5) / 1) * (0.55 + 0.45 * sin(e * 2.2))

        case .surprised:
            shape = .surprised
            shape.lookX = look.x
            let pop = ease(e / 0.15) * (1 - ease((e - 0.4) / 0.6))
            pose = Pose(y: -2.5 * pop, squash: 1 + 0.08 * pop)
            badge = "!"
            badgeAlpha = pop

        case .hide:
            // Wary going in, curious coming back out.
            shape = p < 0.5 ? EyeShape.suspicious : EyeShape(width: 12.5, height: 16)
            shape.lookX = 2.5 * outward

        case .walk:
            shape = EyeShape(height: 14, cheek: 0.3)
            shape.lookX = 2.5 * heading
            pose = Pose(rotation: 4 * heading * hold)

        case .leanOut:
            shape = EyeShape(width: 12.5, height: 16.5)
            shape.lookX = 1 + 2.5 * sin(e * 2.4)
            shape.lookY = 0.8 * sin(e * 1.3)
            pose = Pose(rotation: 4 * hold * sin(e * 1.2))

        case .giggle:
            shape = EyeShape(height: 14, cheek: 0.95, blush: 0.4)
            let hop = abs(sin(e * 2 * .pi * 2.2)) * hold
            pose = Pose(y: -1.6 * hop, rotation: 3 * sin(e * 13) * hold, squash: 1 + 0.05 * hop)

        case .lookUp:
            shape = .lookUp
            shape.lookX = 2 * outward
            pose = Pose(x: outward, y: -0.8 * hold, rotation: outward * 5 * hold)

        case .angry:
            // Fumes and shakes, glaring at whoever poked it.
            shape = EyeShape(width: 13, height: 14, brow: 0.8)
            shape.lookX = look.x
            shape.lookY = look.y
            let shake = max(0, 1 - e / 1.2)
            pose = Pose(x: 2.5 * sin(e * 45) * shake, y: -1.2 * ease(e / 0.12) * (1 - ease((e - 0.3) / 0.3)),
                        rotation: 4 * sin(e * 38) * shake, squash: 0.95)
            badge = "💢"
            badgeAlpha = hold * (0.75 + 0.25 * sin(e * 9))

        case .happy:
            shape = EyeShape(height: 14, cheek: 0.95, blush: 0.3)
            let hop = abs(sin(e * 2 * .pi * 1.8)) * hold
            pose = Pose(y: -2.5 * hop, rotation: 4 * side * sin(e * 6) * hold, squash: 1 + 0.06 * hop)
            badge = "♪"
            badgeAlpha = hold

        case .confused:
            // Head cocked, eyes up, slowly tilting the other way.
            shape = EyeShape(height: 14, lookX: 2 * side, lookY: -1.5, brow: -0.35)
            pose = Pose(rotation: 12 * hold * (e < length * 0.55 ? side : -side))
            badge = "?"
            badgeAlpha = hold * (0.8 + 0.2 * sin(e * 5))

        case .love:
            shape = EyeShape(width: 13, height: 15, cheek: 0.7, blush: 1)
            let beat = abs(sin(e * 7)) * hold
            pose = Pose(y: -1 * hold, squash: 1 + 0.06 * beat)
            badge = "♥"
            badgeAlpha = hold * (0.7 + 0.3 * beat)

        case .startled:
            shape = EyeShape(width: 11, height: 21, lookY: -1)
            let jump = ease(e / 0.1) * (1 - ease((e - 0.25) / 0.5))
            pose = Pose(y: -4 * jump, squash: 1 + 0.1 * jump)
            badge = "!"
            badgeAlpha = 1 - ease((e - 0.8) / 0.6)
        }
        (shape.red, shape.green, shape.blue) = act.tint
        return Frame(pose: pose, shape: shape, pulse: 0, headset: 0, badge: badge, badgeAlpha: badgeAlpha,
                     badgeSide: here.x < -outline.notch.width / 2 ? -1 : 1)
    }
}

/// How the robot moves to a song of each mood.
private struct Vibe {
    var bpm: Double
    /// Design-size points the head hops.
    var bob: CGFloat
    /// Degrees of head tilt, alternating each beat.
    var sway: Double
    var expressions: [EyeShape]
    /// Moves it cycles through, one every few beats.
    var moves: [Move]
    /// Nothing playing: moves blend in slower.
    var isIdle = false

    /// Nothing playing: mostly still, now and then a slow breath, a curious
    /// tilt or a peek to the side.
    static let idle = Vibe(bpm: 24, bob: 0.8, sway: 3,
                           expressions: [.neutral, .neutral, .neutral, .lookLeft, .lookRight, .lookUp, .happy, .sleepy, .surprised, .suspicious],
                           moves: [.rest, .rest, .breathe, .breathe, .curious, .peek], isIdle: true)

    /// Ads: smug. Slow, chin up, looking down its nose with a smirk.
    static let smug = Vibe(bpm: 60, bob: 1, sway: 4, expressions: [.smug, .smugAside, .smug, .smugOther],
                           moves: [.smug, .smug, .tilt])

    static func make(_ mood: LyricMood) -> Vibe {
        switch mood {
        // Slow and chill: lazy tilts and swirls with soft, content eyes.
        case .calm:
            Vibe(bpm: 66, bob: 1.2, sway: 4, expressions: [.relaxed, .relaxed, .neutral, .relaxed],
                 moves: [.tilt, .swirl, .sway, .look, .tilt])
        // Headbanging: fast, hard hops and a scowl.
        case .intense:
            Vibe(bpm: 140, bob: 4.5, sway: 2, expressions: [.angry, .angry, .suspicious, .angry],
                 moves: [.headbang, .headbang, .wiggle, .doubleBounce, .headbang, .squash])
        case .upbeat, .neutral:
            Vibe(bpm: 100, bob: 3, sway: 3, expressions: [.happy, .happy, .neutral, .happy, .wide],
                 moves: [.bounce, .sway, .sideStep, .squash, .swirl, .doubleBounce, .wiggle, .look])
        }
    }
}

/// The head's offset (in design points, up is negative), tilt, squash and
/// where the eyes glance.
private struct Pose {
    var x = 0.0, y = 0.0, rotation = 0.0, squash = 1.0, look = 0.0
    static let rest = Pose()

    func mixed(with other: Pose, by f: Double) -> Pose {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return Pose(x: m(x, other.x), y: m(y, other.y), rotation: m(rotation, other.rotation),
                    squash: m(squash, other.squash), look: m(look, other.look))
    }
}

private enum Move {
    case bounce, doubleBounce, sway, sideStep, squash, swirl, wiggle, tilt, look, headbang, smug
    case rest, breathe, curious, peek

    func pose(at beat: Double, vibe: Vibe) -> Pose {
        let a = Double(vibe.bob), r = vibe.sway
        let s = sin(.pi * beat)
        let hop = abs(s)
        // Rises from 0 to 1 and back over the move's four beats.
        let swell = sin(.pi * beat / 4).magnitude
        switch self {
        case .rest:
            return Pose()
        case .breathe:
            return Pose(y: -a * 0.5 * swell, squash: 1 + 0.04 * swell)
        case .curious:
            // Head cocked one way, then slowly back.
            return Pose(y: -a * 0.3 * swell, rotation: r * 2.5 * swell * (sin(.pi * beat / 8) < 0 ? -1 : 1))
        case .peek:
            return Pose(x: 1.5 * sin(.pi * beat / 4), look: 3 * sin(.pi * beat / 4))
        case .bounce:
            return Pose(y: -a * hop)
        case .doubleBounce:
            return Pose(y: -a * 0.8 * abs(sin(2 * .pi * beat)))
        case .sway:
            return Pose(x: 1.2 * s, y: -a * 0.4 * hop, rotation: r * 1.2 * s)
        case .sideStep:
            return Pose(x: 3 * s, y: -a * 0.3 * hop, rotation: 2 * s)
        case .squash:
            return Pose(y: -a * hop, squash: 0.9 + 0.12 * hop)
        case .swirl:
            return Pose(x: 2.5 * cos(.pi * beat), y: -a * 0.6 * s, rotation: r * 0.5 * cos(.pi * beat))
        case .wiggle:
            return Pose(y: -a * 0.4 * hop, rotation: r * 1.2 * sin(4 * .pi * beat))
        case .tilt:
            return Pose(y: -a * 0.3 * hop, rotation: r * 1.6 * sin(.pi * beat / 2))
        case .look:
            return Pose(y: -a * 0.4 * hop, look: 3 * sin(.pi * beat / 2))
        case .smug:
            // Chin lifted and tipped back, drifting slowly side to side.
            return Pose(x: 1.5 * sin(.pi * beat / 4), y: -a * 0.6, rotation: -r * 0.8 + r * 0.4 * sin(.pi * beat / 4))
        case .headbang:
            // Down on the beat, tipping forward.
            return Pose(y: a * 0.7 * hop, rotation: 3 * hop)
        }
    }
}

private extension LyricMood {
    /// Eye color: the first color of the lyric gradient, as red, green, blue.
    var eyeColor: (Double, Double, Double) {
        let c = NSColor(colors[0]).usingColorSpace(.sRGB) ?? .white
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
}

// MARK: - Eyes

/// Everything that makes up one expression; blends linearly between two.
private nonisolated struct EyeShape {
    var width: Double = 12
    var height: Double = 15
    var lookX: Double = 0
    var lookY: Double = 0
    /// Slant of the top edge: positive is angry, negative is sad.
    var brow: Double = 0
    /// How far the top lid is closed.
    var lid: Double = 0
    /// How far the bottom rises into a smiling arch.
    var cheek: Double = 0
    /// Rosy cheeks on their own, without the smile: 0...1.
    var blush: Double = 0
    var red: Double = 0.2
    var green: Double = 0.95
    var blue: Double = 1

    var color: Color { Color(red: red, green: green, blue: blue) }

    static let neutral = EyeShape()
    static let wide = EyeShape(width: 13, height: 18)
    static let surprised = EyeShape(width: 11, height: 20, lookY: -1)
    static let lookLeft = EyeShape(lookX: -3)
    static let lookRight = EyeShape(lookX: 3)
    static let lookUp = EyeShape(lookX: 2, lookY: -3)
    static let happy = EyeShape(cheek: 0.9)
    static let sleepy = EyeShape(height: 15, lid: 0.55)
    /// Chill: a gentle smile and slightly lowered lids.
    static let relaxed = EyeShape(height: 13, lid: 0.25, cheek: 0.45)
    static let angry = EyeShape(height: 14, brow: 0.7)
    /// Smug: heavy lids, a faint smirk and a glance down.
    static let smug = EyeShape(height: 14, lookY: 1.5, brow: 0.2, lid: 0.4, cheek: 0.3)
    static let smugAside = EyeShape(height: 14, lookX: 2.5, lookY: 1, brow: 0.2, lid: 0.42, cheek: 0.3)
    static let smugOther = EyeShape(height: 14, lookX: -2.5, lookY: 1, brow: 0.2, lid: 0.42, cheek: 0.3)
    static let suspicious = EyeShape(height: 12, brow: 0.35, lid: 0.25)
    /// Watching a video: big and round, a little down toward the screen.
    static let watching = EyeShape(width: 13.5, height: 18, lookY: 1)

    func mixed(with other: EyeShape, by f: Double) -> EyeShape {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return EyeShape(
            width: m(width, other.width), height: m(height, other.height),
            lookX: m(lookX, other.lookX), lookY: m(lookY, other.lookY),
            brow: m(brow, other.brow), lid: m(lid, other.lid), cheek: m(cheek, other.cheek),
            blush: m(blush, other.blush),
            red: m(red, other.red), green: m(green, other.green), blue: m(blue, other.blue)
        )
    }
}

/// Positions shared by the eyes and the headset.
private nonisolated struct RobotLayout {
    let size: CGSize
    let scale: CGFloat
    var centerX: CGFloat { size.width / 2 }
    var centerY: CGFloat { size.height * 0.56 }
    /// Eyes sit close together, which reads cuter.
    var gap: CGFloat { 9 * scale }
    /// Design points an eye plus its sideways shift may span, from the
    /// middle of the face past half the gap, before touching a cup: the cup's
    /// inner edge is 20 out (4.5 + 13 + 2.5), less 4.5 and a point of room.
    static let eyeSpan = 14.5
}

// The face is drawn with plain shapes in a frame only as wide as the face
// itself. A full-width Canvas that is rotated and offset every frame
// occasionally dropped one side of the headset.

private struct EyesPath: Shape {
    let shape: EyeShape
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        let layout = RobotLayout(size: rect.size, scale: scale)
        let s = scale
        let w = shape.width * s, h = shape.height * s
        var path = Path()

        for side in [-1.0, 1.0] {
            let x = layout.centerX + side * (layout.gap / 2 + w / 2) - w / 2 + shape.lookX * s
            let y = layout.centerY - h / 2 + shape.lookY * s
            var eye = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 4.5 * s)

            // Top lid and slanted brow cut away the upper part.
            let inner = side < 0 ? x + w : x
            let outer = side < 0 ? x : x + w
            let outerDrop = h * (max(0, -shape.brow) * 0.7 + shape.lid)
            let innerDrop = h * (max(0, shape.brow) * 0.7 + shape.lid)
            if outerDrop > 0.1 || innerDrop > 0.1 {
                // Overshoot both sides so the cut leaves no sliver at the edges.
                let outerX = outer + (side < 0 ? -2 : 2)
                let innerX = inner + (side < 0 ? 2 : -2)
                var cut = Path()
                cut.move(to: CGPoint(x: outerX, y: y - 2))
                cut.addLine(to: CGPoint(x: innerX, y: y - 2))
                cut.addLine(to: CGPoint(x: innerX, y: y + innerDrop))
                cut.addLine(to: CGPoint(x: outerX, y: y + outerDrop))
                cut.closeSubpath()
                eye = eye.subtracting(cut)
            }

            // A rising circle turns the bottom into a smiling arch.
            if shape.cheek > 0.02 {
                let r = w * 0.8
                let cy = y + h + r - shape.cheek * h * 0.6
                eye = eye.subtracting(Path(ellipseIn: CGRect(x: x + w / 2 - r, y: cy - r, width: r * 2, height: r * 2)))
            }
            path.addPath(eye)
        }
        return path
    }
}

/// Rosy cheeks under the eyes.
private struct BlushPath: Shape {
    let shape: EyeShape
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        let layout = RobotLayout(size: rect.size, scale: scale)
        let s = scale
        let w = shape.width * s, h = shape.height * s
        var path = Path()
        for side in [-1.0, 1.0] {
            let x = layout.centerX + side * (layout.gap / 2 + w + 3 * s) + shape.lookX * s
            let y = layout.centerY + h / 2 + 2 * s + shape.lookY * s
            path.addEllipse(in: CGRect(x: x - 3.5 * s, y: y, width: 7 * s, height: 3.5 * s))
        }
        return path
    }
}

/// A little shine that makes the eyes look alive.
private struct ShinePath: Shape {
    let shape: EyeShape
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        let layout = RobotLayout(size: rect.size, scale: scale)
        let s = scale
        let w = shape.width * s, h = shape.height * s
        var path = Path()
        for side in [-1.0, 1.0] {
            let x = layout.centerX + side * (layout.gap / 2 + w / 2) + shape.lookX * s + w * 0.17
            let y = layout.centerY - h / 2 + shape.lookY * s + h * 0.2
            path.addEllipse(in: CGRect(x: x - 1.6 * s, y: y, width: 3.2 * s, height: 3.2 * s))
        }
        return path
    }
}

private struct EyesView: View {
    let shape: EyeShape
    let scale: CGFloat

    var body: some View {
        let blush = min(0.9, max(shape.cheek * 0.55, shape.blush * 0.9))
        let shine = max(0, 1 - shape.cheek * 1.6 - shape.lid * 1.5 - abs(shape.brow)) * min(1, shape.height / 12)
        ZStack {
            BlushPath(shape: shape, scale: scale)
                .fill(Color(red: 1, green: 0.45, blue: 0.6).opacity(blush > 0.05 ? blush : 0))
            // The glow is a few widening, fading outlines rather than a blur
            // or shadow: those render into an offscreen buffer that, as the
            // eyes change shape, sometimes stayed too small and clipped an eye.
            ForEach([(9.0, 0.07), (6.0, 0.12), (3.0, 0.22)], id: \.0) { width, opacity in
                EyesPath(shape: shape, scale: scale)
                    .stroke(shape.color.opacity(opacity), style: StrokeStyle(lineWidth: width * scale, lineJoin: .round))
            }
            EyesPath(shape: shape, scale: scale)
                .fill(shape.color)
            ShinePath(shape: shape, scale: scale)
                .fill(Color.white.opacity(shine > 0.05 ? 0.85 * shine : 0))
        }
    }
}

/// Where the headset's parts sit, shared by the band and the cups.
private nonisolated struct HeadsetLayout {
    let layout: RobotLayout
    var cup: CGFloat { 8 * layout.scale }
    var offset: CGFloat { layout.gap / 2 + 13 * layout.scale + 2.5 * layout.scale + cup / 2 }
    var cupTop: CGFloat { layout.centerY - cup / 2 }
    var bandTop: CGFloat { layout.centerY - 13 * layout.scale }
}

private struct BandPath: Shape {
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        let l = HeadsetLayout(layout: RobotLayout(size: rect.size, scale: scale))
        let cx = l.layout.centerX
        var band = Path()
        band.move(to: CGPoint(x: cx - l.offset, y: l.cupTop))
        band.addLine(to: CGPoint(x: cx - l.offset, y: l.bandTop))
        band.addLine(to: CGPoint(x: cx + l.offset, y: l.bandTop))
        band.addLine(to: CGPoint(x: cx + l.offset, y: l.cupTop))
        return band
    }
}

private struct CupsPath: Shape {
    let scale: CGFloat
    /// 0...1, follows the beat.
    let pulse: Double

    func path(in rect: CGRect) -> Path {
        let l = HeadsetLayout(layout: RobotLayout(size: rect.size, scale: scale))
        let grow = pulse * 0.6 * scale
        var path = Path()
        for side in [-1.0, 1.0] {
            let cup = CGRect(x: l.layout.centerX + side * l.offset - l.cup / 2, y: l.cupTop, width: l.cup, height: l.cup)
                .insetBy(dx: -grow, dy: -grow)
            path.addRoundedRect(in: cup, cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
        }
        return path
    }
}

/// A boxy headset: square cups hugging the eyes and a squared-off band, so
/// it stays narrow enough to sit beside the notch.
private struct HeadsetView: View {
    let tint: Color
    let scale: CGFloat
    let pulse: Double

    var body: some View {
        ZStack {
            BandPath(scale: scale)
                .stroke(Color(white: 0.55), style: StrokeStyle(lineWidth: max(1.2, 2 * scale), lineCap: .square, lineJoin: .miter))
            CupsPath(scale: scale, pulse: pulse)
                .fill(Color(white: 0.22))
            CupsPath(scale: scale, pulse: pulse)
                .stroke(tint.opacity(0.5 + 0.5 * pulse), lineWidth: 1)
        }
    }
}

// MARK: - Watching a video

/// The robot's routine while a video plays: soda on the left, popcorn on the
/// right. Every few seconds it picks something to do — eat, sip, laugh, jump
/// at a scary bit, lean in, glance around — blending from one to the next.
/// Eating and sipping use them up; at the end of each round it tosses the
/// empty ones away and fresh ones drop in. Shared by the face and
/// `SnacksView` so a kernel lands as the robot chews.
private enum Snacks {
    nonisolated enum Act: CaseIterable {
        case eat, drink, laugh, shocked, focus, glance, sad, watch
        /// Throws the empties away and gets new ones; ends every round.
        case toss

        var weight: Int {
            switch self {
            case .eat: 5
            case .drink: 3
            case .watch: 3
            case .laugh, .focus, .glance: 2
            case .shocked, .sad: 1
            case .toss: 0
            }
        }
    }

    /// Seconds per act.
    nonisolated static let length = 3.0
    /// Seconds a new act takes to blend in.
    nonisolated static let blend = 0.45
    /// Seconds a kernel is in the air.
    nonisolated static let flight = 0.55
    /// Acts per round; the last one is the toss.
    nonisolated static let round = 10
    /// Seconds into the toss the empties fly off, and the new ones land.
    nonisolated static let throwSpan = 0.25...1.15
    nonisolated static let dropSpan = 1.4...2.1

    private nonisolated static let deck: [Act] = Act.allCases.flatMap { Array(repeating: $0, count: $0.weight) }

    private nonisolated static func random(_ n: Int) -> Act {
        deck[RobotBuddyView.pick(n &* 31 &+ 5, count: deck.count)]
    }

    /// The act in segment `n`; never the same twice in a row, except watching.
    nonisolated static func act(_ n: Int) -> Act {
        if position(n) == round - 1 { return .toss }
        let a = random(n)
        guard a != .watch, a == random(n - 1) else { return a }
        return a == .eat ? .drink : .eat
    }

    private nonisolated static func position(_ n: Int) -> Int { ((n % round) + round) % round }

    /// How far into eating or sipping an act is, 0...1.
    nonisolated static func eatProgress(_ e: Double) -> Double { RobotBuddyView.ease(e / flight) }
    nonisolated static func sipProgress(_ e: Double) -> Double { RobotBuddyView.ease((e - 0.2) / 1.9) }

    /// What's left of each, 0...1, and whether it gets tossed this round.
    nonisolated struct Levels {
        var popcorn = 1.0, soda = 1.0
        var tossPopcorn = false, tossSoda = false
    }

    nonisolated static func levels(segment n: Int, elapsed e: Double) -> Levels {
        let start = n - position(n)
        var eats = 0, sips = 0, eaten = 0.0, sipped = 0.0
        for k in start..<(start + round - 1) {
            let a = act(k)
            if a == .eat {
                eats += 1
                if k < n { eaten += 1 } else if k == n { eaten += eatProgress(e) }
            } else if a == .drink {
                sips += 1
                if k < n { sipped += 1 } else if k == n { sipped += sipProgress(e) }
            }
        }
        return Levels(popcorn: eats > 0 ? 1 - eaten / Double(eats) : 1,
                      soda: sips > 0 ? 1 - sipped / Double(sips) : 1,
                      tossPopcorn: eats > 0, tossSoda: sips > 0)
    }

    /// The act now, its segment and seconds into it.
    nonisolated static func now(_ t: Double) -> (act: Act, segment: Int, elapsed: Double) {
        let n = floor(t / length)
        return (act(Int(n)), Int(n), t - n * length)
    }

    static func frame(at t: Double) -> Frame {
        let n = floor(t / length)
        let e = t - n * length
        let current = frame(act(Int(n)), e, t)
        guard e < blend else { return current }
        let previous = frame(act(Int(n) - 1), length + e, t)
        return previous.mixed(with: current, by: RobotBuddyView.ease(e / blend))
    }

    private static func frame(_ act: Act, _ e: Double, _ t: Double) -> Frame {
        let ease = RobotBuddyView.ease
        let hold = ease(e / 0.4) * ease((length - e) / 0.4)
        var shape = EyeShape.watching
        // Breathing slowly while it watches.
        var pose = Pose(y: -0.4 * (0.5 + 0.5 * sin(t * 1.6)), rotation: 1.5 * sin(t * 0.7))
        var badge: String?
        var badgeAlpha = 0.0
        var side = 1.0

        switch act {
        case .watch:
            shape.lookX = 1.2 * sin(t * 0.5)

        case .eat:
            // Glances down at the popcorn as a kernel pops up, then chews.
            let reach = e < flight ? sin(.pi * e / flight) : 0
            let chew = e > flight ? ease((e - flight) / 0.12) * (1 - ease((e - flight - 1.2) / 0.3)) : 0
            let bite = chew * abs(sin(3 * .pi * e))
            shape.lookX = 2.5 * reach
            shape.lookY = 1 + 1.5 * reach - 1.5 * chew
            shape.cheek = 0.75 * chew
            pose.y += 1.5 * reach + 0.6 * bite
            pose.rotation += 3 * reach
            pose.squash = 1 - 0.05 * bite

        case .drink:
            // Leans over to the straw and sips, eyes half closed, content.
            let sip = ease((e - 0.2) / 0.35) * (1 - ease((e - 2.1) / 0.35))
            let gulp = sip * abs(sin(e * 7))
            shape.lookX = -2.5 * sip
            shape.lookY = 1 + 1.2 * sip
            shape.lid = 0.3 * sip
            shape.cheek = 0.35 * sip
            pose.x -= 1 * sip
            pose.y += 1.2 * sip + 0.3 * gulp
            pose.rotation -= 4 * sip
            pose.squash = 1 - 0.03 * gulp
            side = -1

        case .laugh:
            let hop = abs(sin(e * 2 * .pi * 2.4)) * hold
            shape = EyeShape(width: 13.5, height: 15, cheek: 0.95, blush: 0.35)
            pose = Pose(y: -1.6 * hop, rotation: 3 * sin(e * 13) * hold, squash: 1 + 0.05 * hop)
            badge = "ha"
            badgeAlpha = hold * (0.6 + 0.4 * hop)

        case .shocked:
            // Jumps at a sudden bit, then settles down warily.
            let jump = ease(e / 0.1) * (1 - ease((e - 0.3) / 0.5))
            shape = EyeShape(width: 12.5, height: 22, lookY: -0.5).mixed(with: .suspicious, by: ease((e - 1.6) / 0.6) * 0.6)
            shape.width = max(shape.width, 13)
            pose = Pose(y: -3.5 * jump, squash: 1 + 0.1 * jump)
            badge = "!"
            badgeAlpha = 1 - ease((e - 1) / 0.6)

        case .focus:
            // Leans in, narrowed eyes, gripped by the scene.
            shape = EyeShape(width: 14, height: 14, lookY: 1.5, brow: 0.2, lid: 0.15)
            pose.y += 1.2 * hold
            pose.squash = 1 - 0.03 * hold
            pose.rotation = 0

        case .glance:
            // Looks away from the screen at you, then back.
            let look = sin(.pi * min(1, e / 2.4))
            let way: Double = Int(t / length) % 2 == 0 ? 1 : -1
            shape.lookX = 3 * look * way
            shape.lookY = 1 - 2 * look
            shape.cheek = 0.4 * look
            pose.rotation += 3 * look * way

        case .sad:
            // A sad scene: droopy brows and a tear.
            shape = EyeShape(width: 13.5, height: 16, lookY: 1.5, brow: -0.45)
            pose.y += 0.8 * hold
            pose.rotation = -3 * hold
            badge = "💧"
            badgeAlpha = hold * ease((e - 0.6) / 0.5)
            side = -1

        case .toss:
            // A peek into the empties, a flick to throw them away, then
            // delight as fresh ones drop in.
            let peek = ease(e / 0.2) * (1 - ease((e - throwSpan.lowerBound) / 0.1))
            let flick = sin(.pi * min(1, max(0, (e - throwSpan.lowerBound) / 0.35)))
            let joy = ease((e - dropSpan.upperBound + 0.2) / 0.25) * ease((length - e) / 0.4)
            shape.lookY = 1 + 2 * peek
            shape.brow = -0.3 * peek
            shape = shape.mixed(with: EyeShape(width: 13.5, height: 13, cheek: 0.85), by: flick)
            shape = shape.mixed(with: EyeShape(width: 14, height: 19, cheek: 0.6, blush: 0.4), by: joy)
            pose.y += 1 * peek - 2 * flick - 1.5 * joy * abs(sin(e * 9))
            pose.squash = 1 + 0.07 * flick
            badge = "✨"
            badgeAlpha = joy
        }
        (shape.red, shape.green, shape.blue) = (0.2, 0.95, 1)
        return Frame(pose: pose, shape: shape, pulse: 0, headset: 0, badge: badge, badgeAlpha: badgeAlpha,
                     badgeSide: side, snacks: 1)
    }
}

/// A soda on the left and a bucket of popcorn on the right, small and leaning
/// outward so the eyes stay clear. Kernels fly up while it eats, the straw
/// fills while it sips, and empties are thrown away for fresh ones.
private struct SnacksView: View {
    let scale: CGFloat
    let t: Double

    /// Degrees each one leans outward.
    private static let lean = 11.0

    var body: some View {
        Canvas { context, size in
            let l = RobotLayout(size: size, scale: scale)
            let s = scale
            let ease = RobotBuddyView.ease
            let eyes = l.centerY - RobotBuddyView.watchingLift(height: size.height, scale: s) * s
            let top = eyes + 14 * s
            let height = 14 * s
            let (act, n, e) = Snacks.now(t)
            let levels = Snacks.levels(segment: n, elapsed: e)

            // Tossing: the old ones fly off outward, spinning; new ones drop in.
            var away = 0.0, drop = 1.0
            if act == .toss {
                away = ease((e - Snacks.throwSpan.lowerBound) / (Snacks.throwSpan.upperBound - Snacks.throwSpan.lowerBound))
                let d = min(1, max(0, (e - Snacks.dropSpan.lowerBound) / (Snacks.dropSpan.upperBound - Snacks.dropSpan.lowerBound)))
                // A little bounce as it lands.
                drop = d < 0.7 ? ease(d / 0.7) : 1 + 0.12 * sin(.pi * (d - 0.7) / 0.3)
            }

            /// Draws `item` leaning outward on `side`, pivoting on its bottom,
            /// thrown or dropped as the toss goes.
            func place(_ cx: CGFloat, side: Double, tossed: Bool, _ item: (inout GraphicsContext, Double) -> Void) {
                let bottom = CGPoint(x: cx, y: top + height)
                func layer(level: Double, throwAmount: Double, dropAmount: Double, alpha: Double) {
                    guard alpha > 0.01 else { return }
                    var c = context
                    c.opacity = alpha
                    let dx = side * 28 * s * throwAmount
                    let dy = -14 * s * sin(.pi * throwAmount) + 6 * s * throwAmount - (1 - dropAmount) * 22 * s
                    c.translateBy(x: bottom.x + dx, y: bottom.y + dy)
                    c.rotate(by: .degrees(side * (Self.lean + 220 * throwAmount)))
                    c.translateBy(x: -bottom.x, y: -bottom.y)
                    item(&c, level)
                }
                if tossed && act == .toss {
                    // The empty one leaves, the full one arrives.
                    layer(level: 0, throwAmount: away, dropAmount: 1, alpha: 1 - ease((away - 0.6) / 0.4))
                    layer(level: 1, throwAmount: 0, dropAmount: drop, alpha: ease(drop / 0.5))
                } else {
                    layer(level: side < 0 ? levels.soda : levels.popcorn, throwAmount: 0, dropAmount: 1, alpha: 1)
                }
            }

            func cup(_ cx: CGFloat, _ top: CGFloat, _ topW: CGFloat, _ bottomW: CGFloat, _ height: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: cx - topW / 2, y: top))
                p.addLine(to: CGPoint(x: cx + topW / 2, y: top))
                p.addLine(to: CGPoint(x: cx + bottomW / 2, y: top + height))
                p.addLine(to: CGPoint(x: cx - bottomW / 2, y: top + height))
                p.closeSubpath()
                return p
            }

            // Soda, left: a clear cup showing what's left, a lid and a straw.
            let soda = l.centerX - 12 * s
            let sipping = act == .drink ? ease((e - 0.2) / 0.35) * (1 - ease((e - 2.1) / 0.35)) : 0
            place(soda, side: -1, tossed: levels.tossSoda) { c, level in
                let topW = 11 * s, bottomW = 8.5 * s
                var straw = Path()
                straw.move(to: CGPoint(x: soda + 1.2 * s, y: top + 2 * s))
                straw.addLine(to: CGPoint(x: soda + 1.2 * s, y: top - 5.5 * s))
                straw.addLine(to: CGPoint(x: soda + 4.2 * s, y: top - 7.5 * s - 1.5 * s * sipping))
                c.stroke(straw, with: .color(Color(white: 0.95)), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                if sipping > 0.05, level > 0.01 {
                    c.stroke(straw.trimmedPath(from: 0, to: sipping * (0.85 + 0.15 * sin(e * 7))),
                             with: .color(Color(red: 0.55, green: 0.27, blue: 0.13)),
                             style: StrokeStyle(lineWidth: 1 * s, lineCap: .round, lineJoin: .round))
                }
                let body = cup(soda, top, topW, bottomW, height)
                c.fill(body, with: .color(Color(white: 0.85, opacity: 0.35)))
                c.drawLayer { inner in
                    inner.clip(to: body)
                    let surface = top + height * (1 - 0.9 * level)
                    inner.fill(Path(CGRect(x: soda - topW, y: surface, width: topW * 2, height: height)),
                               with: .color(Color(red: 0.55, green: 0.27, blue: 0.13)))
                    // A blue band, like the cup's print.
                    inner.fill(Path(CGRect(x: soda - topW, y: top + 5 * s, width: topW * 2, height: 3.5 * s)),
                               with: .color(Color(red: 0.15, green: 0.55, blue: 1)))
                }
                c.fill(Path(roundedRect: CGRect(x: soda - topW / 2 - 0.8 * s, y: top - 1.3 * s, width: topW + 1.6 * s, height: 2.6 * s),
                            cornerRadius: 1.3 * s), with: .color(Color(white: 0.9)))
            }

            // Popcorn, right: the heap sinks into the bucket as it's eaten.
            let pop = l.centerX + 12 * s
            let puff = Color(red: 1, green: 0.95, blue: 0.75)
            let puffShade = Color(red: 0.98, green: 0.82, blue: 0.45)
            place(pop, side: 1, tossed: levels.tossPopcorn) { c, level in
                let topW = 14 * s, bottomW = 10 * s
                if level > 0.02 {
                    let sink = (1 - level) * 5 * s
                    func ball(_ x: Double, _ y: Double, _ r: Double, _ color: Color) {
                        let p = CGPoint(x: pop + x * s, y: top + y * s + sink)
                        c.fill(Path(ellipseIn: CGRect(x: p.x - r * s, y: p.y - r * s, width: 2 * r * s, height: 2 * r * s)), with: .color(color))
                    }
                    for (x, y) in [(-4.2, -0.4), (4.2, -0.4), (0.0, -2.2)] { ball(x, y, 2.8, puffShade) }
                    for (x, y, needs) in [(-2.4, -1.3, 0.55), (2.5, -1.4, 0.3), (-5.2, 0.3, 0.0), (5.2, 0.3, 0.75), (0.0, -0.3, 0.0)] where level > needs {
                        ball(x, y, 2.4, puff)
                    }
                }
                let bucket = cup(pop, top, topW, bottomW, height)
                c.fill(bucket, with: .color(.white))
                c.drawLayer { inner in
                    inner.clip(to: bucket)
                    let stripes = 5, k = bottomW / topW
                    let stripe = topW / CGFloat(stripes)
                    for i in stride(from: 0, to: stripes, by: 2) {
                        let x0 = -topW / 2 + CGFloat(i) * stripe, x1 = x0 + stripe
                        var p = Path()
                        p.move(to: CGPoint(x: pop + x0, y: top))
                        p.addLine(to: CGPoint(x: pop + x1, y: top))
                        p.addLine(to: CGPoint(x: pop + x1 * k, y: top + height))
                        p.addLine(to: CGPoint(x: pop + x0 * k, y: top + height))
                        inner.fill(p, with: .color(Color(red: 0.92, green: 0.18, blue: 0.2)))
                    }
                }
                c.fill(Path(roundedRect: CGRect(x: pop - topW / 2 - 0.8 * s, y: top - 1.2 * s, width: topW + 1.6 * s, height: 2.4 * s),
                            cornerRadius: 1.2 * s), with: .color(Color(white: 0.92)))
            }

            // While eating, a kernel pops out and arcs up to the robot.
            if act == .eat, e < Snacks.flight {
                let p = e / Snacks.flight
                let from = CGPoint(x: pop + 2 * s, y: top - 3 * s)
                let to = CGPoint(x: l.centerX + 1 * s, y: eyes + 8 * s)
                let x = from.x + (to.x - from.x) * p
                let y = from.y + (to.y - from.y) * p - 10 * s * 4 * p * (1 - p)
                let r = 2.3 * s * (1 - 0.3 * p)
                var kernel = context
                kernel.opacity = 1 - ease((p - 0.75) / 0.25)
                kernel.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(puff))
            }
        }
    }
}

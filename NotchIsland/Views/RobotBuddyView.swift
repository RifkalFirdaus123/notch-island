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

    private var mode: Mode { Mode(isListening: isListening, isAngry: isAngry, mood: mood) }

    var body: some View {
        let mode = self.mode
        TimelineView(.animation(minimumInterval: mode.active || RobotTransitions.shared.isChanging ? 1 / 24 : 1 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let frame = RobotTransitions.shared.frame(for: mode, at: t)
            let pose = frame.pose
            let shape = frame.shape

            ZStack {
                EyesView(shape: shape, scale: scale)
                // On top, so a cup is never hidden behind an eye.
                HeadsetView(tint: shape.color, scale: scale, pulse: frame.pulse)
                    .opacity(frame.headset)
                    .offset(y: (1 - frame.headset) * -8 * scale)
                    .scaleEffect(0.6 + 0.4 * frame.headset)
            }
            .frame(width: Self.faceWidth * scale)
            .scaleEffect(x: 1 - (pose.squash - 1) * 0.5, y: pose.squash, anchor: .bottom)
            .rotationEffect(.degrees(pose.rotation))
            .offset(x: pose.x * scale, y: pose.y * scale)
        }
    }

    /// Width of the face including the headset, in design points.
    private static let faceWidth: CGFloat = 60

    fileprivate static func frame(for mode: Mode, at t: Double) -> Frame {
        let vibe = mode.vibe
        let phase = t * vibe.bpm / 60
        let pose = self.pose(atBeat: phase, vibe: vibe)
        let shape = eyes(at: t, mode: mode, lookSway: pose.look)
        return Frame(pose: pose, shape: shape, pulse: mode.isListening ? abs(sin(.pi * phase)) : 0,
                     headset: mode.isListening ? 1 : 0)
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
    fileprivate static func pick(_ index: Int, count: Int) -> Int {
        var x = UInt64(bitPattern: Int64(index)) &* 6364136223846793005 &+ 1442695040888963407
        x ^= x >> 29
        return Int(x % UInt64(count))
    }

    fileprivate static func ease(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}

/// What the robot is reacting to; a change sets off a double take.
private struct Mode: Equatable {
    var isListening: Bool
    var isAngry: Bool
    var mood: LyricMood

    var active: Bool { isListening || isAngry }
    var vibe: Vibe { isAngry ? .smug : isListening ? .make(mood) : .idle }

    var eyeColor: (Double, Double, Double) {
        if isAngry { return (1, 0.1, 0.08) }
        return isListening && mood != .neutral ? mood.eyeColor : (0.2, 0.95, 1)
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

    func mixed(with other: Frame, by f: Double) -> Frame {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return Frame(pose: pose.mixed(with: other.pose, by: f), shape: shape.mixed(with: other.shape, by: f),
                     pulse: m(pulse, other.pulse), headset: m(headset, other.headset))
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

    func mixed(with other: EyeShape, by f: Double) -> EyeShape {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return EyeShape(
            width: m(width, other.width), height: m(height, other.height),
            lookX: m(lookX, other.lookX), lookY: m(lookY, other.lookY),
            brow: m(brow, other.brow), lid: m(lid, other.lid), cheek: m(cheek, other.cheek),
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
        let blush = shape.cheek * 0.55
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

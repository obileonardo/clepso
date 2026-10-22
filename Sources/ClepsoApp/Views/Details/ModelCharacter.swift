import DesignSystem
import SwiftUI

/// Native counterpart of the approved literary guild. Model identity selects an edition; usage-based levels never
/// change the artwork or manufacture a newer model version. Unknown versions retain the family’s base silhouette.
struct ModelCharacter: Sendable {
    enum Edition: String, CaseIterable, Sendable {
        case opus, opus55, fable, fable51, sonnet, haiku, other
    }
    enum Frame: Int, CaseIterable, Sendable { case still, gesture, flutter, blink }
    let edition: Edition

    init(_ modelID: String) {
        var parts = modelID.lowercased().replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        let version = Array(parts.dropFirst().prefix(2))
        edition = switch parts.first {
        case "opus": version == ["5", "5"] ? .opus55 : .opus
        case "fable": version == ["5", "1"] ? .fable51 : .fable
        case "sonnet": .sonnet
        case "haiku": .haiku
        default: .other
        }
    }

    static let frameInterval: TimeInterval = 0.12
    static let cycleFrames = 35

    /// Four authored poses over a quiet 4.2-second cycle; feet and shadow stay planted. Pure timing makes the paused
    /// and Reduce Motion result testable without waiting on the system clock or running a view timer.
    static func frame(at time: TimeInterval, enabled: Bool) -> Frame {
        guard enabled, time.isFinite, time >= 0 else { return .still }
        let cycle = frameInterval * Double(cycleFrames)
        let index = Int((time.truncatingRemainder(dividingBy: cycle) / frameInterval).rounded(.down))
        switch index {
        case 7...12: return .gesture
        case 18...21: return .flutter
        case 30: return .blink
        default: return .still
        }
    }

    struct Run: Sendable, Equatable {
        let x: Int, y: Int, width: Int
        let ink: CharacterInk
    }
    struct Drawing: Sendable {
        let dimension: Int
        let runs: [Run]
    }

    /// Decode each atlas once, grouping adjacent pixels into horizontal runs. Drawing performs no bitmap decoding
    /// or I/O. Small level markers use a compact 20-cell raster so they fill their slot on whole physical pixels.
    private static let drawings: [Edition: [Drawing]] = Edition.allCases.reduce(into: [:]) { result, edition in
        result[edition] = (ModelCharacterAtlas.rows[edition] ?? []).map { rows in
            drawing(rows.map(Array.init))
        }
    }
    private static let compact: [Edition: [Drawing]] = Edition.allCases.reduce(into: [:]) { result, edition in
        result[edition] = (ModelCharacterAtlas.rows[edition] ?? []).map { rows in
            let grid = rows.map(Array.init)
            let small = stride(from: 1, to: 40, by: 2).map { y in
                stride(from: 1, to: 40, by: 2).map { x in grid[y][x] }
            }
            return drawing(small)
        }
    }
    private static func drawing(_ rows: [[Character]]) -> Drawing {
        let inks = Array("abcdefghij")
        var runs: [Run] = []
        for (y, row) in rows.enumerated() {
            var x = 0
            while x < row.count {
                let start = x, code = row[x]
                while x < row.count, row[x] == code { x += 1 }
                if let index = inks.firstIndex(of: code), let ink = CharacterInk(rawValue: index) {
                    runs.append(Run(x: start, y: y, width: x - start, ink: ink))
                }
            }
        }
        return Drawing(dimension: rows.count, runs: runs)
    }

    func drawing(_ frame: Frame, compact: Bool = false) -> Drawing {
        let poses = (compact ? Self.compact : Self.drawings)[edition] ?? []
        return poses.isEmpty ? Drawing(dimension: 40, runs: []) : poses[min(frame.rawValue, poses.count - 1)]
    }

    struct Placement: Equatable {
        let unit: CGFloat
        let origin: CGPoint
        let compact: Bool
    }
    static func placement(size: CGSize, displayScale: CGFloat) -> Placement {
        guard size.width.isFinite, size.height.isFinite, displayScale.isFinite,
              size.width > 0, size.height > 0, displayScale > 0 else {
            return Placement(unit: 0, origin: .zero, compact: false)
        }
        let compact = min(size.width, size.height) < 40
        let dimension: CGFloat = compact ? 20 : 40
        let unit = floor(min(size.width, size.height) * displayScale / dimension) / displayScale
        // Round the origin as well as each grid cell: no half-physical-pixel edges or scaling interpolation.
        let x = floor((size.width - dimension * unit) / 2 * displayScale) / displayScale
        let y = floor((size.height - dimension * unit) / 2 * displayScale) / displayScale
        return Placement(unit: unit, origin: CGPoint(x: x, y: y), compact: compact)
    }
}

/// One native Canvas; only the selected dossier animates. The roster and level track always use a still pose.
/// Hidden or inactive windows, Pause and Reduce Motion all pause the schedule itself, rather than only hiding motion.
struct ModelSprite: View {
    let modelID: String
    var animated = false
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        let moving = animated && visible && scenePhase == .active && !reduceMotion
        TimelineView(.animation(minimumInterval: ModelCharacter.frameInterval, paused: reduceMotion || !moving)) { timeline in
            let frame = ModelCharacter.frame(at: timeline.date.timeIntervalSinceReferenceDate, enabled: moving)
            ModelCharacterCanvas(modelID: modelID, frame: frame)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}

/// Kept separate so previews and tests can render the exact authored pose, including a deterministic still frame.
struct ModelCharacterCanvas: View {
    let modelID: String
    var frame: ModelCharacter.Frame = .still
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let placement = ModelCharacter.placement(size: size, displayScale: displayScale)
            guard placement.unit > 0 else { return }
            let drawing = ModelCharacter(modelID).drawing(frame, compact: placement.compact)
            for ink in CharacterInk.allCases {
                var path = Path()
                for run in drawing.runs where run.ink == ink {
                    path.addRect(CGRect(x: placement.origin.x + CGFloat(run.x) * placement.unit,
                                        y: placement.origin.y + CGFloat(run.y) * placement.unit,
                                        width: CGFloat(run.width) * placement.unit, height: placement.unit))
                }
                context.fill(path, with: .color(ink.color))
            }
        }
        .accessibilityHidden(true)
    }
}

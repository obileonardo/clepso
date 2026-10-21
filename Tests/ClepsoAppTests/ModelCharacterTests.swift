import DesignSystem
import Foundation
import Testing
@testable import ClepsoApp

struct ModelCharacterTests {
    @Test("Real model identifiers choose editions without confusing dates or future versions")
    func editions() {
        for id in ["claude-opus-5-5", "claude-opus-5-5-20261001", "opus-5.5", "CLAUDE_OPUS_5_5"] {
            #expect(ModelCharacter(id).edition == .opus55)
        }
        for id in ["claude-fable-5-1", "claude-fable-5-1-20261001", "fable-5.1"] {
            #expect(ModelCharacter(id).edition == .fable51)
        }
        #expect(ModelCharacter("claude-opus-5").edition == .opus)
        #expect(ModelCharacter("claude-opus-4-20250505").edition == .opus)
        #expect(ModelCharacter("claude-opus-6-5").edition == .opus)
        #expect(ModelCharacter("claude-fable-5").edition == .fable)
        #expect(ModelCharacter("claude-sonnet-5-5").edition == .sonnet)
        #expect(ModelCharacter("claude-haiku-4-5-20251001").edition == .haiku)
        #expect(ModelCharacter("gpt-5.5").edition == .other)
        #expect(ModelCharacter("not-opus-5-5").edition == .other)
        #expect(ModelCharacter("").edition == .other)
    }

    @Test("Every authored pose is a valid 40-cell atlas, with a visible neutral fallback")
    func atlas() {
        #expect(ModelCharacterAtlas.palette == CharacterInk.allCases.map { $0.rgb.hex })
        for edition in ModelCharacter.Edition.allCases {
            let poses = ModelCharacterAtlas.rows[edition] ?? []
            #expect(!poses.isEmpty)
            for rows in poses {
                #expect(rows.count == 40 && rows.allSatisfy { $0.count == 40 })
                #expect(rows.joined().allSatisfy { ".abcdefghij".contains($0) })
            }
        }
        for id in ["opus-5", "opus-5.5", "fable-5", "fable-5.1", "sonnet-5.5", "haiku-4.5", "unknown"] {
            for compact in [false, true] {
                for frame in ModelCharacter.Frame.allCases {
                    let drawing = ModelCharacter(id).drawing(frame, compact: compact)
                    #expect(drawing.dimension == (compact ? 20 : 40))
                    #expect(drawing.runs.count > 10)
                    #expect(drawing.runs.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.x + $0.width <= drawing.dimension && $0.y < drawing.dimension })
                }
            }
        }
    }

    @Test("Edition differences survive every pose and compact rendering; motion keeps feet and shadow planted")
    func silhouettes() {
        for compact in [false, true] {
            for frame in ModelCharacter.Frame.allCases {
                for (base, next) in [("opus-5", "opus-5.5"), ("fable-5", "fable-5.1")] {
                    #expect(ModelCharacter(base).drawing(frame, compact: compact).runs != ModelCharacter(next).drawing(frame, compact: compact).runs)
                }
            }
        }
        for id in ["opus-5", "opus-5.5", "fable-5", "fable-5.1", "sonnet-5.5", "haiku-4.5"] {
            let character = ModelCharacter(id)
            let feet = character.drawing(.still).runs.filter { $0.y >= 35 }
            for frame in ModelCharacter.Frame.allCases {
                #expect(character.drawing(frame).runs.filter { $0.y >= 35 } == feet)
            }
            #expect(character.drawing(.still).runs != character.drawing(.gesture).runs)
            #expect(character.drawing(.still).runs != character.drawing(.blink).runs)
        }
    }

    @Test("Pause and Reduce Motion select a still frame; authored poses run on a finite quiet cycle")
    func motion() {
        for i in 0..<105 {
            let time = Double(i) * ModelCharacter.frameInterval + 0.001
            #expect(ModelCharacter.frame(at: time, enabled: false) == .still)
            #expect(ModelCharacter.frame(at: time, enabled: true) == ModelCharacter.frame(at: time + 4.2, enabled: true))
        }
        #expect(ModelCharacter.frame(at: 0, enabled: true) == .still)
        #expect(ModelCharacter.frame(at: 0.85, enabled: true) == .gesture)
        #expect(ModelCharacter.frame(at: 2.17, enabled: true) == .flutter)
        #expect(ModelCharacter.frame(at: 3.61, enabled: true) == .blink)
        for time in [Double.nan, .infinity, -.infinity, -1] {
            #expect(ModelCharacter.frame(at: time, enabled: true) == .still)
        }
    }

    @Test("Portrait and roster cells land on whole physical pixels without clipping at 1x or 2x")
    func placement() {
        for scale: CGFloat in [1, 2] {
            for size in [CGSize(width: 192, height: 156), CGSize(width: 54, height: 54), CGSize(width: 36, height: 36)] {
                let p = ModelCharacter.placement(size: size, displayScale: scale)
                let dimension: CGFloat = p.compact ? 20 : 40
                #expect(p.unit > 0)
                #expect(p.unit * scale == floor(p.unit * scale))
                #expect(p.origin.x * scale == floor(p.origin.x * scale))
                #expect(p.origin.y * scale == floor(p.origin.y * scale))
                #expect(p.origin.x >= 0 && p.origin.y >= 0)
                #expect(p.origin.x + dimension * p.unit <= size.width)
                #expect(p.origin.y + dimension * p.unit <= size.height)
            }
        }
        #expect(ModelCharacter.placement(size: .zero, displayScale: 2).unit == 0)
        #expect(ModelCharacter.placement(size: CGSize(width: 40, height: 40), displayScale: 0).unit == 0)
    }
}

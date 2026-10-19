import CoreGraphics
import Testing
@testable import DesignSystem

/// Founder, 19 Oct 2026: activity levels as pixel density, so the calendar is pixel art and a level reads without shade.
struct PixelDensityTests {
    func lit(_ level: Int, _ n: Int) -> Set<[Int]> {
        var out = Set<[Int]>()
        for r in 0..<n { for c in 0..<n where PixelDensity.isLit(level: level, column: c, row: r, count: n) { out.insert([c, r]) } }
        return out
    }

    @Test("Each level has its own pattern, lighting more pixels than the last; level 0 lights none, corners never light")
    func levels() {
        for n in [5, 7, 9, 15] {
            let sets = (0...4).map { lit($0, n) }
            #expect(sets[0].isEmpty)
            #expect(Set(sets).count == 5, "\(n): five different patterns")
            #expect(zip(sets, sets.dropFirst()).allSatisfy { $0.count < $1.count }, "\(n): more pixels at each level")
            #expect(sets[4].count == n * n - 4, "\(n): the top level is the whole tile less its notched corners")
            for corner in [[0, 0], [n - 1, 0], [0, n - 1], [n - 1, n - 1]] { #expect(!sets.contains { $0.contains(corner) }) }
            // Lit share ≈ 20 / 55 / 80 / 100 %: the eye's blend keeps the old brightness ramp (0.3 / 0.55 / 0.8 / 1).
            let share = sets.map { Double($0.count) / Double(n * n - 4) }
            #expect(share[1] < 0.3 && (0.45...0.6).contains(share[2]) && (0.75...0.85).contains(share[3]))
        }
    }

    @Test("Every pattern is centred: the same mirrored left–right and top–bottom")
    func centred() {
        for n in [5, 7, 9] {
            for level in 1...4 {
                let set = lit(level, n)
                #expect(set == Set(set.map { [n - 1 - $0[0], $0[1]] }), "level \(level), \(n) px: left–right")
                #expect(set == Set(set.map { [$0[0], n - 1 - $0[1]] }), "level \(level), \(n) px: top–bottom")
            }
        }
    }

    @Test("Tiles are an odd number of whole pixels: 2 pt pixels from 10 pt, hairline pixels below")
    func tiles() {
        let px: CGFloat = 2
        #expect(PixelDensity.tile(fitting: 13.4, px: px) == 10)
        #expect(PixelDensity.tile(fitting: 14, px: px) == 14)
        #expect(PixelDensity.tile(fitting: 32, px: px) == 30)
        #expect(PixelDensity.tile(fitting: 9.9, px: px) == 9)
        #expect(PixelDensity.tile(fitting: 8, px: px) == 7)
        #expect(PixelDensity.tile(fitting: 2, px: px) == 5, "never smaller than five hairline pixels")
        for limit in stride(from: CGFloat(5), through: 80, by: 0.5) {
            let tile = PixelDensity.tile(fitting: limit, px: px), unit = PixelDensity.unit(for: tile, px: px)
            #expect(tile <= limit && tile == tile.rounded())
            let n = Int(tile / unit)
            #expect(CGFloat(n) * unit == tile && n % 2 == 1 && n >= 5)
        }
    }

    @Test("A tile's pixels are whole-point squares filling it exactly, and the ground matches the top level")
    func pixelsOnWholePoints() {
        let rect = CGRect(x: 40, y: 13, width: 14, height: 14)
        let g = PixelDensity.grid(in: rect, px: 2)
        #expect(g.origin == rect.origin && g.count == 7 && g.unit == 2)
        let bounds = PixelDither(level: 4, px: 2).path(in: rect).boundingRect
        #expect(bounds == rect)
        #expect(PixelTile(px: 2).path(in: rect).boundingRect == rect)
        // A size that isn't a tile is drawn as the largest tile inside it, centred on whole points.
        let odd = PixelDensity.grid(in: CGRect(x: 0, y: 0, width: 20, height: 20), px: 2)
        #expect(odd.origin == CGPoint(x: 1, y: 1) && odd.count == 9)
    }
}

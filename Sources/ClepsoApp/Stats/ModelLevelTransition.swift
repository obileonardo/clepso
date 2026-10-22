/// A flourish requires a newly crossed output threshold while the same model/range is visible. Opening a model,
/// changing range, demo playback, old-file replay or recovering a previous high-water value never celebrates.
struct ModelLevelTransition {
    private var previous: (id: String, scope: String, output: Int64?)?
    private var highWater: [String: Int64] = [:]
    mutating func observe(id: String, scope: String, output: Int64?, active: Bool) -> Int? {
        let before = previous
        previous = (id, scope, output)
        guard let output else { return nil }
        let highest = highWater[id] ?? output
        if highWater.count >= 128, highWater[id] == nil { highWater.removeAll() }
        highWater[id] = max(highest, output)
        guard active, let before, before.id == id, before.scope == scope, let old = before.output,
              output > highest, output > old else { return nil }
        let next = ModelLevel(output: output).level
        return next > ModelLevel(output: old).level ? next : nil
    }
}

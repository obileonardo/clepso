import Foundation

/// Everything one upload sends: daily counts and a profile, shaped like the server's tables.
/// No row has a field for prompts, replies, paths, project names, raw session or agent ids, or per-session cost.
public struct SyncPayload: Sendable, Equatable {
    public struct Profile: Codable, Sendable, Equatable {
        public var displayName: String?
        public var planLabel: String?
        public init(displayName: String?, planLabel: String?) { self.displayName = displayName; self.planLabel = planLabel }
    }
    public struct Activity: Codable, Sendable, Equatable {
        public var day: String; public var messages: Int; public var sessions: Int; public var active: Bool
        public init(day: String, messages: Int, sessions: Int, active: Bool) { self.day = day; self.messages = messages; self.sessions = sessions; self.active = active }
    }
    public struct ModelTokens: Codable, Sendable, Equatable {
        public var day: String; public var model: String; public var tokens: Int64
        public init(day: String, model: String, tokens: Int64) { self.day = day; self.model = model; self.tokens = tokens }
    }
    public struct ModelTotals: Codable, Sendable, Equatable {
        public var model: String; public var input: Int64; public var output: Int64; public var cacheRead: Int64; public var cacheWrite: Int64
        public init(model: String, input: Int64, output: Int64, cacheRead: Int64, cacheWrite: Int64) {
            self.model = model; self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
        }
    }
    public struct Limits: Codable, Sendable, Equatable {
        public var day: String; public var fiveHourPeakPct: Double?; public var sevenDayEndPct: Double?
        public init(day: String, fiveHourPeakPct: Double?, sevenDayEndPct: Double?) { self.day = day; self.fiveHourPeakPct = fiveHourPeakPct; self.sevenDayEndPct = sevenDayEndPct }
    }
    public struct Agents: Codable, Sendable, Equatable {
        public var day: String; public var tasks: Int; public var agents: Int; public var byType: [String: Int]
        public init(day: String, tasks: Int, agents: Int, byType: [String: Int]) { self.day = day; self.tasks = tasks; self.agents = agents; self.byType = byType }
    }
    public struct Goal: Codable, Sendable, Equatable {
        public var kind: String; public var target: Int?
        public init(kind: String, target: Int?) { self.kind = kind; self.target = target }
        // `target` is always sent, null when the goal is off, so turning a goal off reaches the server.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(target, forKey: .target)
        }
    }
    public struct GoalDay: Codable, Sendable, Equatable {
        public var day: String; public var kind: String; public var value: Double?; public var met: Bool?
        public init(day: String, kind: String, value: Double?, met: Bool?) { self.day = day; self.kind = kind; self.value = value; self.met = met }
    }

    public var profile: Profile?
    public var activity: [Activity] = []
    public var modelTokens: [ModelTokens] = []
    public var modelTotals: [ModelTotals] = []
    public var limits: [Limits] = []
    public var agents: [Agents] = []
    public var goals: [Goal] = []
    public var goalDays: [GoalDay] = []
    public init() {}

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

import Foundation
import Testing
import ShimProtocol
import TestFixtures
import ClaudeCodeAdapter
import Domain
import Storage
import UsageEngine

/// The spec's field table written out again, test-side (docs/specs/statusline-shim.md §6). It is kept
/// separate from `Allowlist` on purpose: the harness compares the real frame with this second
/// statement, so an omission or addition in the code shows up as a contract failure.
enum SpecOracle {
    static let stdinToFrame: [String: String] = {
        var map: [String: String] = [
            "version": "source_version",
            "model.id": "model.id",
            "model.display_name": "model.display_name",
            "context_window.context_window_size": "context.window_size",
            "context_window.used_percentage": "context.used_pct",
            "context_window.remaining_percentage": "context.remaining_pct",
            "context_window.total_input_tokens": "context.total_input_tokens",
            "context_window.total_output_tokens": "context.total_output_tokens",
            "context_window.current_usage": "context.current_usage",
            "exceeds_200k_tokens": "context.exceeds_200k",
            "effort.level": "session.effort_level",
            "thinking.enabled": "session.thinking_enabled",
            "fast_mode": "session.fast_mode",
            "cost.total_cost_usd": "cost_usd_estimate",
            // Increment 1.7, founder decision 17 Oct 2026 (A4 amended).
            "cost.total_duration_ms": "activity.wall_ms",
            "cost.total_api_duration_ms": "activity.api_ms",
            "cost.total_lines_added": "activity.lines_added",
            "cost.total_lines_removed": "activity.lines_removed",
            "rate_limits.spend_limit.used_usd": "rate_limits.spend_limit.used_usd",
            "rate_limits.spend_limit.limit_usd": "rate_limits.spend_limit.limit_usd",
            "rate_limits.spend_limit.period": "rate_limits.spend_limit.period",
        ]
        for member in ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"] {
            map["context_window.current_usage.\(member)"] = "context.current_usage.\(member)"
        }
        for window in ["five_hour", "seven_day", "spend_limit"] {
            map["rate_limits.\(window).used_percentage"] = "rate_limits.\(window).used_pct"
            map["rate_limits.\(window).resets_at"] = "rate_limits.\(window).resets_at"
        }
        for field in ["warm", "caching_observed", "ttl", "expires_at", "hit_ratio", "requests", "misses"] {
            map["prompt_cache.\(field)"] = "prompt_cache.\(field)"
        }
        return map
    }()

    /// Top-level keys the status-line doc describes; anything else is "unknown".
    static let documentedTopLevel: Set<String> = [
        "session_id", "version", "model", "context_window", "exceeds_200k_tokens", "rate_limits", "prompt_cache",
        "effort", "thinking", "fast_mode", "cost", "cwd", "workspace", "transcript_path", "session_name",
        "prompt_id", "output_style", "vim", "agent", "pr", "worktree",
    ]

    struct Classified {
        var forwarded = Set<String>(), dropped = Set<String>(), scrubbed = Set<String>(), unknown = Set<String>()
        var transformed: [String] = []          // a mapped value that arrived changed: always a bug
        var badSessionRef = false
    }

    static func leaves(_ value: JSONValue, _ prefix: [String] = []) -> [([String], JSONValue)] {
        if case .object(let members) = value, !members.isEmpty {
            return members.flatMap { leaves($0.value, prefix + [$0.key]) }
        }
        return [(prefix, value)]
    }

    static func classify(stdin: JSONValue, frame: JSONValue, into c: inout Classified) {
        for (path, value) in leaves(stdin) {
            let key = path.joined(separator: ".")
            let top = path[0]
            guard documentedTopLevel.contains(top) else { c.unknown.insert(top); continue }
            if key == "session_id" {
                if case .value(.string(let ref)) = frame.lookup(["session_ref"]), ref.count == 16,
                   ref.allSatisfy(\.isHexDigit) {
                    c.forwarded.insert(key)
                } else {
                    c.badSessionRef = true
                }
                continue
            }
            if let target = stdinToFrame[key] {
                switch frame.lookup(target.split(separator: ".").map(String.init)) {
                case .value(let sent) where sent == value: c.forwarded.insert(key)
                case .null where value == .null: c.forwarded.insert(key)
                case .null, .absent: c.scrubbed.insert(key)
                case .value: c.transformed.append(key)
                }
            } else if stdinToFrame.keys.contains(where: { $0 == top || $0.hasPrefix(top + ".") }) {
                c.dropped.insert(key)          // documented parent, field not on the allowlist
            } else {
                c.dropped.insert(top)          // whole subtree is never forwarded
            }
        }
    }
}

struct FixtureCase: Sendable, CustomTestStringConvertible {
    let id: String
    let directory: URL
    var testDescription: String { id }
}

enum Corpus {
    static func json(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    static var manifest: [[String: Any]] {
        (try? json(Fixtures.claudeCodeRoot.appendingPathComponent("manifest.json")))?["fixtures"] as? [[String: Any]] ?? []
    }

    static var active: [FixtureCase] {
        // Status-line fixtures only; the F13 settings corpus is exercised by ClaudeCodeAdapterTests.
        manifest.filter { $0["status"] as? String == "active" && $0["kind"] == nil }.compactMap { entry in
            guard let id = entry["id"] as? String, let slug = entry["slug"] as? String else { return nil }
            let base = entry["dir"] as? String ?? "synthetic"
            return FixtureCase(id: id, directory: Fixtures.claudeCodeRoot.appendingPathComponent("\(base)/\(id)-\(slug)"))
        }
    }
}

func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

@Suite("Fixture contracts through the real helper", .serialized)
struct FixtureContractTests {
    @Test("Each active fixture: passthrough exact, frames as expected, fields classified as the spec says",
          arguments: Corpus.active)
    func contract(fixture: FixtureCase) async throws {
        let meta = try Corpus.json(fixture.directory.appendingPathComponent("meta.json"))
        let expected = try Corpus.json(fixture.directory.appendingPathComponent("expected.json"))
        let events = try #require(meta["events"] as? [[String: Any]])
        let clock = try #require(meta["clock"] as? [String: Any])
        let start = try #require(ISO8601DateFormatter().date(from: clock["start"] as? String ?? ""))

        let h = try ShimHarness(); defer { h.cleanUp() }
        let agent = meta["agent"] as? String == "absent" ? nil : try FakeAgent(path: h.socketPath, mode: .readAll)
        defer { agent?.stop() }

        var accepted: [Bool] = []
        var classified = SpecOracle.Classified()
        var scrubTotal = 0
        var frameTexts: [String] = []
        var rawSessionIDs: [String] = []
        var batches: [IngestBatch] = []

        for event in events {
            let stdout = event["originalCommandStdout"] as? String ?? ""
            try h.writeConfig(originalCommand: "printf '%s' " + shellQuoted(stdout))
            let stdin: Data
            if let file = event["file"] as? String {
                stdin = try Data(contentsOf: fixture.directory.appendingPathComponent(file))
            } else {
                let spec = try #require(event["generate"] as? [String: Any])
                let byte = UInt8(ascii: Unicode.Scalar((spec["repeatByte"] as? String ?? "x").utf8.first!))
                stdin = Data(repeating: byte, count: spec["count"] as? Int ?? 0)
            }
            let offset = event["atOffsetSeconds"] as? Int ?? 0
            let before = agent?.frames.count ?? 0
            let nowMs = Int64((start.timeIntervalSince1970 + Double(offset)) * 1000)

            let result = try h.run(stdin: stdin, nowMs: nowMs)
            #expect(result.stdout == Data(stdout.utf8), "\(fixture.id): the user's status line changed")
            #expect(result.status == 0, "\(fixture.id): exit status \(result.status)")

            guard let agent else { accepted.append(false); continue }
            // A maximum wait; frames normally arrive in milliseconds. 0.3 s failed twice for F01 on the first run after a
            // helper rebuild (cause unconfirmed: a slow first launch did not reproduce in isolation).
            let deadline = Date().addingTimeInterval(2)
            while agent.frames.count == before && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
            let gotFrame = agent.frames.count > before
            accepted.append(gotFrame)
            guard gotFrame, let wire = agent.frames.last else { continue }

            let frame = try FrameCodec.decode(wire)
            frameTexts.append(String(decoding: wire, as: UTF8.self))
            // Fixture clock: the app receives the frame at the moment the helper read it.
            if let batch = FrameMapper.map(frame, connectionID: UUID(), receivedAt: Date(timeIntervalSince1970: Double(nowMs) / 1000)) {
                batches.append(batch)
            }
            let input = try JSONDecoder().decode(JSONValue.self, from: stdin)
            if case .value(.string(let raw)) = input.lookup(["session_id"]) { rawSessionIDs.append(raw) }
            var perEvent = SpecOracle.Classified()
            SpecOracle.classify(stdin: input, frame: frame, into: &perEvent)
            classified.forwarded.formUnion(perEvent.forwarded)
            classified.dropped.formUnion(perEvent.dropped)
            classified.scrubbed.formUnion(perEvent.scrubbed)
            classified.unknown.formUnion(perEvent.unknown)
            classified.transformed += perEvent.transformed
            classified.badSessionRef = classified.badSessionRef || perEvent.badSessionRef
            if case .value(.number(let n)) = frame.lookup(["health", "scrub_count"]) { scrubTotal += Int(n) }
            #expect(frame.lookup(["health", "unknown_top_level_keys"]) == .value(.number(Double(perEvent.unknown.count))),
                    "\(fixture.id): unknown-key count in frame health")
        }

        let shim = try #require(expected["shim"] as? [String: Any])
        #expect((agent?.frames.count ?? 0) == shim["framesDelivered"] as? Int, "\(fixture.id): frames delivered")

        // Observations (increment 1.1): the real frames through FrameMapper must equal the oracle's list.
        if let expectedObservations = expected["observations"] as? [[String: Any]] {
            var labels: [String: String] = [:]
            let actual = batches.flatMap { batch in batch.observations.map { ObservationShape.canonical($0, labels: &labels) } }.sorted()
            let want = expectedObservations.map(ObservationShape.canonical).sorted()
            #expect(actual == want, "\(fixture.id) observations: unexpected \(Set(actual).subtracting(want).sorted()), missing \(Set(want).subtracting(actual).sorted())")
        }

        // Engine (increment 1.2): batches through the store; where each pool ends up and what fired.
        if let expectedSnapshot = expected["snapshot"] as? [String: [String: Any]] {
            let store = try Store.inMemory(now: start)
            for batch in batches {
                let meta = batch.sessionRef.map { Store.SessionMeta(sessionRef: $0, modelID: batch.modelID, modelDisplayName: batch.modelDisplayName) }
                _ = try await store.ingest(batch.observations, session: meta)
            }
            let renderAt = ISO8601DateFormatter().date(from: clock["renderAt"] as? String ?? "") ?? start
            _ = try await store.tick(now: max(renderAt, batches.last?.receivedAt ?? start))
            let states = Dictionary(uniqueKeysWithValues: try await store.poolStates().map { ($0.poolKey, $0) })
            for (key, want) in expectedSnapshot {
                let state = states[key]
                let got: [String: Any] = ["state": state?.limit.label ?? "missing",
                                          "usedPct": state?.usedPct.map { "\($0)" } ?? NSNull(),
                                          "resetsAt": state?.resetsAt.map { Int64($0.timeIntervalSince1970) } ?? NSNull(),
                                          "usedAbsence": state?.usedAbsence?.rawValue ?? NSNull()]
                #expect(ObservationShape.serialize(got) == ObservationShape.serialize(want), "\(fixture.id) \(key): got \(ObservationShape.serialize(got))")
            }
            let gotEvents = try await store.events().map { e -> String in
                var d: [String: Any] = ["kind": e.kind.rawValue, "pool": e.poolKey]
                if let level = e.level { d["level"] = level.rawValue }
                return ObservationShape.serialize(d)
            }.sorted()
            let wantEvents = (expected["events"] as? [[String: Any]] ?? []).map(ObservationShape.serialize).sorted()
            #expect(gotEvents == wantEvents, "\(fixture.id) events: unexpected \(gotEvents.filter { !wantEvents.contains($0) }), missing \(wantEvents.filter { !gotEvents.contains($0) })")
        }

        guard let parser = expected["parser"] as? [String: Any],
              let forwarded = expected["forwarded"] as? [String: Any] else { return }

        let expectedAccepted = (parser["events"] as? [[String: Any]] ?? []).map { $0["accepted"] as? Bool ?? false }
        #expect(accepted == expectedAccepted, "\(fixture.id): which events produced a frame")
        #expect(classified.unknown.sorted() == parser["unknownTopLevelKeys"] as? [String], "\(fixture.id): unknown keys")
        let health = parser["health"] as? [String: Int] ?? [:]
        #expect(accepted.filter { $0 }.count == health["accepted"])
        #expect(accepted.filter { !$0 }.count == health["rejected"])
        #expect(scrubTotal == health["scrubbed"], "\(fixture.id): scrub count")

        // Compared as sets: the order in which a fixture lists fields carries no meaning.
        for (name, actual, key) in [("forwarded", classified.forwarded, "fields"),
                                    ("dropped", classified.dropped, "droppedByConstruction"),
                                    ("scrubbed", classified.scrubbed, "scrubbed")] {
            let want = Set(forwarded[key] as? [String] ?? [])
            #expect(actual == want, "\(fixture.id) \(name): unexpected \(actual.subtracting(want).sorted()), missing \(want.subtracting(actual).sorted())")
        }
        #expect(classified.transformed.isEmpty, "\(fixture.id): values changed in transit: \(classified.transformed)")
        #expect(classified.badSessionRef == !(forwarded["sessionIdIsHMAC"] as? Bool ?? true), "\(fixture.id): session_ref")
        let rawLeaked = rawSessionIDs.contains { raw in frameTexts.contains { $0.contains(raw) } }
        #expect(rawLeaked == (forwarded["rawSessionIdPresentAnywhere"] as? Bool ?? false), "\(fixture.id): raw session id leaked")
        for text in frameTexts {
            #expect(!text.contains("/fixture") && !text.contains("transcript"), "\(fixture.id): a path reached the frame")
        }
    }
}

@Suite("Fixture corpus lint")
struct FixtureLintTests {
    @Test("The manifest covers F01 to F19 exactly once; deferred entries name a stage and a reason")
    func manifestComplete() throws {
        let ids = Corpus.manifest.compactMap { $0["id"] as? String }
        #expect(ids.filter { $0.hasPrefix("F") } == (1...19).map { String(format: "F%02d", $0) })
        #expect(Set(ids).count == ids.count, "fixture ids are unique")
        for entry in Corpus.manifest where entry["status"] as? String == "covered" {
            #expect(entry["coveredBy"] is String, "\(entry["id"] ?? "?") must name the tests that cover it")
        }
        for entry in Corpus.manifest where entry["status"] as? String == "deferred" {
            #expect(entry["stage"] is String && entry["reason"] is String, "\(entry["id"] ?? "?") needs stage and reason")
        }
        #expect(Corpus.active.count == 12)          // 11 synthetic status-line fixtures + C01
        #expect(Corpus.manifest.filter { $0["status"] as? String == "active" }.count == 13)
    }

    @Test("Every active fixture has meta and expected files whose ids match")
    func filesPresent() throws {
        for fixture in Corpus.active {
            let meta = try Corpus.json(fixture.directory.appendingPathComponent("meta.json"))
            let expected = try Corpus.json(fixture.directory.appendingPathComponent("expected.json"))
            #expect(meta["id"] as? String == fixture.id)
            #expect(expected["fixtureId"] as? String == fixture.id)
            #expect(meta["origin"] as? String == "synthetic" || meta["scrubbed"] as? Bool == true,
                    "\(fixture.id): captured fixtures must be scrubbed")
        }
    }

    @Test("No real path, volume, username or email anywhere in the corpus")
    func noPersonalData() throws {
        let files = FileManager.default.enumerator(at: Fixtures.claudeCodeRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath } ?? []
        #expect(!files.isEmpty)
        let username = NSUserName()
        for file in files {
            let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            for forbidden in ["/Users/", "/Volumes/", "@", username] where forbidden != "" {
                if file.lastPathComponent == "01-wrong-types.json" && forbidden == "/Users/" { continue } // the hostile path is the test
                #expect(!text.contains(forbidden), "\(file.lastPathComponent) contains \(forbidden)")
            }
        }
    }
}

/// One canonical JSON string per observation, in the fixture format (docs/fixtures/README.md §3), so the
/// mapper's output and the oracle's list compare as sorted string arrays.
enum ObservationShape {
    static func canonical(_ o: IncomingObservation, labels: inout [String: String]) -> String {
        var dict: [String: Any] = ["metricKind": o.kind.rawValue, "observedAt": ISO8601DateFormatter().string(from: o.observedAt),
                                   "source": o.evidence.rawValue, "sourceVersion": o.sourceVersion ?? NSNull(),
                                   "quality": o.quality.rawValue]
        switch o.subject {
        case .pool(let key): dict["subject"] = "pool"; dict["providerPoolKey"] = key
        case .session: dict["subject"] = "session"
        }
        if let ref = o.sessionRef {
            if labels[ref] == nil { labels[ref] = ["A", "B", "C", "D"][labels.count] }
            dict["sessionRef"] = labels[ref]
        }
        switch o.value {
        case .percent(let d): dict["measurement"] = ["kind": "percent", "value": "\(d)"]
        case .usd(let d): dict["measurement"] = ["kind": "usd", "value": "\(d)"]
        case .tokens(let n): dict["measurement"] = ["kind": "tokens", "value": n]
        case .instant(let date): dict["measurement"] = ["kind": "instant", "epochSeconds": Int64(date.timeIntervalSince1970)]
        case .count(let n): dict["measurement"] = ["kind": "count", "value": n]
        case .duration(let ms): dict["measurement"] = ["kind": "duration", "milliseconds": ms]
        case .flag(let b): dict["measurement"] = ["kind": "flag", "value": b]
        case .absent(let reason): dict["measurement"] = ["kind": "absent", "reason": reason.rawValue]
        }
        return serialize(dict)
    }

    static func canonical(_ expected: [String: Any]) -> String { serialize(expected) }

    static func serialize(_ dict: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
    }
}

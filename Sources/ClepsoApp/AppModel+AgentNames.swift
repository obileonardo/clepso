import Foundation
import os
import ShimProtocol

/// Approved agent names (founder decision 19 Oct 2026, DECISIONS C8 amended): the user can list custom Claude Code agent
/// names, letter for letter, to be shown by name instead of "Custom". The list lives in Clepso's preferences and is
/// written into the helper's config; the helper is the gate (it sends a custom type verbatim only when it is exactly
/// one of these names). The app checks again when a frame arrives, so a name taken off the list stops counting under
/// its own name at once, and its stored runs become Custom.
extension AppModel {
    public enum AgentNameOutcome: Equatable, Sendable {
        case added
        case invalid                // not an agent name's shape (1–40 of A–Z a–z 0–9 _ -)
        case builtIn                // Explore, Plan…: already shown by name; custom/unknown are Clepso's own buckets
        case duplicate
        case full                   // `HookFrame.maxApprovedAgentNames`
    }

    /// What adding `name` to `existing` would do. Exact and case-sensitive: `Code-Reviewer` is not `code-reviewer`.
    nonisolated static func checkAgentName(_ name: String, existing: [String]) -> AgentNameOutcome {
        let lowered = name.lowercased()
        if HookFrame.builtInAgentTypes.contains(name) || lowered == HookFrame.customAgentType || lowered == "unknown" { return .builtIn }
        guard HookFrame.isApprovableAgentName(name) else { return .invalid }
        if existing.contains(name) { return .duplicate }
        return existing.count >= HookFrame.maxApprovedAgentNames ? .full : .added
    }

    /// Settings › Claude Code › "Show these agents by name": adds one name (surrounding spaces trimmed, nothing else changed).
    public func approveAgentName(_ raw: String) async -> AgentNameOutcome {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = Self.checkAgentName(name, existing: approvedAgentNames)
        guard outcome == .added else { return outcome }
        await saveApprovedAgentNames((approvedAgentNames + [name]).sorted())
        return .added
    }

    /// Takes a name off the list: the helper stops sending it, and the runs already stored under it become Custom.
    public func removeApprovedAgentName(_ name: String) async {
        guard approvedAgentNames.contains(name) else { return }
        await saveApprovedAgentNames(approvedAgentNames.filter { $0 != name })
        _ = try? await store?.forgetAgentName(name)
        await refresh()
    }

    func saveApprovedAgentNames(_ names: [String]) async {
        approvedAgentNames = names
        agentNameAllowlist.set(names)
        try? await store?.setPreference(Pref.approvedAgentNames, names, now: environment.clock.now())
        let installer = Self.installer(environment, forwardCost: forwardCost, approvedAgentTypes: names)
        if environment.rewritesHome, installer.isInstalled { try? installer.repair() }
        // The same list names Codex's roles (sheet item 10), applied to the threads already read.
        if let usage = codexUsage, codexAgentTasks != nil {
            codexAgentTasks = usage.agents.tasks(approved: Set(names))
            await refresh()
        }
    }

    /// "Find my agents": the `name:` of each agent file in `~/.claude/agents`, read only when the user asks, names only
    /// (nothing else in the files is kept), and only names that could be approved and aren't yet. Nothing is approved here.
    public func suggestedAgentNames() -> [String] {
        let folder = environment.home.appendingPathComponent(".claude/agents")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let names = files.filter { $0.pathExtension == "md" }.prefix(500).compactMap { url -> String? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            return Self.frontmatterName(String(decoding: (try? handle.read(upToCount: 16 * 1024)) ?? Data(), as: UTF8.self))
        }
        return Set(names).filter { Self.checkAgentName($0, existing: approvedAgentNames) == .added }.sorted()
    }

    /// The `name:` value in a Markdown file's YAML frontmatter (the block between the first two `---` lines), unquoted.
    nonisolated static func frontmatterName(_ text: String) -> String? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }[...]
        guard lines.popFirst() == "---" else { return nil }
        for line in lines {
            if line == "---" { return nil }
            guard line.hasPrefix("name:") else { continue }
            let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let unquoted = value.count >= 2 && (value.first == "\"" || value.first == "'") && value.last == value.first
                ? String(value.dropFirst().dropLast()) : value
            return unquoted.isEmpty ? nil : unquoted
        }
        return nil
    }
}

/// The approved names, readable from the ingest path off the main actor.
final class AgentNameAllowlist: Sendable {
    private let names = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    func set(_ list: [String]) { names.withLock { $0 = Set(list) } }

    /// A frame's type as the store keeps it: built-in and "custom" as they are, an approved name as it is, anything else
    /// "custom" (a name removed from the list while a helper still had the old config).
    func filter(_ type: String) -> String {
        if HookFrame.builtInAgentTypes.contains(type) || type == HookFrame.customAgentType { return type }
        return names.withLock { $0.contains(type) } ? type : HookFrame.customAgentType
    }
}

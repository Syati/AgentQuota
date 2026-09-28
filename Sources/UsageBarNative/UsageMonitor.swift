import Foundation
import SwiftUI

struct ProviderUsage: Sendable {
    var usedPercent: Double?
    var secondaryUsedPercent: Double? = nil
    var resetsAt: Date?
    var detail: String

    static let loading = ProviderUsage(usedPercent: nil, secondaryUsedPercent: nil, resetsAt: nil, detail: Copy.text("読み込み中…", "Loading…"))

    /// Keeps the last known-good percentages when a refresh fails to fetch any data,
    /// so a transient failure doesn't blank out an already-displayed value.
    func merging(_ next: ProviderUsage) -> ProviderUsage {
        guard next.usedPercent != nil || next.secondaryUsedPercent != nil else {
            return ProviderUsage(usedPercent: usedPercent, secondaryUsedPercent: secondaryUsedPercent, resetsAt: resetsAt, detail: next.detail)
        }
        return next
    }

    var statusText: String {
        guard let usedPercent else { return "—" }
        return "\(usedPercent.formatted(.number.precision(.fractionLength(0))))%"
    }
}

@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var codex = ProviderUsage.loading
    @Published private(set) var claude = ProviderUsage.loading
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?

    func menuBarTitle(showCodex: Bool = true, showClaude: Bool = true) -> String {
        var values: [String] = []
        if showCodex, let percent = codex.usedPercent {
            values.append("Cdx \(percent.formatted(.number.precision(.fractionLength(0))))%")
        }
        if showClaude, let percent = claude.usedPercent {
            values.append("Cl \(percent.formatted(.number.precision(.fractionLength(0))))%")
        }
        return values.isEmpty ? "Quota —" : values.joined(separator: " · ")
    }

    func hasUsageWarning(showCodex: Bool = true, showClaude: Bool = true) -> Bool {
        let percentages = [showCodex ? codex.usedPercent : nil, showClaude ? claude.usedPercent : nil].compactMap { $0 }
        return percentages.contains(where: { $0 >= 90 })
    }

    func menuBarTooltip(showCodex: Bool = true, showClaude: Bool = true) -> String {
        [
            showCodex ? tooltipLine(name: "Codex", usage: codex) : nil,
            showClaude ? tooltipLine(name: "Claude Code", usage: claude) : nil
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func tooltipLine(name: String, usage: ProviderUsage) -> String {
        let primary = usage.usedPercent.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—"
        let secondary = usage.secondaryUsedPercent.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—"
        return "\(name): 5h \(primary) · 7d \(secondary)"
    }

    func start() {
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            async let codexUsage = CodexUsageReader.read()
            async let claudeUsage = ClaudeStatusLineUsageReader.read()
            codex = codex.merging(await codexUsage)
            claude = claude.merging(await claudeUsage)
            refreshedAt = .now
            isRefreshing = false
        }
    }

    deinit { refreshTask?.cancel() }
}

enum CodexUsageReader {
    static func read() async -> ProviderUsage {
        let start = Date()
        do {
            guard let codexURL = [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/usr/bin/codex"
            ]
                .map(URL.init(fileURLWithPath:))
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
            else {
                let detail = Copy.text("codex コマンドが見つかりません", "The codex command was not found")
                DiagnosticsLog.append("Codex: \(detail)")
                return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: detail)
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errorPipe = Pipe()
            process.executableURL = codexURL
            process.arguments = ["app-server"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errorPipe

            try process.run()
            defer { forceTerminate(process) }

            let initialize = "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"UsageBarNative\",\"version\":\"0.1.0\"}}}\n"
            input.fileHandleForWriting.write(Data(initialize.utf8))

            // Races the RPC exchange against a hard 10s deadline. `withTaskGroup` waits
            // for every child task before returning, and `process.terminate()` only
            // requests a graceful shutdown (codex app-server's own shutdown can take much
            // longer than 10s), so the losing exchange task must be force-killed as soon
            // as the deadline wins, not after — otherwise this call still blocks for as
            // long as codex takes to exit on its own (observed: 40s+).
            let outcome = await withTaskGroup(of: RPCOutcome?.self) { group in
                group.addTask { await Self.exchange(input: input, output: output) }
                group.addTask {
                    try? await Task.sleep(for: .seconds(10))
                    return nil
                }
                let first = await group.next() ?? nil
                if first == nil {
                    forceTerminate(process)
                }
                group.cancelAll()
                return first
            }

            guard let outcome else {
                let detail = Copy.text("Codex の応答がタイムアウトしました", "Codex did not respond in time")
                DiagnosticsLog.append("Codex: \(detail) (elapsed=\(elapsedString(since: start)))")
                return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: detail)
            }

            switch outcome {
            case .success(let usage):
                DiagnosticsLog.append("Codex: ok (elapsed=\(elapsedString(since: start)))")
                return usage
            case .rpcError(let object):
                DiagnosticsLog.append("Codex: rpc error \(object) (elapsed=\(elapsedString(since: start)))")
                fallthrough
            case .streamEnded:
                let detail = Copy.text("Codex の利用状況を取得できませんでした", "Could not retrieve Codex usage")
                let stderrText = readAvailableString(errorPipe)
                DiagnosticsLog.append("Codex: \(detail) (elapsed=\(elapsedString(since: start))\(stderrText.isEmpty ? "" : " stderr=\(stderrText)"))")
                return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: detail)
            }
        } catch {
            let detail = Copy.text("codex app-server を起動できませんでした", "Could not start codex app-server")
            DiagnosticsLog.append("Codex: \(detail) (elapsed=\(elapsedString(since: start)) error=\(error))")
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: detail)
        }
    }

    private enum RPCOutcome: Sendable {
        case success(ProviderUsage)
        case rpcError(String)
        case streamEnded
    }

    private static func exchange(input: Pipe, output: Pipe) async -> RPCOutcome {
        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    let id = object["id"] as? Int
                else { continue }

                if id == 1 {
                    let initialized = "{\"method\":\"initialized\",\"params\":{}}\n"
                    let limits = "{\"method\":\"account/rateLimits/read\",\"id\":2}\n"
                    input.fileHandleForWriting.write(Data((initialized + limits).utf8))
                    continue
                }

                guard
                    id == 2,
                    let result = object["result"] as? [String: Any],
                    let rateLimits = result["rateLimits"] as? [String: Any],
                    let primary = rateLimits["primary"] as? [String: Any],
                    let percent = numberValue(primary["usedPercent"])
                else {
                    if let errorObject = object["error"] {
                        return .rpcError(String(describing: errorObject))
                    }
                    continue
                }

                let secondary = numberValue((rateLimits["secondary"] as? [String: Any])?["usedPercent"])
                let reset = numberValue(primary["resetsAt"]).map(Date.init(timeIntervalSince1970:))
                return .success(ProviderUsage(usedPercent: percent, secondaryUsedPercent: secondary, resetsAt: reset, detail: ""))
            }
        } catch {}
        return .streamEnded
    }

    private static func forceTerminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private static func numberValue(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func elapsedString(since start: Date) -> String {
        String(format: "%.1fs", Date().timeIntervalSince(start))
    }

    private static func readAvailableString(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum DiagnosticsLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/AgentQuota/debug.log")

    private static let maxLines = 200

    static func append(_ message: String) {
        let line = "\(Date.now.formatted(.iso8601)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
        trimIfNeeded()
    }

    private static func trimIfNeeded() {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxLines else { return }
        let trimmed = lines.suffix(maxLines).joined(separator: "\n") + "\n"
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum ClaudeStatusLineUsageReader {
    static func read() async -> ProviderUsage {
        let path = ClaudeStatusLineIntegration.cacheURL
        guard let data = try? Data(contentsOf: path) else {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: Copy.text("Claude Code 連携を設定してください", "Set up the Claude Code integration"))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: Copy.text("Claude Code から保存した利用量を読めませんでした", "Could not read saved Claude Code usage"))
        }

        guard object["cacheVersion"] as? Int == 2 else {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: Copy.text("Claude Code を一度操作すると利用量が更新されます", "Use Claude Code once to refresh usage"))
        }
        let percent = object["fiveHourUsedPercent"] as? Double
        let secondary = object["sevenDayUsedPercent"] as? Double
        guard percent != nil || secondary != nil else {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: Copy.text("Claude Code の利用枠情報がまだ届いていません", "Claude Code quota data has not arrived yet"))
        }
        let reset = (object["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        return ProviderUsage(usedPercent: percent, secondaryUsedPercent: secondary, resetsAt: reset, detail: "")
    }
}

enum ClaudeStatusLineIntegration {
    static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/AgentQuota/claude-usage.json")

    private static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/settings.json")

    static var statusDescription: String {
        guard let helperURL else { return Copy.text("連携用プログラムがありません", "Integration helper is missing") }
        guard
            let data = try? Data(contentsOf: settingsURL),
            let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let statusLine = settings["statusLine"] as? [String: Any],
            let command = statusLine["command"] as? String
        else {
            return Copy.text("未設定", "Not configured")
        }
        return command == helperURL.path() ? Copy.text("AgentQuota と連携中", "Connected to AgentQuota") : Copy.text("既存の statusline を検出", "Existing statusline detected")
    }

    static var currentCommand: String? {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let statusLine = settings["statusLine"] as? [String: Any]
        else { return nil }
        return statusLine["command"] as? String
    }

    static var savedOriginalCommand: String? {
        guard
            let data = try? Data(contentsOf: wrapperURL),
            let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return config["originalCommand"] as? String
    }

    static var userCommand: String? {
        if let command = savedOriginalCommand { return command }
        guard let command = currentCommand, command != helperURL?.path() else { return nil }
        return command
    }

    static func install(preserving originalCommand: String?) throws {
        guard let helperURL = helperURL else {
            throw IntegrationError.helperNotFound
        }

        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path()) {
            let data = try Data(contentsOf: settingsURL)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw IntegrationError.invalidSettings
            }
            settings = parsed
        }

        let newStatusLine: [String: Any] = [
            "type": "command",
            "command": helperURL.path()
        ]
        if let originalCommand,
           !originalCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           originalCommand != helperURL.path() {
            let configData = try JSONSerialization.data(withJSONObject: ["originalCommand": originalCommand], options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: wrapperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try configData.write(to: wrapperURL, options: .atomic)
        }

        settings["statusLine"] = newStatusLine
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    static func saveMetricPreferences(showFiveHour: Bool, showSevenDay: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "showFiveHour": showFiveHour,
            "showSevenDay": showSevenDay
        ], options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: preferencesURL, options: .atomic)
    }

    static var metricPreferences: (showFiveHour: Bool, showSevenDay: Bool) {
        guard
            let data = try? Data(contentsOf: preferencesURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (true, true) }
        return (object["showFiveHour"] as? Bool ?? true, object["showSevenDay"] as? Bool ?? true)
    }

    private static let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/AgentQuota/claude-preferences.json")

    private static let wrapperURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/AgentQuota/claude-wrapper.json")

    private static var helperURL: URL? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        let helperURL = executableURL.deletingLastPathComponent().appending(path: "AgentQuotaClaudeStatusLine")
        return FileManager.default.isExecutableFile(atPath: helperURL.path()) ? helperURL : nil
    }

    enum IntegrationError: LocalizedError {
        case helperNotFound
        case invalidSettings
        case existingStatusLine

        var errorDescription: String? {
            switch self {
            case .helperNotFound:
                return Copy.text("Claude Code 連携用のプログラムが見つかりません。配布版の AgentQuota を使ってください。", "The Claude Code integration helper was not found. Use the distributed AgentQuota app.")
            case .invalidSettings:
                return Copy.text("~/.claude/settings.json を読み取れませんでした。", "Could not read ~/.claude/settings.json.")
            case .existingStatusLine:
                return Copy.text("Claude Code の statusline がすでに設定されています。上書きせず中止しました。", "Claude Code already has a statusline. No changes were made.")
            }
        }
    }
}

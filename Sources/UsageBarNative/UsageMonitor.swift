import Foundation
import SwiftUI

struct ProviderUsage: Sendable {
    var usedPercent: Double?
    var secondaryUsedPercent: Double? = nil
    var resetsAt: Date?
    var detail: String

    static let loading = ProviderUsage(usedPercent: nil, secondaryUsedPercent: nil, resetsAt: nil, detail: Copy.text("読み込み中…", "Loading…"))

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
            codex = await codexUsage
            claude = await claudeUsage
            refreshedAt = .now
            isRefreshing = false
        }
    }

    deinit { refreshTask?.cancel() }
}

enum CodexUsageReader {
    static func read() async -> ProviderUsage {
        do {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "app-server"]
            process.standardInput = input
            process.standardOutput = output

            try process.run()
            defer {
                if process.isRunning {
                    process.terminate()
                }
            }

            let initialize = "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"UsageBarNative\",\"version\":\"0.1.0\"}}}\n"
            input.fileHandleForWriting.write(Data(initialize.utf8))

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
                    let percent = primary["usedPercent"] as? Double
                else { continue }

                let secondary = (rateLimits["secondary"] as? [String: Any])?["usedPercent"] as? Double
                let reset = (primary["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                return ProviderUsage(usedPercent: percent, secondaryUsedPercent: secondary, resetsAt: reset, detail: "")
            }

            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: Copy.text("Codex の利用状況を取得できませんでした", "Could not retrieve Codex usage"))
        } catch {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: Copy.text("codex app-server を起動できませんでした", "Could not start codex app-server"))
        }
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

import Foundation
import SwiftUI

struct ProviderUsage: Sendable {
    var usedPercent: Double?
    var resetsAt: Date?
    var detail: String

    static let loading = ProviderUsage(usedPercent: nil, resetsAt: nil, detail: "読み込み中…")

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

    var menuBarTitle: String {
        let providers = [("Cdx", codex), ("Cl", claude)]
        let values = providers.compactMap { name, usage in
            usage.usedPercent.map { "\(name) \($0.formatted(.number.precision(.fractionLength(0))))%" }
        }
        return values.isEmpty ? "Quota —" : values.joined(separator: " · ")
    }

    var menuBarSymbol: String {
        let percentages = [codex.usedPercent, claude.usedPercent].compactMap { $0 }
        guard !percentages.isEmpty else { return "chart.bar" }
        return percentages.contains(where: { $0 >= 90 }) ? "exclamationmark.triangle.fill" : "chart.bar.fill"
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
            async let claudeUsage = ClaudeLocalUsageReader.read()
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

                let reset = (primary["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                return ProviderUsage(usedPercent: percent, resetsAt: reset, detail: "")
            }

            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: "Codex の利用状況を取得できませんでした")
        } catch {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: "codex app-server を起動できませんでした")
        }
    }
}

enum ClaudeLocalUsageReader {
    static func read() async -> ProviderUsage {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/rate_limits_cache.json")
        guard let data = try? Data(contentsOf: path) else {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: "ローカルの利用量キャッシュはまだありません")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: "Claude のローカルキャッシュを読めませんでした")
        }

        // Claude Code のキャッシュ形式は公開契約ではないため、既知の形式だけを控えめに扱う。
        for key in ["five_hour", "fiveHour", "session"] {
            if let window = object[key] as? [String: Any], let percent = window["utilization"] as? Double {
                return ProviderUsage(usedPercent: percent, resetsAt: nil, detail: "")
            }
        }
        return ProviderUsage(usedPercent: nil, resetsAt: nil, detail: "対応するローカル利用量形式が見つかりません")
    }
}

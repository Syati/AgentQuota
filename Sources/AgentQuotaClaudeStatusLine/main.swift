import Foundation

struct UsageSnapshot: Encodable {
    let cacheVersion: Int
    let fiveHourUsedPercent: Double?
    let sevenDayUsedPercent: Double?
    let resetsAt: Double?
}

struct MetricPreferences: Decodable {
    let showFiveHour: Bool
    let showSevenDay: Bool
}

struct WrapperConfiguration: Decodable {
    let originalCommand: String?
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard
    let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
    let model = findValue(named: "display_name", in: object) as? String
else {
    print("[Claude]")
    exit(0)
}

let rateLimits = findValue(named: "rate_limits", in: object) as? [String: Any]
let fiveHour = rateLimits.flatMap { preferredWindow(named: "five_hour", in: $0) }
    ?? rateLimits.flatMap { preferredWindow(named: "fiveHour", in: $0) }
let week = rateLimits.flatMap { preferredWindow(named: "seven_day", in: $0) }
    ?? rateLimits.flatMap { preferredWindow(named: "sevenDay", in: $0) }
let usedPercent = fiveHour.flatMap { number(in: $0, keys: ["used_percentage", "usedPercent", "utilization"]) }
let weekPercent = week.flatMap { number(in: $0, keys: ["used_percentage", "usedPercent", "utilization"]) }
let resetsAt = fiveHour.flatMap { number(in: $0, keys: ["resets_at", "resetsAt"]) }
let directory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/AgentQuota")
let file = directory.appending(path: "claude-usage.json")
let preferencesFile = directory.appending(path: "claude-preferences.json")
let preferences = (try? Data(contentsOf: preferencesFile)).flatMap { try? JSONDecoder().decode(MetricPreferences.self, from: $0) }
let showFiveHour = preferences?.showFiveHour ?? true
let showSevenDay = preferences?.showSevenDay ?? true
let selectedFiveHour = showFiveHour ? usedPercent : nil
let selectedWeek = showSevenDay ? weekPercent : nil
let selectedReset = selectedFiveHour == nil ? nil : resetsAt

do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if selectedFiveHour != nil || selectedWeek != nil {
        let selectedSnapshot = UsageSnapshot(cacheVersion: 2, fiveHourUsedPercent: selectedFiveHour, sevenDayUsedPercent: selectedWeek, resetsAt: selectedReset)
        let data = try JSONEncoder().encode(selectedSnapshot)
        try data.write(to: file, options: .atomic)
    }
} catch {
    // Claude Code の描画を止めないため、保存エラーは表示に反映しない。
}

var limits = ""
if let selectedFiveHour {
    limits = "5h: \(selectedFiveHour.formatted(.number.precision(.fractionLength(0))))%"
}
if let selectedWeek {
    limits += "\(limits.isEmpty ? "" : " ")7d: \(selectedWeek.formatted(.number.precision(.fractionLength(0))))%"
}
let agentQuotaOutput = limits.isEmpty ? "[\(model)]" : "[\(model)] | \(limits)"
let wrapperFile = directory.appending(path: "claude-wrapper.json")
let originalCommand = (try? Data(contentsOf: wrapperFile)).flatMap { try? JSONDecoder().decode(WrapperConfiguration.self, from: $0).originalCommand }

if let originalCommand, !originalCommand.isEmpty {
    let process = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", originalCommand]
    process.standardInput = stdin
    process.standardOutput = stdout
    do {
        try process.run()
        stdin.fileHandleForWriting.write(input)
        stdin.fileHandleForWriting.closeFile()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if !output.isEmpty {
            FileHandle.standardOutput.write(output)
        } else {
            print(agentQuotaOutput)
        }
    } catch {
        print(agentQuotaOutput)
    }
} else {
    print(agentQuotaOutput)
}

func preferredWindow(named name: String, in rateLimits: [String: Any]) -> [String: Any]? {
    if let window = rateLimits[name] as? [String: Any] {
        return window
    }
    return nil
}

func findValue(named name: String, in object: [String: Any]) -> Any? {
    if let value = object[name] { return value }
    for value in object.values {
        if let nested = value as? [String: Any], let found = findValue(named: name, in: nested) {
            return found
        }
    }
    return nil
}

func number(in object: [String: Any], keys: [String]) -> Double? {
    for key in keys {
        if let value = object[key] as? Double { return value }
        if let value = object[key] as? Int { return Double(value) }
        if let value = object[key] as? String, let number = Double(value) { return number }
    }
    return nil
}

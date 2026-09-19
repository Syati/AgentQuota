import AppKit
import SwiftUI

@main
struct UsageBarNativeApp: App {
    @StateObject private var monitor = UsageMonitor()
    @AppStorage("showCodex") private var showCodex = true
    @AppStorage("showClaude") private var showClaude = true

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(monitor: monitor, showCodex: showCodex, showClaude: showClaude)
        } label: {
            HStack(spacing: 4) {
                Text(monitor.menuBarTitle(showCodex: showCodex, showClaude: showClaude))
                if monitor.hasUsageWarning(showCodex: showCodex, showClaude: showClaude) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .help(monitor.menuBarTooltip(showCodex: showCodex, showClaude: showClaude))
        }
        .menuBarExtraStyle(.window)

        Window(Copy.text("AgentQuota 設定", "AgentQuota Settings"), id: "settings") {
            SettingsWindow()
        }
        .windowResizability(.contentSize)
    }
}

private struct UsagePopover: View {
    @ObservedObject var monitor: UsageMonitor
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appLanguage") private var appLanguage = "system"
    let showCodex: Bool
    let showClaude: Bool

    var body: some View {
        usageView
        .padding()
        .frame(width: 330)
        .task { monitor.start() }
    }

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("AgentQuota")
                    .font(.headline)
                if let refreshedAt = monitor.refreshedAt {
                    Text(refreshedAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                        .fixedSize()
                        .help(Copy.text("最終更新時刻", "Last updated"))
                }
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Copy.text("更新", "Refresh"))
                .disabled(monitor.isRefreshing)
                Spacer()
                Button(Copy.text("設定", "Settings")) {
                    openWindow(id: "settings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                        let title = Copy.text("AgentQuota 設定", "AgentQuota Settings")
                        if let window = NSApp.windows.first(where: { $0.title == title }) {
                            window.level = .floating
                            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                }
                .font(.caption)
                Button(Copy.text("終了", "Quit"), role: .destructive) {
                    NSApp.terminate(nil)
                }
                .font(.caption)
            }

            UsageTable(codex: monitor.codex, claude: monitor.claude, showCodex: showCodex, showClaude: showClaude)
        }
    }
}

private struct UpdateView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var updateChecker = UpdateChecker()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.text("アップデート", "Update"))
                .font(.title3.weight(.semibold))
            Text(Copy.text("GitHub の公開リリースを確認します。署名なしの DMG は自動インストールせず、リリースページから手動で更新します。", "Check public GitHub releases. Unsigned DMGs are not installed automatically; update manually from the release page."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text(updateChecker.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Copy.text("確認", "Check")) {
                    updateChecker.check()
                }
                .font(.caption)
                .disabled({
                    if case .checking = updateChecker.state { return true }
                    return false
                }())
            }

            Button(Copy.text("GitHub Releases を開く", "Open GitHub Releases")) {
                if let url = URL(string: "https://github.com/Syati/AgentQuota/releases") {
                    openURL(url)
                }
            }
            .font(.caption)

            if let availableURL = updateChecker.availableURL {
                Button(Copy.text("GitHub のリリースを開く", "Open GitHub Release")) {
                    openURL(availableURL)
                }
                .font(.caption)
            }

            Spacer()
        }
        .onAppear {
            updateChecker.check()
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About AgentQuota")
                .font(.headline)

            Text(Copy.text("Codex と Claude Code の利用量を、メニューバーから確認するためのローカルアプリです。", "A local app for checking Codex and Claude Code usage from the menu bar."))
                .font(.subheadline)

            Divider()

            Text(Copy.text("データの取り扱い", "Data handling"))
                .font(.subheadline.weight(.semibold))
            Text(Copy.text("Codex は公式の app-server を通じて利用量を読みます。Claude Code は statusline が渡す利用枠情報だけをローカルに保存し、Keychain・OAuth トークン・非公式 API にはアクセスしません。", "Codex usage is read through the official app-server. Claude Code only stores the quota data provided by its statusline locally; it does not access Keychain, OAuth tokens, or unofficial APIs."))
            Text(Copy.text("Claude Code 連携を設定すると ~/.claude/settings.json の statusline を AgentQuota のラッパーにします。元のコマンドは保存し、同じ入力を渡して実行します。テレメトリー、自動更新、ログイン画面はありません。", "When enabled, AgentQuota wraps the statusline in ~/.claude/settings.json, preserves the original command, and passes it the same input. There is no telemetry, automatic update, or login screen."))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private enum SettingsSection: Hashable {
    case settings
    case update
    case about
}

private struct SettingsWindow: View {
    @State private var selection: SettingsSection? = .settings

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(Copy.text("設定", "Settings"), systemImage: "gearshape")
                    .tag(SettingsSection.settings)
                Label("Update", systemImage: "arrow.down.circle")
                    .tag(SettingsSection.update)
                Label("About", systemImage: "info.circle")
                    .tag(SettingsSection.about)
            }
            .navigationTitle("AgentQuota")
            .frame(minWidth: 150)
        } detail: {
            Group {
                switch selection {
                case .update:
                    UpdateView()
                case .about:
                    AboutView()
                default:
                    SettingsView()
                }
            }
            .padding()
            .frame(minWidth: 360, alignment: .topLeading)
        }
        .frame(width: 600, height: 380)
        .onAppear {
            activateSettingsWindow()
        }
    }

    private func activateSettingsWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let title = Copy.text("AgentQuota 設定", "AgentQuota Settings")
            if let window = NSApp.windows.first(where: { $0.title == title }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

}

private struct SettingsView: View {
    @State private var message: String?
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("showCodex") private var showCodex = true
    @AppStorage("showClaude") private var showClaude = true
    @State private var showFiveHour = ClaudeStatusLineIntegration.metricPreferences.showFiveHour
    @State private var showSevenDay = ClaudeStatusLineIntegration.metricPreferences.showSevenDay
    @State private var originalCommand = ClaudeStatusLineIntegration.userCommand ?? ""

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
            Text("AgentQuota")
                .font(.title3.weight(.semibold))

            Text(Copy.text("一般", "General"))
                .font(.subheadline.weight(.semibold))
            Picker(Copy.text("言語", "Language"), selection: $appLanguage) {
                Text(Copy.text("システム設定", "System"))
                    .tag("system")
                Text("日本語")
                    .tag("ja")
                Text("English")
                    .tag("en")
            }

            Text(Copy.text("表示するサービス", "Services to display"))
                .font(.subheadline.weight(.semibold))
            Text(Copy.text("メニューバーとポップオーバーに表示する利用量を選択します。", "Choose which usage meters appear in the menu bar and popover."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(Copy.text("Codex の利用量を表示", "Show Codex usage"), isOn: $showCodex)
            Toggle(Copy.text("Claude Code の利用量を表示", "Show Claude Code usage"), isOn: $showClaude)

            Text(Copy.text("起動", "Startup"))
                .font(.subheadline.weight(.semibold))
            Toggle(Copy.text("ログイン時に AgentQuota を起動", "Launch AgentQuota at login"), isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { enabled in
                    do {
                        try LoginItem.setEnabled(enabled)
                        message = nil
                    } catch {
                        message = Copy.text("ログイン時起動を変更できません。配布版アプリから設定してください。", "Could not change launch-at-login. Configure it from the installed app.")
                    }
                }
            ))

            Divider()

            Text(Copy.text("Claude Code 連携", "Claude Code integration"))
                .font(.subheadline.weight(.semibold))
            HStack {
                Text("statusline")
                Spacer()
                Text(ClaudeStatusLineIntegration.statusDescription)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Text(Copy.text("Claude Code の statusline を利用して、画面への表示と AgentQuota への保存を同時に行います。", "Claude Code's statusline is used for both its display and saving data to AgentQuota."))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(Copy.text("既存 statusline コマンド（任意）", "Existing statusline command (optional)"), text: $originalCommand)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            Toggle(Copy.text("5時間枠", "5-hour window"), isOn: $showFiveHour)
            Toggle(Copy.text("週次枠", "7-day window"), isOn: $showSevenDay)

            Button(Copy.text("既存の statusline と連携", "Connect existing statusline")) {
                do {
                    guard showFiveHour || showSevenDay else {
                        message = Copy.text("少なくとも1つの quota 指標を選択してください。", "Select at least one quota metric.")
                        return
                    }
                    try ClaudeStatusLineIntegration.saveMetricPreferences(showFiveHour: showFiveHour, showSevenDay: showSevenDay)
                    try ClaudeStatusLineIntegration.install(preserving: originalCommand.isEmpty ? nil : originalCommand)
                    message = Copy.text("設定しました。Claude Code を一度操作してください。", "Saved. Use Claude Code once to refresh the values.")
                } catch {
                    message = error.localizedDescription
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                .foregroundStyle(.secondary)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
    }
}

private struct UsageTable: View {
    let codex: ProviderUsage
    let claude: ProviderUsage
    let showCodex: Bool
    let showClaude: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("")
                    .frame(width: 70)
                Text(Copy.text("5時間枠", "5-hour"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Copy.text("週次枠", "7-day"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if showCodex { UsageTableRow(title: "Codex", usage: codex) }
            if showClaude { UsageTableRow(title: "Claude", usage: claude) }
        }
    }
}

private struct UsageTableRow: View {
    let title: String
    let usage: ProviderUsage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 70, alignment: .leading)
            QuotaCell(percentage: usage.usedPercent, resetsAt: usage.resetsAt)
            QuotaCell(percentage: usage.secondaryUsedPercent, resetsAt: nil)
        }
    }
}

private struct QuotaCell: View {
    let percentage: Double?
    let resetsAt: Date?

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.22))
                    if let percentage {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(width: proxy.size.width * min(max(percentage, 0), 100) / 100)
                    }
                    if let percentage {
                        HStack(spacing: 2) {
                    Text("\(percentage.formatted(.number.precision(.fractionLength(0))))%")
                    if let resetsAt {
                        let resetText = resetsAt.formatted(.dateTime.hour().minute())
                        Text(Copy.text("（復帰 \(resetText)）", "(resets \(resetText))"))
                    }
                        }
                        .frame(maxWidth: .infinity)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 1)
                    }
                }
            }
        }
        .frame(height: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        guard let percentage else { return .gray }
        return percentage >= 90 ? .red : percentage >= 70 ? .orange : .accentColor
    }
}

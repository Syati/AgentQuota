import SwiftUI

@main
struct UsageBarNativeApp: App {
    @StateObject private var monitor = UsageMonitor()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(monitor: monitor)
        } label: {
            Label(monitor.menuBarTitle, systemImage: monitor.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct UsagePopover: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AgentQuota")
                .font(.headline)

            UsageCard(title: "Codex", usage: monitor.codex)
            UsageCard(title: "Claude Code", usage: monitor.claude)

            HStack {
                if let refreshedAt = monitor.refreshedAt {
                    Text("更新: \(refreshedAt, format: .dateTime.hour().minute())")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("更新") { monitor.refresh() }
                    .disabled(monitor.isRefreshing)
            }
            .font(.caption)

            Text("Claude Code はローカルキャッシュだけを読みます。Keychain と Claude API にはアクセスしません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 330)
        .task { monitor.start() }
    }
}

private struct UsageCard: View {
    let title: String
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(usage.statusText).foregroundStyle(.secondary)
            }

            if let percentage = usage.usedPercent {
                ProgressView(value: percentage, total: 100)
                    .tint(percentage >= 90 ? .red : percentage >= 70 ? .orange : .accentColor)
                HStack {
                    Text("\(percentage.formatted(.number.precision(.fractionLength(0))))% 使用")
                    Spacer()
                    if let resetsAt = usage.resetsAt {
                        Text("復帰 \(resetsAt, format: .dateTime.hour().minute())")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(usage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

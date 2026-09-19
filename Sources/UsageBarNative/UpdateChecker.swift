import Foundation
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate
        case available(tag: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    var statusText: String {
        switch state {
        case .idle:
            return Copy.text("未確認", "Not checked")
        case .checking:
            return Copy.text("確認中…", "Checking…")
        case .upToDate:
            return Copy.text("最新です（v\(currentVersion)）", "You're up to date (v\(currentVersion))")
        case let .available(tag, _):
            return Copy.text("\(tag) が利用可能です", "\(tag) is available")
        case .failed:
            return Copy.text("確認できませんでした", "Could not check for updates")
        }
    }

    var availableURL: URL? {
        guard case let .available(_, url) = state else { return nil }
        return url
    }

    private let currentVersion: String
    private let endpoint = URL(string: "https://api.github.com/repos/Syati/AgentQuota/releases/latest")!

    init() {
        currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.3.2"
    }

    func check() {
        if case .checking = state { return }
        state = .checking

        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: endpoint)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("AgentQuota/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !release.draft, !release.prerelease, let url = release.htmlURL else {
                    state = .upToDate
                    return
                }
                state = isNewer(release.tagName, than: currentVersion) ? .available(tag: release.tagName, url: url) : .upToDate
            } catch {
                state = .failed
            }
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = versionParts(remote)
        let localParts = versionParts(local)
        return localParts.lexicographicallyPrecedes(remoteParts)
    }

    private func versionParts(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
            .padding(toLength: 3, withPad: 0, expectedCount: 3)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

private extension Array where Element == Int {
    func padding(toLength length: Int, withPad element: Int, expectedCount: Int) -> [Int] {
        guard count < length else { return Array(prefix(length)) }
        return self + Array(repeating: element, count: length - count)
    }
}

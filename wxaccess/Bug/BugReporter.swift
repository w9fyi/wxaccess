import Foundation
import OSLog
import Security

// Singleton service that collects diagnostic data and files GitHub issues.
// Matches the *Fetcher singleton pattern used throughout the codebase.
final class BugReporter: @unchecked Sendable {
    static let shared = BugReporter()
    private init() {}

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "BugReporter")

    // MARK: - Keychain

    private let keychainService = "net.ai5os.wxaccess.github-pat"
    private let keychainAccount = "w9fyi"

    private func loadPAT() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else { return nil }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func savePAT(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let checkStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if checkStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else {
            let attrs: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        }
    }

    func hasPAT() -> Bool {
        (try? loadPAT()) != nil
    }

    // MARK: - OSLogStore

    // Collects the 50 most-recent log entries from this app's subsystem
    // over the past 5 minutes. Runs detached to avoid blocking the main actor.
    func collectLogs() async -> [String] {
        await Task.detached(priority: .utility) {
            guard let store = try? OSLogStore.local() else { return [] }
            let since = store.position(date: Date().addingTimeInterval(-300))
            let pred  = NSPredicate(format: "subsystem == %@", "net.ai5os.wxaccess")
            guard let entries = try? store.getEntries(at: since, matching: pred) else { return [] }
            let fmt = ISO8601DateFormatter()
            var lines: [String] = []
            for entry in entries {
                guard let e = entry as? OSLogEntryLog else { continue }
                lines.append("[\(fmt.string(from: e.date))] [\(e.category)] \(e.composedMessage)")
            }
            return Array(lines.suffix(50))
        }.value
    }

    // MARK: - Diagnostics JSON

    // Must be called on @MainActor (reads AppState properties directly).
    @MainActor
    func buildDiagnosticJSON(state: AppState) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVer   = ProcessInfo.processInfo.operatingSystemVersionString

        let dict: [String: Any] = [
            "selectedSites":  state.selectedSites.map { $0.icao },
            "product":        state.selectedProduct.rawValue,
            "tiltIndex":      state.tiltIndex,
            "isAnimating":    state.isAnimating,
            "showSatellite":  state.showSatellite,
            "showModelLayer": state.showModelLayer,
            "colorPalette":   "\(state.colorPalette)",
            "lastError":      state.errorMessage ?? NSNull(),
            "appVersion":     "\(version) (\(build))",
            "macOS":          osVer,
            "timestamp":      ISO8601DateFormatter().string(from: .now)
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - GitHub API

    // Top-level submission entry point.
    // If providedPAT is non-nil it is saved to Keychain and used.
    // Otherwise the stored Keychain PAT is used.
    // Throws BugReporterError.noToken when neither is present.
    func submit(description: String, pat providedPAT: String?,
                appState: AppState) async throws -> URL {
        let token: String
        if let p = providedPAT, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try savePAT(p)
            token = p
        } else if let stored = try loadPAT() {
            token = stored
        } else {
            throw BugReporterError.noToken
        }

        async let diagJSON = buildDiagnosticJSON(state: appState)
        async let logLines = collectLogs()
        return try await fileIssue(description: description,
                                   diagnosticJSON: diagJSON,
                                   logLines: logLines,
                                   pat: token)
    }

    private func fileIssue(description: String, diagnosticJSON: String,
                            logLines: [String], pat: String) async throws -> URL {
        let title = String(
            description.components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(72) ?? description.prefix(72)
        )

        let logsBlock = logLines.isEmpty
            ? "_No log entries collected._"
            : logLines.joined(separator: "\n")

        let body = """
        ## What were you doing?

        \(description)

        ## App State

        ```json
        \(diagnosticJSON)
        ```

        ## Recent Logs

        ```
        \(logsBlock)
        ```
        """

        let payload: [String: Any] = [
            "title":  title,
            "body":   body,
            "labels": ["bug"]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        guard let url = URL(string: "https://api.github.com/repos/w9fyi/wxaccess/issues") else {
            throw URLError(.badURL)
        }
        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = payloadData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(pat)",               forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28",                  forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json",            forHTTPHeaderField: "Content-Type")
        request.setValue("wxaccess/\(appVersionString()) (net.ai5os.wxaccess)",
                                                        forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 201 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw BugReporterError.apiError(http.statusCode, msg)
        }

        struct Response: Decodable {
            let htmlUrl: String
            enum CodingKeys: String, CodingKey { case htmlUrl = "html_url" }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let issueURL = URL(string: decoded.htmlUrl) else { throw URLError(.badURL) }
        logger.info("Bug report filed: \(issueURL.absoluteString)")
        return issueURL
    }

    private func appVersionString() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v).\(b)"
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let s): "Keychain error \(s)"
        case .encodingFailed:          "Could not encode token as UTF-8"
        }
    }
}

enum BugReporterError: Error, LocalizedError {
    case noToken
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noToken:                     "No GitHub token found. Please enter your personal access token."
        case .apiError(let code, let msg): "GitHub API error \(code): \(msg)"
        }
    }
}

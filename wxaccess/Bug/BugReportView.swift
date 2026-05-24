import SwiftUI
import AppKit

enum BugReportPhase: Equatable {
    case idle
    case submitting
    case success(URL)
    case failure(String)

    static func == (lhs: BugReportPhase, rhs: BugReportPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.submitting, .submitting): return true
        case (.success(let a), .success(let b)):         return a == b
        case (.failure(let a), .failure(let b)):         return a == b
        default:                                         return false
        }
    }
}

struct BugReportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss)    private var dismiss
    @Environment(\.openURL)    private var openURL

    @State private var description:  String          = ""
    @State private var patEntry:     String          = ""
    @State private var showPATField: Bool            = false
    @State private var phase:        BugReportPhase  = .idle

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch phase {
                    case .idle:
                        idleContent
                    case .submitting:
                        submittingContent
                    case .success(let url):
                        successContent(url: url)
                    case .failure(let msg):
                        failureContent(message: msg)
                    }
                }
                .padding(20)
            }
            Divider()
            footerButtons
        }
        .frame(minWidth: 480, minHeight: 380)
        .onAppear {
            showPATField = !BugReporter.shared.hasPAT()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "ladybug.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("File a Bug Report")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File a bug report")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Idle form

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe what you were doing when the problem occurred:")
                .font(.subheadline.weight(.medium))

            TextEditor(text: $description)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel("Bug description")
                .accessibilityHint("Describe what went wrong. The first line becomes the issue title on GitHub.")

            if showPATField {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Personal Access Token")
                        .font(.caption.weight(.semibold))
                    Text("Required for first-time setup. Create a fine-grained token with Issues: Write scope on w9fyi/wxaccess only. Saved securely to your Keychain — you will not be asked again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("ghp_…", text: $patEntry)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("GitHub personal access token")
                        .accessibilityHint("Enter a fine-grained PAT with Issues write scope. Saved to Keychain after first use.")
                }
            }

            Divider()

            DisclosureGroup("Diagnostics that will be included") {
                Text(BugReporter.shared.buildDiagnosticJSON(state: appState))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel("Diagnostic data preview")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Submitting

    private var submittingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Filing bug report…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filing bug report, please wait")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Success

    private func successContent(url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Bug report filed successfully!")
                .font(.headline)
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Open in Browser") {
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open bug report in browser")
            .accessibilityHint("Opens the GitHub issue in your default browser")
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Failure

    private func failureContent(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Submission failed")
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                phase = .idle
            }
            .accessibilityLabel("Try filing the bug report again")
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Footer buttons

    private var footerButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel and close bug report")
                .disabled(phase == .submitting)

            Spacer()

            if case .success = phase {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Close bug report sheet")
            } else if phase != .submitting {
                Button("Submit") { submitReport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitDisabled)
                    .accessibilityLabel("Submit bug report")
                    .accessibilityHint("Files a GitHub issue with your description and diagnostic data")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var submitDisabled: Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (showPATField && patEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Submit action

    private func submitReport() {
        phase = .submitting
        announce("Filing bug report")

        let capturedDesc = description
        let capturedPAT  = showPATField ? patEntry : nil

        Task {
            do {
                let url = try await BugReporter.shared.submit(
                    description: capturedDesc,
                    pat: capturedPAT,
                    appState: appState
                )
                phase = .success(url)
                appState.bugReportURL = url
                announce("Bug report filed successfully")
            } catch {
                phase = .failure(error.localizedDescription)
                announce("Bug report failed: \(error.localizedDescription)")
            }
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }
}

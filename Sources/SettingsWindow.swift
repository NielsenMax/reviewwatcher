import AppKit
import SwiftUI

/// The single settings window, built on first use and brought forward after that.
final class SettingsWindow {
    private let settings: Settings
    private let updater: Updater
    private var window: NSWindow?

    init(settings: Settings, updater: Updater) {
        self.settings = settings
        self.updater = updater
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(settings: settings, updater: updater))
        host.sizingOptions = .minSize
        let window = NSWindow(contentViewController: host)
        window.title = "Review Watcher Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 720))
        window.center()
        return window
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var updater: Updater

    private static let standardIntervals: [TimeInterval] = [30, 60, 120, 300, 600, 900]

    var body: some View {
        Form {
            Section {
                LabeledContent("GitLab", value: settings.config.host)
                LabeledContent("User", value: "@\(settings.config.username)")
            } header: {
                Text("Account")
            } footer: {
                Text("Set by install.sh from your glab login. To change them, edit config.json and restart the watcher.")
                    .foregroundStyle(.secondary)
            }

            Section("Polling") {
                Picker("Check every", selection: $settings.config.pollInterval) {
                    ForEach(intervals, id: \.self) { seconds in
                        Text(Self.describe(seconds)).tag(seconds)
                    }
                }
            }

            Section("Notify me about reviews when") {
                Toggle("I'm asked to review a merge request", isOn: $settings.config.notifyOnNewReviewRequest)
                Toggle("New commits remove my approval", isOn: $settings.config.notifyOnApprovalRemoved)
                Toggle("A pipeline that was failing passes", isOn: $settings.config.notifyOnPipelineFixed)
                Toggle("A merge request I review gets commits or comments", isOn: $settings.config.notifyOnActivity)
                Toggle("Requests are already waiting when the watcher starts", isOn: $settings.config.notifyBacklogOnFirstRun)
            }

            Section {
                Picker("Pipeline", selection: $settings.config.notifyOnlyWhen.pipeline) {
                    Text("In any state").tag(NotificationGate.Pipeline.any)
                    Text("Has not failed").tag(NotificationGate.Pipeline.notFailed)
                    Text("Has passed").tag(NotificationGate.Pipeline.passed)
                }
                Toggle("Has no conflicts", isOn: $settings.config.notifyOnlyWhen.requiresNoConflicts)
                Toggle("Is not a draft", isOn: $settings.config.notifyOnlyWhen.requiresNotDraft)
            } header: {
                Text("Only when the merge request")
            } footer: {
                Text("""
                    A review request or removed approval that does not qualify yet notifies as soon as it does, \
                    unless you approve first. A merge request without a pipeline passes the pipeline check.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Releases from develop to main or master", isOn: $settings.config.autoApproveReleases)
                Toggle("Version bumps in Kubernetes manifests", isOn: $settings.config.autoApproveVersionBumps)
            } header: {
                Text("Approve automatically")
            } footer: {
                Text("""
                    A version bump changes nothing but kustomize newTag or container image lines in YAML files, \
                    each to a version like 1.2.3 in the same image. Drafts are left alone, every approval notifies, \
                    and one you revoke stays revoked until new commits arrive.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Celebrate on screen", isOn: $settings.config.celebrateMerges)
            } header: {
                Text("When a merge from the menu bar lands")
            } footer: {
                Text("A gilded bull charges across the screen in use, with a bellow. Clicks go through it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $settings.collapsedPatternsText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 64)
            } header: {
                Text("Diff window: start collapsed when the path matches")
            } footer: {
                Text("""
                    One glob per line, matched against the whole path without regard to case; * also crosses /. \
                    Generated files always start collapsed. Applies to diff windows opened afterwards.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                if settings.config.jira.isSetUp {
                    LabeledContent("Jira", value: settings.config.jira.site)
                    LabeledContent("You", value: settings.config.jira.email)
                    LabeledContent("Following", value: settings.config.jira.epics.isEmpty
                                   ? "no epics" : settings.config.jira.epics.joined(separator: ", "))
                } else {
                    Text("Log in with acli jira auth login, then run install.sh again.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Epic tab")
            } footer: {
                Text("""
                    Follow and close epics from the search box in the Epic tab. Each one brings its children and \
                    their subtasks. Site and user come from your acli login.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("A ticket is added to the epic", isOn: $settings.config.jira.notifyOnNewTicket)
                Toggle("A ticket changes status", isOn: $settings.config.jira.notifyOnStatusChange)
                Toggle("A ticket is assigned or unassigned", isOn: $settings.config.jira.notifyOnAssigneeChange)
                Toggle("Someone else comments", isOn: $settings.config.jira.notifyOnComment)
            } header: {
                Text("Notify me about the epic when")
            } footer: {
                Text("""
                    Moves and assignments you make from the menu bar stay quiet. Ones you make in Jira itself \
                    notify like anyone else's: Jira does not say who made a change without reading its history.
                    """)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.config.jira.isSetUp)

            Section {
                LabeledContent("Version", value: updater.runningVersion)
                LabeledContent("Latest") { updateStatus }
                Button("Check now", action: updater.checkNow)
            } header: {
                Text("Updates")
            } footer: {
                Text("""
                    Checks GitHub for a newer release tag every hour. Updating, from the menu bar, builds that \
                    release from source on this Mac and restarts into it.
                    """)
                    .foregroundStyle(.secondary)
            }

            if let failure = settings.saveFailure {
                Text(failure).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 360)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.state {
        case .unchecked:
            Text("Checking…").foregroundStyle(.secondary)
        case .upToDate(let checkedAt):
            Text("Up to date · checked \(checkedAt.formatted(date: .omitted, time: .shortened))")
        case .checkFailed(let message), .installFailed(_, let message):
            Text(message).foregroundStyle(.red).lineLimit(3).help(message)
        case .available(let release):
            Text("\(release.version.description) is available from the menu bar")
        case .installing(_, let step):
            Text(step)
        }
    }

    /// A value set by hand in config.json stays selectable even when it is not one of the standard steps.
    private var intervals: [TimeInterval] {
        Array(Set(Self.standardIntervals + [settings.config.pollInterval])).sorted()
    }

    private static func describe(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        guard whole >= 60, whole % 60 == 0 else { return "\(whole) seconds" }
        return whole == 60 ? "1 minute" : "\(whole / 60) minutes"
    }
}

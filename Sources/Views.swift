import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: RunnerStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showSettings || store.org.isEmpty {
                SettingsView(store: store) { showSettings = false }
            } else {
                content
            }
            Divider()
            footer
        }
        .frame(width: 400)
        // The popover window becomes key each time the menu bar icon is clicked, but on the first
        // click it does so before this view subscribes; onAppear covers that one.
        // refresh() ignores overlapping calls, so both firing is harmless.
        .onAppear { Task { await store.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await store.refresh() }
        }
    }

    private var header: some View {
        HStack {
            Text(store.org.isEmpty ? "Actions Runners" : store.org).font(.headline)
            Spacer()
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("Refresh now")
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        if store.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking runners…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } else {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(12)
                Divider()
            }
            if store.rows.isEmpty {
                Text(store.lastUpdated == nil ? "Loading…" : "No self-hosted runners in this org.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                HStack(spacing: 14) {
                    ForEach(RunnerState.allCases, id: \.self) { state in
                        StateCount(state: state, count: store.rows.filter { $0.state == state }.count)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                // A ScrollView has no intrinsic height in a MenuBarExtra window and collapses to zero,
                // so only scroll (at a fixed height) once the list is long.
                if store.rows.count > 8 {
                    ScrollView { runnerList }.frame(height: 480)
                } else {
                    runnerList
                }
            }
        }
    }

    private var runnerList: some View {
        VStack(spacing: 0) {
            ForEach(store.rows) { row in
                RunnerRowView(row: row)
                Divider()
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
            }
            if let remaining = store.rateLimitRemaining {
                Text("· API \(remaining) left")
            }
            Spacer()
            Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

extension RunnerState {
    var label: String { "\(self)" }

    var color: Color {
        switch self {
        case .busy: return .orange
        case .idle: return .green
        case .offline: return .gray
        }
    }
}

private struct StateCount: View {
    let state: RunnerState
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            Text("\(count) \(state.label)").font(.callout)
        }
    }
}

struct RunnerRowView: View {
    let row: RunnerRow
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(row.state.color).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.runner.name).font(.system(.body, design: .monospaced)).fontWeight(.medium)
                    Spacer()
                    Text(row.state.label).font(.caption).foregroundStyle(row.state.color)
                }
                if row.state == .busy { jobDetails }
                Text(labels).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering && jobURL != nil ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if let jobURL { NSWorkspace.shared.open(jobURL) } }
        .help(jobURL == nil ? "" : "Open job on GitHub")
    }

    @ViewBuilder private var jobDetails: some View {
        if let active = row.job {
            let job = active.job
            VStack(alignment: .leading, spacing: 2) {
                Text(active.repo).font(.callout).fontWeight(.semibold)
                Text([job.workflowName, job.name].compactMap { $0 }.joined(separator: " › "))
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let branch = job.headBranch {
                        Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                    }
                    if let started = job.startedAt {
                        Label { Text(started, style: .timer) } icon: { Image(systemName: "clock") }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            Text("Job not found (repo may be outside token's access)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var jobURL: URL? { row.job?.job.htmlUrl.flatMap(URL.init(string:)) }

    private var labels: String {
        row.runner.labels.map(\.name).filter { $0 != "self-hosted" }.joined(separator: " · ")
    }
}

struct SettingsView: View {
    @ObservedObject var store: RunnerStore
    let onDone: () -> Void

    @State private var org = ""
    @State private var token = Keychain.readToken() ?? ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            TextField("Organization", text: $org, prompt: Text("my-org"))
            SecureField("Token", text: $token, prompt: Text("optional — uses `gh auth token`"))
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Text("Token needs org admin, or a fine-grained token with “Self-hosted runners: read” on the org plus “Actions: read” on its repos.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(org.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .onAppear { org = store.org }
    }

    private func save() {
        store.org = org.trimmingCharacters(in: .whitespaces)
        Keychain.writeToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
        store.reconfigure()
        onDone()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

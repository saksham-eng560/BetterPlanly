//
//  SettingsView.swift
//  Planly
//
//  The Mac's address with "Test connection", reminder and badge options, and the agent toggle.
//

import SwiftUI

/// The server address field with a Test connection button; shared by Settings and Onboarding.
struct ServerAddressField: View {
    @Binding var address: String
    @State private var status: Status = .idle

    enum Status: Equatable { case idle, testing, ok(String), failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("http://My-MacBook.local:8000", text: $address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityLabel("Mac address")
            HStack {
                Button {
                    Task { await test() }
                } label: {
                    if status == .testing { ProgressView() } else { Text("Test connection") }
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || status == .testing)
                Spacer()
                switch status {
                case .ok(let text):
                    Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.lime).font(.footnote)
                case .failed(let text):
                    Label(text, systemImage: "xmark.octagon.fill").foregroundStyle(Palette.red).font(.footnote)
                default:
                    EmptyView()
                }
            }
        }
        .onChange(of: address) { status = .idle }
    }

    private func test() async {
        guard let client = APIClient(address: address) else {
            status = .failed("Not a valid address")
            return
        }
        status = .testing
        do {
            _ = try await client.health()
            address = client.server.absoluteString
            status = .ok("Connected")
        } catch {
            status = .failed(error.isOffline ? "Can't reach it" : error.userMessage)
        }
    }
}

struct SettingsView: View {
    @Environment(PlanStore.self) private var plan
    @State private var address = SharedStore.serverAddress
    @State private var reminders = SharedStore.remindersEnabled
    @State private var lead = SharedStore.reminderLeadMinutes
    @State private var badge = SharedStore.badgeEnabled
    @State private var react = SharedStore.reactToChanges

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ServerAddressField(address: $address)
                } header: {
                    Text("Your Mac")
                } footer: {
                    Text("Start Planly on your Mac with `make phone` and enter the address it prints. Use port 8080 if you run it with Docker. The iPhone must be on the same Wi-Fi.")
                }

                Section("Reminders") {
                    Toggle("Remind me before tasks", isOn: $reminders)
                    Picker("Remind me", selection: $lead) {
                        Text("At start time").tag(0)
                        Text("5 min before").tag(5)
                        Text("10 min before").tag(10)
                        Text("15 min before").tag(15)
                    }
                    .disabled(!reminders)
                    Toggle("Open tasks on the app icon", isOn: $badge)
                }

                Section {
                    Toggle("Let the agent react to my changes", isOn: $react)
                } header: {
                    Text("Agent")
                } footer: {
                    Text("After you tick or move tasks, the agent looks at the rest of your day and adjusts it. You can undo anything it changes.")
                }

                Section("About") {
                    LabeledContent("Model", value: plan.state?.agent.model ?? "—")
                    LabeledContent("Widget sharing", value: SharedStore.hasAppGroup ? "App Group" : "Widget has its own address")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .planlyScreen()
        }
        .onChange(of: address) { _, value in
            if let normalized = APIClient.normalize(value) { SharedStore.serverAddress = normalized }
        }
        .onSubmit { Task { await plan.refresh() } }
        .onChange(of: reminders) { _, value in
            SharedStore.remindersEnabled = value
            if value { Task { await Reminders.requestPermission() } }
            resync()
        }
        .onChange(of: lead) { _, value in SharedStore.reminderLeadMinutes = value; resync() }
        .onChange(of: badge) { _, value in SharedStore.badgeEnabled = value; resync() }
        .onChange(of: react) { _, value in SharedStore.reactToChanges = value }
        .onDisappear { Task { await plan.refresh() } }
    }

    private func resync() {
        Task { await Sync.afterRefresh(tasks: plan.tasks, today: plan.today) }
    }
}

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var address = SharedStore.serverAddress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "checklist")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Palette.label)
                    .accessibilityHidden(true)
                DisplayTitle(text: "Welcome to Planly")
                Text("Planly on your iPhone talks to the planner running on your Mac, over your home Wi-Fi. Your tasks, history and agent chats stay on the Mac and show up in both places.")
                    .foregroundStyle(Palette.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Mac's address").font(.headline).foregroundStyle(Palette.label)
                    Text("On your Mac, run `make phone` and type the address it prints.")
                        .font(.subheadline).foregroundStyle(Palette.tertiary)
                    ServerAddressField(address: $address)
                }
                .padding(16)
                .glassCard()

                Button {
                    Task { await finish() }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(Palette.ink)
                }
                .disabled(APIClient.normalize(address) == nil)
                .opacity(APIClient.normalize(address) == nil ? 0.5 : 1)

                Text("Planly will ask to find devices on your local network and to send you reminders.")
                    .font(.footnote)
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(24)
            .padding(.top, 40)
        }
        .background(Backdrop())
    }

    private func finish() async {
        guard let normalized = APIClient.normalize(address) else { return }
        SharedStore.serverAddress = normalized
        await Reminders.requestPermission()
        onFinish()
    }
}

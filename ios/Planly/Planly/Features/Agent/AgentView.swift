//
//  AgentView.swift
//  Planly
//
//  Chat with the planner's agent on your Mac: streaming replies, tool chips, change cards with Undo.
//

import SwiftUI

struct AgentView: View {
    @Environment(AgentStore.self) private var agent
    @Environment(PlanStore.self) private var plan
    @Environment(Router.self) private var router
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private static let suggestions = [
        "I'm behind — re-plan the rest of today",
        "What should I focus on next?",
        "How did this week go?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if agent.items.isEmpty {
                            intro
                        }
                        ForEach(agent.items) { item in
                            ChatRow(item: item).id(item.id)
                        }
                        if agent.running, !isStreamingText {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…").font(.footnote).foregroundStyle(Palette.tertiary)
                            }
                            .id("thinking")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: agent.items.count) { scrollToBottom(proxy) }
                .onChange(of: lastText) { scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy, animated: false) }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .planlyScreen()
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
            }
        }
        .task { await agent.load() }
        .onAppear(perform: takeDraft)
        .onChange(of: router.agentDraft) { takeDraft() }
    }

    private var isStreamingText: Bool {
        if case .assistant = agent.items.last { true } else { false }
    }

    private var lastText: Int {
        if case .assistant(_, let text) = agent.items.last { text.count } else { 0 }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func takeDraft() {
        guard !router.agentDraft.isEmpty else { return }
        draft = router.agentDraft
        router.agentDraft = ""
        composerFocused = true
    }

    private var header: some View {
        let info = plan.state?.agent
        return HStack(spacing: 6) {
            Circle()
                .fill(info?.reachable == true ? Palette.lime : Palette.red)
                .frame(width: 8, height: 8)
            Text(info?.model ?? "Agent").font(.headline).foregroundStyle(Palette.label)
            if agent.running || info?.busy == true {
                ProgressView().controlSize(.mini)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent \(info?.model ?? ""), \(info?.reachable == true ? "reachable" : "not reachable")\(agent.running ? ", working" : "")")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles").font(.title).foregroundStyle(Palette.label).accessibilityHidden(true)
            Text("Your planning agent").font(.title2.weight(.light)).foregroundStyle(Palette.label)
            Text("It runs on your Mac. Ask it to re-plan, find resources or review your week. It also notices when you tick or move tasks.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if draft.isEmpty && !composerFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            Button(suggestion) { agent.send(suggestion) }
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.label)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message the agent", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCard(radius: 20)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    private func send() {
        agent.send(draft)
        draft = ""
    }
}

private struct ChatRow: View {
    @Environment(PlanStore.self) private var plan
    let item: ChatItem

    var body: some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                    .textSelection(.enabled)
            }
        case .assistant(_, let text):
            HStack {
                Text(markdown(text))
                    .foregroundStyle(Palette.label)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCard(radius: 20)
                    .textSelection(.enabled)
                Spacer(minLength: 32)
            }
        case .event(_, let text):
            Label(AgentStore.eventSummary(text), systemImage: "bolt.fill")
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.1)))
                .frame(maxWidth: .infinity)
        case .error(_, let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Palette.label)
                .padding(12)
                .glassCard(radius: 16, tint: Palette.red)
        case .tool(_, let name, let args, let done):
            HStack(spacing: 8) {
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Palette.lime)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(AgentStore.label(tool: name, args: args)).font(.footnote).foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().strokeBorder(Palette.hairline))
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? "Done" : "In progress")
        case .changes(_, let changes):
            VStack(alignment: .leading, spacing: 8) {
                Text("Changes").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.tertiary)
                ForEach(changes) { change in
                    HStack {
                        Text(change.summary)
                            .font(.subheadline)
                            .foregroundStyle(change.undone ? Palette.tertiary : Palette.label)
                            .strikethrough(change.undone)
                        Spacer()
                        if change.undone {
                            Text("Undone").font(.footnote).foregroundStyle(Palette.tertiary)
                        } else {
                            Button("Undo") { Task { await plan.undo(change.id) } }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(14)
            .glassCard(radius: 18)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

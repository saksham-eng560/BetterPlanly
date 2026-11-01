//
//  ContentView.swift
//  Planly
//
//  Onboarding on first launch, then the tabs, with the Undo toast floating above them.
//

import SwiftUI

enum AppTab: Hashable { case today, agent, history, settings }

/// Lets any screen switch tabs, e.g. "Ask the agent about this" opens chat with a draft.
@Observable
final class Router {
    var tab: AppTab = .today
    var agentDraft = ""

    func ask(_ message: String) {
        agentDraft = message
        tab = .agent
    }
}

struct ContentView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(AgentStore.self) private var agent
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = Router()
    @State private var onboarded = SharedStore.onboarded

    var body: some View {
        Group {
            if onboarded {
                tabs
            } else {
                OnboardingView {
                    SharedStore.onboarded = true
                    onboarded = true
                }
            }
        }
        .environment(router)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, onboarded else { return }
            Task { await refreshAndReview() }
        }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            AgentView()
                .tabItem { Label("Agent", systemImage: "sparkles") }
                .tag(AppTab.agent)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.white)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 60) }
        .task { await refreshAndReview() }
    }

    /// Refresh on open and on every return to the foreground; the first open of a day with missed
    /// tasks also asks the agent for a day review.
    private func refreshAndReview() async {
        await plan.refresh()
        guard !plan.offline else { return }
        agent.dayReviewIfNeeded(missed: plan.missed.count, today: plan.today)
    }
}

/// The floating "Completed “X” · Undo" toast.
struct ToastView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = plan.toast {
                HStack(spacing: 12) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Palette.red : Palette.lime)
                        .accessibilityHidden(true)
                    Text(toast.message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.label)
                        .lineLimit(2)
                    if let id = toast.changeSetId {
                        Spacer(minLength: 4)
                        Button("Undo") {
                            plan.toast = nil
                            Task { await plan.undo(id) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.label)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCard(radius: 18)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .id(toast.id)
            }
        }
        .animation(planlyAnimation(reduceMotion), value: plan.toast)
        .onChange(of: plan.toast) { _, toast in
            if let toast { AccessibilityNotification.Announcement(toast.message).post() }
        }
    }
}

#Preview {
    ContentView()
        .environment(PlanStore())
        .environment(AgentStore())
}

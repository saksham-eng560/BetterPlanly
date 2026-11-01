//
//  PlanlyApp.swift
//  Planly
//
//  Created by saksham verma on 02/11/26.
//

import SwiftUI

@main
struct PlanlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var plan: PlanStore
    @State private var agent: AgentStore

    init() {
        let plan = PlanStore()
        let agent = AgentStore()
        plan.agent = agent
        agent.plan = plan
        _plan = State(initialValue: plan)
        _agent = State(initialValue: agent)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plan)
                .environment(agent)
                .preferredColorScheme(.dark)
        }
        .backgroundTask(.appRefresh(Sync.refreshTaskId)) {
            await Sync.backgroundRefresh()
        }
    }
}

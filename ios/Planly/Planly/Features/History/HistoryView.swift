//
//  HistoryView.swift
//  Planly
//
//  Every change set, newest first, with Undo; plus Export (share sheet) and Import.
//

import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(PlanStore.self) private var plan
    @State private var entries: [ChangeSet] = []
    @State private var error: String?
    @State private var loading = false
    @State private var exportFile: ExportFile?
    @State private var exporting = false
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.red)
                        .listRowBackground(Color.clear)
                }
                if entries.isEmpty && !loading && error == nil {
                    Text("Nothing has changed yet.")
                        .foregroundStyle(Palette.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(entries) { entry in
                    HistoryRow(entry: entry) { await undo(entry) }
                        .listRowBackground(Color.white.opacity(0.06))
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
            .planlyScreen()
            .navigationTitle("History")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImport = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    Button {
                        Task { await export() }
                    } label: {
                        if exporting { ProgressView() } else { Label("Export", systemImage: "square.and.arrow.up") }
                    }
                    .disabled(exporting)
                }
            }
            .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showImport, onDismiss: { Task { await load() } }) { ImportView() }
        }
        .task { await load() }
        .onChange(of: plan.lastUpdated) { Task { await load() } }
    }

    private func load() async {
        guard let client = SharedStore.client else { return }
        loading = true
        defer { loading = false }
        do {
            entries = try await client.history(limit: 50)
            error = nil
        } catch {
            self.error = error.isOffline ? "Can't reach Planly on your Mac." : error.userMessage
        }
    }

    private func undo(_ entry: ChangeSet) async {
        await plan.undo(entry.id)
        await load()
    }

    private func export() async {
        guard let client = SharedStore.client else { return }
        exporting = true
        defer { exporting = false }
        do {
            exportFile = ExportFile(url: try await client.export())
        } catch {
            plan.show(Toast(message: error.userMessage, isError: true))
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct HistoryRow: View {
    let entry: ChangeSet
    var onUndo: () async -> Void

    private var symbol: String {
        switch entry.actor {
        case "agent": "sparkles"
        case "import": "square.and.arrow.down"
        default: "person.fill"
        }
    }

    var body: some View {
        let undone = entry.undoneAt != nil
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Palette.label)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.14)))
                .accessibilityLabel(entry.actor)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .foregroundStyle(undone ? Palette.tertiary : Palette.label)
                    .strikethrough(undone)
                Text(undone ? "Undone · \(PlanDates.timeAgo(entry.createdAt))" : PlanDates.timeAgo(entry.createdAt))
                    .font(.footnote)
                    .foregroundStyle(Palette.tertiary)
            }
            Spacer()
            if !undone && entry.undoOf == nil {
                Button("Undo") { Task { await onUndo() } }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }
}

/// UIActivityViewController for sharing the export file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

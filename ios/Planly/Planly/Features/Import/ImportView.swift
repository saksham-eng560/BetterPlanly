//
//  ImportView.swift
//  Planly
//
//  Import plan files from the Files app (json, yaml, md, csv or a Notion .zip export), or sync a
//  Notion database when the Mac has a Notion token.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var working = false
    @State private var result: ImportResult?
    @State private var error: String?
    @State private var databaseId = ""

    private static let types: [UTType] = {
        var types: [UTType] = [.json, .yaml, .commaSeparatedText, .zip, .plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let yml = UTType(filenameExtension: "yml") { types.append(yml) }
        return types
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        picking = true
                    } label: {
                        Label("Choose files…", systemImage: "folder")
                    }
                    .disabled(working)
                } footer: {
                    Text("A Planly plan (.json, .yaml), Markdown (.md), a Notion CSV, or a whole Notion export (.zip). Pick several to import them together.")
                }

                if plan.state?.notionConfigured == true {
                    Section {
                        TextField("Notion database ID", text: $databaseId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Import from Notion") { Task { await importNotion() } }
                            .disabled(databaseId.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    } header: {
                        Text("Notion")
                    }
                }

                if working {
                    Section { HStack { ProgressView(); Text("Importing…").padding(.leading, 8) } }
                }

                if let result {
                    Section("Imported") {
                        LabeledContent("Created", value: "\(result.created)")
                        LabeledContent("Updated", value: "\(result.updated)")
                        LabeledContent("Unchanged", value: "\(result.unchanged)")
                        if let skipped = result.skipped, !skipped.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Skipped").foregroundStyle(Palette.secondary)
                                ForEach(skipped, id: \.self) { Text($0).font(.footnote).foregroundStyle(Palette.tertiary) }
                            }
                        }
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.red) }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: Self.types, allowsMultipleSelection: true) { outcome in
                switch outcome {
                case .success(let urls): Task { await importFiles(urls) }
                case .failure(let failure): error = failure.localizedDescription
                }
            }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        guard let client = SharedStore.client, !urls.isEmpty else { return }
        var files: [(name: String, data: Data)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { files.append((url.lastPathComponent, data)) }
        }
        guard !files.isEmpty else {
            error = "Couldn't read those files."
            return
        }
        await run { try await client.importFiles(files) }
    }

    private func importNotion() async {
        guard let client = SharedStore.client else { return }
        let id = databaseId.trimmingCharacters(in: .whitespaces)
        await run { try await client.importNotion(databaseId: id) }
    }

    private func run(_ call: () async throws -> ImportResult) async {
        working = true
        error = nil
        result = nil
        defer { working = false }
        do {
            let imported = try await call()
            result = imported
            if let id = imported.changeSet?.id {
                plan.show(Toast(message: "Imported \(imported.created) new, \(imported.updated) updated", changeSetId: id))
            }
            await plan.refresh()
        } catch let api as APIError {
            error = ([api.detail] + api.errors).joined(separator: "\n")
        } catch {
            self.error = error.userMessage
        }
    }
}

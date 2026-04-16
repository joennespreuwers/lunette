import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var coordinator: AnalysisCoordinator
    @State private var showSettings = false
    @State private var isTargeted = false

    private let supportedTypes: [UTType] = [
        .audio, .mp3, .aiff, .wav,
        UTType("public.flac") ?? .audio,
        UTType("com.apple.m4a-audio") ?? .audio,
        UTType("public.aac-audio") ?? .audio,
    ]

    var body: some View {
        ZStack {
            if coordinator.reports.isEmpty && coordinator.analysisState == .idle {
                DropTargetView(isTargeted: $isTargeted)
            } else if coordinator.reports.count == 1 && !coordinator.showBatch {
                SingleFileView(report: coordinator.reports[0])
            } else {
                BatchTableView()
            }

            // Progress overlay
            if coordinator.analysisState == .running {
                VStack(spacing: 12) {
                    ProgressView(value: coordinator.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                    Text(coordinator.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.3))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    coordinator.reset()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(coordinator.reports.isEmpty)
                .keyboardShortcut("w", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gear")
                }
                .popover(isPresented: $showSettings) {
                    SettingsPopoverView()
                }
            }
        }
        .onDrop(of: supportedTypes.map(\.identifier), isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedTypes
        panel.title = "Choose Audio Files"

        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                await coordinator.analyzeFiles(urls)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            Task {
                await coordinator.analyzeFiles(urls)
            }
        }
    }
}

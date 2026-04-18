import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var coordinator: AnalysisCoordinator
    @State private var showSettings = false

    @AppStorage("appTheme") private var appTheme = "system"

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil
        }
    }

    // Supported drop / open-panel types (audio + video)
    private let supportedTypes: [UTType] = [
        .audio, .mp3, .aiff, .wav,
        UTType("public.flac")          ?? .audio,
        UTType("com.apple.m4a-audio")  ?? .audio,
        UTType("public.aac-audio")     ?? .audio,
        .movie,                         // generic video (mp4, mov, m4v, avi, …)
        .mpeg4Movie,
        .quickTimeMovie,
        UTType("public.avi")           ?? .movie,
        UTType("com.apple.m4v-video")  ?? .movie,
    ]

    var body: some View {
        ZStack {
            // Main content — drive solely from coordinator state
            if let report = coordinator.selectedReport {
                // Drilled into a file from batch table
                SingleFileView(report: report)
            } else if coordinator.reports.isEmpty {
                DropTargetView()
            } else if coordinator.reports.count == 1 {
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
        .preferredColorScheme(colorScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .keyboardShortcut("[", modifiers: .command)
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
    }

    // MARK: - Navigation

    private var canGoBack: Bool {
        coordinator.selectedReport != nil || !coordinator.reports.isEmpty
    }

    private func goBack() {
        if coordinator.selectedReport != nil {
            // Drill-down from batch → return to batch table
            coordinator.selectedReport = nil
        } else {
            // Batch or single view → return to drop target
            coordinator.reset()
        }
    }

    // MARK: - File picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = supportedTypes
        panel.title = "Choose Audio or Video Files"

        if panel.runModal() == .OK {
            Task { await coordinator.analyzeFiles(panel.urls) }
        }
    }

}

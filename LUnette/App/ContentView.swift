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
        .movie,
        .mpeg4Movie,
        .quickTimeMovie,
        UTType("public.avi")           ?? .movie,
        UTType("com.apple.m4v-video")  ?? .movie
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !coordinator.errors.isEmpty {
                    errorBanner
                }

                mainContent
            }

            if coordinator.analysisState == .running {
                progressOverlay
            }
        }
        .frame(minWidth: 800.0, minHeight: 600.0)
        .preferredColorScheme(colorScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .keyboardShortcut("[", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: openFilePicker) {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .popover(isPresented: $showSettings) {
                    SettingsPopoverView()
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let report = coordinator.selectedReport {
            SingleFileView(report: report)
        } else if coordinator.reports.isEmpty {
            DropTargetView()
        } else {
            BatchTableView()
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 12.0) {
            ProgressView(value: coordinator.progress)
                .progressViewStyle(.linear)
                .frame(width: 300.0)

            Text(coordinator.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20.0)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12.0))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.3))
    }

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack {
                Label(
                    "\(coordinator.errors.count) file\(coordinator.errors.count == 1 ? "" : "s") failed",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

                Spacer()

                Button(action: coordinator.clearErrors) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4.0) {
                    ForEach(Array(coordinator.errors.enumerated()), id: \.offset) { item in
                        errorRow(url: item.element.0, error: item.element.1)
                    }
                }
            }
            .frame(maxHeight: 100.0)
        }
        .padding(12.0)
        .background(.regularMaterial)
    }

    private func errorRow(
        url: URL,
        error: Error
    ) -> some View {
        HStack(alignment: .top, spacing: 8.0) {
            Text(url.lastPathComponent)
                .font(.caption.monospaced())
                .lineLimit(1)

            Text("—")
                .foregroundStyle(.tertiary)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Navigation

    private var canGoBack: Bool {
        coordinator.selectedReport != nil || !coordinator.reports.isEmpty
    }

    private func goBack() {
        if coordinator.selectedReport != nil {
            coordinator.selectedReport = nil
        } else {
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
            coordinator.start(urls: panel.urls)
        }
    }
}

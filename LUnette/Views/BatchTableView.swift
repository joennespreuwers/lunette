import SwiftUI

struct BatchTableView: View {
    @EnvironmentObject var coordinator: AnalysisCoordinator
    @State private var sortOrder = [KeyPathComparator(\AudioFileReport.integratedLUFS, order: .reverse)]
    @State private var selection = Set<AudioFileReport.ID>()

    @State private var showMomentaryMax = false
    @State private var showShortTermMax = false
    @State private var showCodec        = false
    @State private var showSampleRate   = false
    @State private var showDuration     = true

    private var sorted: [AudioFileReport] {
        coordinator.reports.sorted(using: sortOrder)
    }

    /// The single selected report, if exactly one row is highlighted
    private var singleSelection: AudioFileReport? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return coordinator.reports.first(where: { $0.id == id })
    }

    var body: some View {
        tableContent
            .onDeleteCommand { deleteSelected() }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Open") {
                        openSelected()
                    }
                    .disabled(singleSelection == nil)
                    .keyboardShortcut(.return, modifiers: [])
                }

                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selection.isEmpty)
                    .keyboardShortcut(.delete, modifiers: [])
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        columnToggleMenu
                    } label: {
                        Image(systemName: "table.badge.more")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { saveCSV() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
    }

    private func openSelected() {
        if let report = singleSelection {
            coordinator.selectedReport = report
        }
    }

    private func deleteSelected() {
        coordinator.reports.removeAll { selection.contains($0.id) }
        selection.removeAll()
        // If we just deleted everything, coordinator state cleans up automatically
        // via ContentView's view switching logic.
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Track", value: \.filename) { r in
                HStack(spacing: 6) {
                    Text(r.filename).lineLimit(1)
                    clipIcon(r.clipFlag)
                }
            }
            .width(200)

            TableColumn("Integrated", value: \.integratedLUFS) { r in
                monoText(lufsStr(r.integratedLUFS))
            }.width(110)

            TableColumn("LRA", value: \.lra) { r in
                monoText(String(format: "%.1f LU", r.lra))
            }.width(80)

            TableColumn("True Peak", value: \.truePeakMax) { r in
                Text(dbTPStr(r.truePeakMax))
                    .font(.system(.body, design: .monospaced).monospacedDigit())
                    .foregroundStyle(r.truePeakMax > -1 ? .orange : .primary)
            }.width(100)

            TableColumn("PLR", value: \.plr) { r in
                monoText(String(format: "%+.1f dB", r.plr))
            }.width(80)

            TableColumn("M-Max", value: \.momentaryMax) { r in
                monoText(showMomentaryMax ? lufsStr(r.momentaryMax) : "")
            }.width(showMomentaryMax ? 100 : 0)

            TableColumn("S-Max", value: \.shortTermMax) { r in
                monoText(showShortTermMax ? lufsStr(r.shortTermMax) : "")
            }.width(showShortTermMax ? 100 : 0)

            TableColumn("Codec", value: \.codec) { r in
                monoText(showCodec ? r.codec : "")
            }.width(showCodec ? 80 : 0)

            TableColumn("kHz", value: \.sampleRate) { r in
                monoText(showSampleRate ? "\(Int(r.sampleRate / 1000))" : "")
            }.width(showSampleRate ? 50 : 0)

            TableColumn("Duration", value: \.duration) { r in
                monoText(showDuration ? durationStr(r.duration) : "")
            }.width(showDuration ? 70 : 0)
        }
        // Double-click opens the file; right-click shows column toggles + delete
        .contextMenu(forSelectionType: AudioFileReport.ID.self) { ids in
            columnToggleMenu
            Divider()
            Button("Open") { openSelected() }
                .disabled(singleSelection == nil)
            Divider()
            Button("Delete", role: .destructive) {
                coordinator.reports.removeAll { ids.contains($0.id) }
                selection.subtract(ids)
            }
            .disabled(ids.isEmpty)
        } primaryAction: { ids in
            if let id = ids.first,
               let report = coordinator.reports.first(where: { $0.id == id }) {
                coordinator.selectedReport = report
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var columnToggleMenu: some View {
        Toggle("Momentary Max",  isOn: $showMomentaryMax)
        Toggle("Short-term Max", isOn: $showShortTermMax)
        Divider()
        Toggle("Codec",          isOn: $showCodec)
        Toggle("Sample Rate",    isOn: $showSampleRate)
        Toggle("Duration",       isOn: $showDuration)
    }

    @ViewBuilder
    private func clipIcon(_ flag: ClipFlag) -> some View {
        switch flag {
        case .error:   Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .warning: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .none:    EmptyView()
        }
    }

    private func monoText(_ s: String) -> some View {
        Text(s).font(.system(.body, design: .monospaced).monospacedDigit())
    }

    private func lufsStr(_ v: Double) -> String {
        v.isFinite ? String(format: "%.1f LUFS", v) : "—"
    }
    private func dbTPStr(_ v: Double) -> String {
        v.isFinite ? String(format: "%.2f dBTP", v) : "—"
    }
    private func durationStr(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return Int(t) >= 3600
            ? String(format: "%d:%02d:%02d", Int(t) / 3600, m % 60, s)
            : String(format: "%d:%02d", m, s)
    }

    private func saveCSV() {
        let csv = ExportFormatter.csv(for: coordinator.reports)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LUnette_Batch.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

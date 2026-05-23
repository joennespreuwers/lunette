import SwiftUI

struct BatchTableView: View {
    @EnvironmentObject var coordinator: AnalysisCoordinator
    @AppStorage("truePeakWarningThreshold") private var tpWarnThreshold: Double = -1.0

    @State private var sortOrder = [KeyPathComparator(\AudioFileReport.integratedLUFS, order: .reverse)]
    @State private var selection = Set<AudioFileReport.ID>()

    private var sorted: [AudioFileReport] {
        coordinator.reports.sorted(using: sortOrder)
    }

    /// The single selected report, if exactly one row is highlighted.
    private var singleSelection: AudioFileReport? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return coordinator.reports.first(where: { $0.id == id })
    }

    var body: some View {
        tableContent
            .onDeleteCommand(perform: deleteSelected)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Open", action: openSelected)
                        .disabled(singleSelection == nil)
                        .keyboardShortcut(.return, modifiers: [])
                }

                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive, action: deleteSelected) {
                        Image(systemName: "trash")
                    }
                    .disabled(selection.isEmpty)
                    .keyboardShortcut(.delete, modifiers: [])
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveCSV) {
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
        coordinator.reports.removeAll(where: { selection.contains($0.id) })
        selection.removeAll()
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Track", value: \.filename) { r in
                HStack(spacing: 6.0) {
                    Text(r.filename).lineLimit(1)

                    clipIcon(r.clipFlag)
                }
            }
            .width(200.0)

            TableColumn("Integrated", value: \.integratedLUFS) { r in
                monoText(lufsStr(r.integratedLUFS))
            }
            .width(110.0)

            TableColumn("LRA", value: \.lra) { r in
                monoText(String(format: "%.1f LU", r.lra))
            }
            .width(80.0)

            TableColumn("True Peak", value: \.truePeakMax) { r in
                Text(dbTPStr(r.truePeakMax))
                    .font(.system(.body, design: .monospaced).monospacedDigit())
                    .foregroundStyle(r.truePeakMax > tpWarnThreshold ? .orange : .primary)
            }
            .width(100.0)

            TableColumn("PLR", value: \.plr) { r in
                monoText(String(format: "%+.1f dB", r.plr))
            }
            .width(80.0)

            TableColumn("Duration", value: \.duration) { r in
                monoText(durationStr(r.duration))
            }
            .width(70.0)
        }
        .contextMenu(forSelectionType: AudioFileReport.ID.self) { ids in
            Button("Open", action: openSelected)
                .disabled(singleSelection == nil)

            Divider()

            Button("Delete", role: .destructive) {
                coordinator.reports.removeAll(where: { ids.contains($0.id) })
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
    private func clipIcon(_ flag: ClipFlag) -> some View {
        switch flag {
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

        case .warning:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

        case .none:
            EmptyView()
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
        let m = Int(t) / 60
        let s = Int(t) % 60
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

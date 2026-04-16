import SwiftUI

struct BatchTableView: View {
    @EnvironmentObject var coordinator: AnalysisCoordinator
    @State private var sortOrder = [KeyPathComparator(\AudioFileReport.integratedLUFS, order: .reverse)]
    @State private var selection = Set<AudioFileReport.ID>()

    // Column visibility
    @State private var showMomentaryMax  = false
    @State private var showShortTermMax  = false
    @State private var showCodec         = false
    @State private var showSampleRate    = false
    @State private var showBitDepth      = false
    @State private var showDuration      = true

    private var sorted: [AudioFileReport] {
        coordinator.reports.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            // Always-visible columns
            TableColumn("Track", value: \.filename) { r in
                HStack(spacing: 6) {
                    Text(r.filename)
                        .lineLimit(1)
                    if r.clipFlag == .error {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    } else if r.clipFlag == .warning {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn("Integrated", value: \.integratedLUFS) { r in
                monoText(lufsString(r.integratedLUFS))
            }
            .width(100)

            TableColumn("LRA", value: \.lra) { r in
                monoText(String(format: "%.1f LU", r.lra))
            }
            .width(80)

            TableColumn("True Peak", value: \.truePeakMax) { r in
                Text(dbTPString(r.truePeakMax))
                    .font(.system(.body, design: .monospaced).monospacedDigit())
                    .foregroundStyle(r.truePeakMax > -1 ? .orange : .primary)
            }
            .width(90)

            TableColumn("PLR", value: \.plr) { r in
                monoText(String(format: "%+.1f dB", r.plr))
            }
            .width(80)

            // Optional columns
            if showMomentaryMax {
                TableColumn("M-Max", value: \.momentaryMax) { r in
                    monoText(lufsString(r.momentaryMax))
                }
                .width(90)
            }

            if showShortTermMax {
                TableColumn("S-Max", value: \.shortTermMax) { r in
                    monoText(lufsString(r.shortTermMax))
                }
                .width(90)
            }

            if showCodec {
                TableColumn("Codec", value: \.codec)
                    .width(70)
            }

            if showSampleRate {
                TableColumn("Sample Rate", value: \.sampleRate) { r in
                    monoText("\(Int(r.sampleRate / 1000)) kHz")
                }
                .width(80)
            }

            if showBitDepth {
                TableColumn("Bit Depth", value: \.bitDepth) { r in
                    monoText("\(r.bitDepth)-bit")
                }
                .width(70)
            }

            if showDuration {
                TableColumn("Duration", value: \.duration) { r in
                    monoText(durationString(r.duration))
                }
                .width(70)
            }
        }
        .contextMenu(forSelectionType: AudioFileReport.ID.self) { ids in
            columnToggleMenu
        } primaryAction: { ids in
            // Open single file detail on double-click
            if ids.count == 1, let id = ids.first,
               let report = coordinator.reports.first(where: { $0.id == id }) {
                coordinator.reports = [report]
                coordinator.showBatch = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    columnToggleMenu
                } label: {
                    Image(systemName: "table.badge.more")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveCSV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Batch Analysis (\(coordinator.reports.count) files)")
    }

    @ViewBuilder
    private var columnToggleMenu: some View {
        Toggle("Momentary Max",  isOn: $showMomentaryMax)
        Toggle("Short-term Max", isOn: $showShortTermMax)
        Divider()
        Toggle("Codec",          isOn: $showCodec)
        Toggle("Sample Rate",    isOn: $showSampleRate)
        Toggle("Bit Depth",      isOn: $showBitDepth)
        Toggle("Duration",       isOn: $showDuration)
    }

    private func monoText(_ s: String) -> some View {
        Text(s)
            .font(.system(.body, design: .monospaced).monospacedDigit())
    }

    private func lufsString(_ v: Double) -> String {
        v.isFinite ? String(format: "%.1f LUFS", v) : "—"
    }
    private func dbTPString(_ v: Double) -> String {
        v.isFinite ? String(format: "%.2f dBTP", v) : "—"
    }
    private func durationString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
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

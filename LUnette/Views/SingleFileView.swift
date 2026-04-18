import SwiftUI

struct SingleFileView: View {
    let report: AudioFileReport
    @EnvironmentObject var coordinator: AnalysisCoordinator
    @State private var showExportMenu = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // File info bar
                fileInfoBar

                // Two-column layout: metrics + compliance
                HStack(alignment: .top, spacing: 16) {
                    MetricsCardView(report: report)
                        .frame(minWidth: 300)

                    StandardsComplianceView(report: report)
                        .frame(minWidth: 320)
                }

                // Loudness plot — TODO: implement in a future milestone
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    deleteReport()
                } label: {
                    Image(systemName: "trash")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy as Text") {
                        let text = ExportFormatter.plainText(for: report)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    Button("Copy as CSV") {
                        let csv = ExportFormatter.csv(for: [report])
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(csv, forType: .string)
                    }
                    Divider()
                    Button("Save as Text…") { saveAs(text: ExportFormatter.plainText(for: report), ext: "txt") }
                    Button("Save as CSV…")  { saveAs(text: ExportFormatter.csv(for: [report]), ext: "csv") }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var fileInfoBar: some View {
        HStack(spacing: 20) {
            Label(report.filename, systemImage: "waveform")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            infoChip(report.codec)
            infoChip("\(Int(report.sampleRate / 1000)) kHz")
            infoChip(report.bitDepthLabel)
            infoChip(durationString(report.duration))

            if report.clipFlag == .error {
                Label("CLIP", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.red, in: Capsule())
            } else if report.clipFlag == .warning {
                Label("NEAR CLIP", systemImage: "exclamationmark.triangle")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange, in: Capsule())
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func durationString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func deleteReport() {
        coordinator.reports.removeAll { $0.id == report.id }
        coordinator.selectedReport = nil
    }

    private func saveAs(text: String, ext: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "csv" ? [.commaSeparatedText] : [.plainText]
        panel.nameFieldStringValue = (report.filename as NSString).deletingPathExtension + "." + ext
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

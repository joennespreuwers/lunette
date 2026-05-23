import SwiftUI

struct SingleFileView: View {
    let report: AudioFileReport
    @EnvironmentObject var coordinator: AnalysisCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16.0) {
                fileInfoBar

                HStack(alignment: .top, spacing: 16.0) {
                    MetricsCardView(report: report)
                        .frame(minWidth: 300.0)

                    StandardsComplianceView(report: report)
                        .frame(minWidth: 320.0)
                }
            }
            .padding(20.0)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive, action: deleteReport) {
                    Image(systemName: "trash")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy as Text", action: copyAsText)

                    Button("Copy as CSV", action: copyAsCSV)

                    Divider()

                    Button("Save as Text…", action: saveAsText)

                    Button("Save as CSV…", action: saveAsCSV)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var fileInfoBar: some View {
        HStack(spacing: 20.0) {
            Label(report.filename, systemImage: "waveform")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            infoChip(report.codec)
            infoChip("\(Int(report.sampleRate / 1000.0)) kHz")
            infoChip(report.bitDepthLabel)
            infoChip(durationString(report.duration))

            if report.clipFlag == .error {
                clipCapsule(label: "CLIP", color: .red, systemImage: "exclamationmark.triangle.fill")
            } else if report.clipFlag == .warning {
                clipCapsule(label: "NEAR CLIP", color: .orange, systemImage: "exclamationmark.triangle")
            }
        }
        .padding(12.0)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10.0))
    }

    private func clipCapsule(
        label: String,
        color: Color,
        systemImage: String
    ) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8.0)
            .padding(.vertical, 3.0)
            .background(color, in: Capsule())
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8.0)
            .padding(.vertical, 3.0)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6.0))
    }

    private func durationString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Actions

    private func deleteReport() {
        coordinator.reports.removeAll(where: { $0.id == report.id })
        coordinator.selectedReport = nil
    }

    private func copyAsText() {
        let text = ExportFormatter.plainText(for: report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAsCSV() {
        let csv = ExportFormatter.csv(for: [report])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }

    private func saveAsText() {
        saveAs(text: ExportFormatter.plainText(for: report), ext: "txt")
    }

    private func saveAsCSV() {
        saveAs(text: ExportFormatter.csv(for: [report]), ext: "csv")
    }

    private func saveAs(
        text: String,
        ext: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "csv" ? [.commaSeparatedText] : [.plainText]
        panel.nameFieldStringValue = (report.filename as NSString).deletingPathExtension + "." + ext
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

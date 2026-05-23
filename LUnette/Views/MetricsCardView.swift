import SwiftUI

struct MetricsCardView: View {
    let report: AudioFileReport

    @AppStorage("truePeakWarningThreshold") private var tpWarnThreshold: Double = -1.0

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 32.0, verticalSpacing: 8.0) {
                metricRow(
                    "Integrated",
                    value: lufsString(report.integratedLUFS),
                    accent: true
                )
                metricRow("LRA", value: "\(luString(report.lra)) LU")
                metricRow("LRA Low", value: lufsString(report.lraLow))
                metricRow("LRA High", value: lufsString(report.lraHigh))
                metricRow("LRA Threshold", value: lufsString(report.lraThreshold))
                metricRow("Int. Threshold", value: lufsString(report.integratedThreshold))

                Divider().gridCellUnsizedAxes(.horizontal)

                metricRow(
                    "True Peak L",
                    value: dbTPString(report.truePeakL),
                    warning: report.truePeakL > tpWarnThreshold
                )
                if report.channels >= 2 {
                    metricRow(
                        "True Peak R",
                        value: dbTPString(report.truePeakR),
                        warning: report.truePeakR > tpWarnThreshold
                    )
                }
                metricRow(
                    "True Peak Max",
                    value: dbTPString(report.truePeakMax),
                    warning: report.truePeakMax > tpWarnThreshold
                )

                Divider().gridCellUnsizedAxes(.horizontal)

                metricRow("PLR", value: "\(String(format: "%+.1f", report.plr)) dB")
                metricRow("Momentary Max", value: lufsString(report.momentaryMax))
                metricRow("Short-term Max", value: lufsString(report.shortTermMax))

                if report.clipFlag != .none {
                    GridRow {
                        Text("Clip Warning")
                            .foregroundStyle(.secondary)

                        clipBadge(report.clipFlag)
                    }
                }
            }
            .padding(8.0)
        } label: {
            Text("Loudness Metrics")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func metricRow(
        _ label: String,
        value: String,
        accent: Bool = false,
        warning: Bool = false
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)

            Text(value)
                .font(.system(.body, design: .monospaced).monospacedDigit())
                .foregroundStyle(warning ? .orange : .primary)
                .fontWeight(accent ? .bold : .regular)
                .gridColumnAlignment(.leading)
        }
    }

    private func clipBadge(_ flag: ClipFlag) -> some View {
        Text(flag == .error ? "CLIP" : "NEAR CLIP")
            .font(.caption.bold())
            .padding(.horizontal, 8.0)
            .padding(.vertical, 3.0)
            .background(flag == .error ? Color.red : Color.orange, in: Capsule())
            .foregroundColor(.white)
    }

    private func lufsString(_ v: Double) -> String {
        v.isFinite ? "\(String(format: "%.1f", v)) LUFS" : "—"
    }

    private func luString(_ v: Double) -> String {
        v.isFinite ? String(format: "%.1f", v) : "—"
    }

    private func dbTPString(_ v: Double) -> String {
        v.isFinite ? "\(String(format: "%.2f", v)) dBTP" : "—"
    }
}

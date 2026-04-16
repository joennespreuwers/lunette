import SwiftUI
import Charts

struct LoudnessPlotView: View {
    let report: AudioFileReport

    @AppStorage("showPlotReferenceLinesSpotify") private var showSpotify  = false
    @AppStorage("showPlotReferenceLinesApple")   private var showApple    = false
    @AppStorage("showPlotReferenceLinesEBU")     private var showEBU      = true
    @AppStorage("showPlotReferenceLinesYouTube") private var showYouTube  = false

    private var momentaryData: [(x: Double, y: Double)] {
        report.momentaryHistory.enumerated().map { (Double($0.offset) * 0.1, $0.element) }
    }
    private var shortTermData: [(x: Double, y: Double)] {
        report.shortTermHistory.enumerated().map { (Double($0.offset) * 0.1, $0.element) }
    }

    private var yMin: Double {
        let minM = momentaryData.map(\.y).filter { $0.isFinite }.min() ?? -60
        let minS = shortTermData.map(\.y).filter { $0.isFinite }.min() ?? -60
        return max(min(minM, minS) - 3, -60)
    }
    private var yMax: Double {
        let maxM = momentaryData.map(\.y).filter { $0.isFinite }.max() ?? 0
        let maxS = shortTermData.map(\.y).filter { $0.isFinite }.max() ?? 0
        return min(max(maxM, maxS) + 3, 0)
    }

    var body: some View {
        GroupBox {
            Chart {
                // Short-term line
                ForEach(shortTermData, id: \.x) { pt in
                    LineMark(
                        x: .value("Time", pt.x),
                        y: .value("Short-term", pt.y)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                .foregroundStyle(by: .value("Series", "Short-term"))

                // Momentary line
                ForEach(momentaryData, id: \.x) { pt in
                    LineMark(
                        x: .value("Time", pt.x),
                        y: .value("Momentary", pt.y)
                    )
                    .foregroundStyle(.cyan.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.catmullRom)
                }
                .foregroundStyle(by: .value("Series", "Momentary"))

                // Integrated reference line
                RuleMark(y: .value("Integrated", report.integratedLUFS))
                    .foregroundStyle(.primary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("I: \(String(format: "%.1f", report.integratedLUFS)) LUFS")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }

                // Platform reference lines (optional)
                if showEBU {
                    referenceRule(lufs: -23, label: "EBU R128", color: .orange)
                }
                if showSpotify {
                    referenceRule(lufs: -14, label: "Spotify", color: .green)
                }
                if showApple {
                    referenceRule(lufs: -16, label: "Apple", color: .gray)
                }
                if showYouTube {
                    referenceRule(lufs: -14, label: "YouTube", color: .red)
                }

                // True peak markers
                if report.truePeakMax > -1 {
                    let tpTime = report.duration / 2.0  // approximate position
                    PointMark(x: .value("Time", tpTime), y: .value("TP", report.truePeakMax))
                        .foregroundStyle(.red)
                        .symbolSize(60)
                }
            }
            .chartYScale(domain: yMin...yMax)
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel("LUFS")
            .chartLegend(position: .top, alignment: .trailing)
            .frame(minHeight: 200)
        } label: {
            HStack {
                Text("Loudness Over Time")
                    .font(.headline)
                Spacer()
                referenceToggles
            }
        }
    }

    private var referenceToggles: some View {
        HStack(spacing: 12) {
            Toggle("EBU R128", isOn: $showEBU)
            Toggle("Spotify", isOn: $showSpotify)
            Toggle("Apple", isOn: $showApple)
            Toggle("YouTube", isOn: $showYouTube)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    @ChartContentBuilder
    private func referenceRule(lufs: Double, label: String, color: Color) -> some ChartContent {
        RuleMark(y: .value(label, lufs))
            .foregroundStyle(color.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, alignment: .leading) {
                Text("\(label): \(Int(lufs))")
                    .font(.caption2)
                    .foregroundStyle(color)
            }
    }
}

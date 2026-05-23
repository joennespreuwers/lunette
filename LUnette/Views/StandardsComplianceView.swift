import SwiftUI

struct StandardsComplianceView: View {
    let report: AudioFileReport

    @AppStorage("defaultStandard") private var defaultStandard: String = "ebu_r128"

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(Array(LoudnessStandard.all.enumerated()), id: \.element.id) { i, std in
                    complianceRow(std, isDefault: std.id == defaultStandard)

                    if i < LoudnessStandard.all.count - 1 {
                        Divider().padding(.leading, 16.0)
                    }
                }
            }
        } label: {
            Text("Platform Compliance")
                .font(.headline)
        }
    }

    private func complianceRow(
        _ std: LoudnessStandard,
        isDefault: Bool
    ) -> some View {
        let badge = std.badge(for: report)
        let delta = std.gainDelta(for: report)
        let deltaStr = delta >= 0.0
            ? String(format: "+%.1f LU", delta)
            : String(format: "%.1f LU", delta)

        return HStack(spacing: 12.0) {
            Circle()
                .fill(isDefault ? Color.accentColor : Color.clear)
                .frame(width: 6.0, height: 6.0)

            VStack(alignment: .leading, spacing: 1.0) {
                Text(std.name)
                    .font(isDefault ? .body.bold() : .body)

                if let notes = std.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text("\(Int(std.targetLUFS)) LUFS")
                .font(.system(.caption, design: .monospaced).monospacedDigit())
                .foregroundStyle(.secondary)

            Text(deltaStr)
                .font(.system(.caption, design: .monospaced).monospacedDigit())
                .frame(width: 70.0, alignment: .trailing)
                .foregroundStyle(deltaColor(for: std, delta: delta))

            BadgeView(badge: badge)
        }
        .padding(.horizontal, 16.0)
        .padding(.vertical, 8.0)
    }

    /// Mirrors `LoudnessStandard.badge(for:)` thresholds so the delta color and the
    /// PASS/WARN/FAIL (or OK/LOUD/QUIET) badge cannot disagree.
    private func deltaColor(
        for std: LoudnessStandard,
        delta: Double
    ) -> Color {
        let mag = abs(delta)
        if std.isBroadcast {
            if mag <= 1.0 { return .primary }
            if mag <= 2.0 { return .orange }
            return .red
        }
        return mag <= 1.0 ? .primary : .orange
    }
}

struct BadgeView: View {
    let badge: ComplianceBadge

    var body: some View {
        Text(badge.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8.0)
            .padding(.vertical, 3.0)
            .background(badgeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4.0))
            .foregroundStyle(badgeColor)
            .frame(minWidth: 40.0)
    }

    private var badgeColor: Color {
        switch badge {
        case .pass:  return .green
        case .warn:  return .orange
        case .fail:  return .red
        case .ok:    return .green
        case .loud:  return .orange
        case .quiet: return .orange
        }
    }
}

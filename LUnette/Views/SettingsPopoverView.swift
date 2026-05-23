import SwiftUI

struct SettingsPopoverView: View {
    @AppStorage("defaultStandard")          private var defaultStandard = "ebu_r128"
    @AppStorage("truePeakWarningThreshold") private var tpWarnThreshold: Double = -1.0
    @AppStorage("appTheme")                 private var appTheme = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            Text("Settings")
                .font(.title3.bold())
                .padding(.bottom, 4.0)

            VStack(alignment: .leading, spacing: 8.0) {
                Text("Default Broadcast Standard")
                    .font(.subheadline.bold())

                Picker("", selection: $defaultStandard) {
                    Text("EBU R128 (−23 LUFS)").tag("ebu_r128")
                    Text("ATSC A/85 (−24 LUFS)").tag("atsc_a85")
                    Text("ARIB TR-B32 (−24 LUFS)").tag("arib")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8.0) {
                Text("True Peak Warning Threshold")
                    .font(.subheadline.bold())

                HStack {
                    Slider(value: $tpWarnThreshold, in: -6.0 ... 0.0, step: 0.5)

                    Text("\(String(format: "%.1f", tpWarnThreshold)) dBTP")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 75.0, alignment: .trailing)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8.0) {
                Text("Theme")
                    .font(.subheadline.bold())

                Picker("Theme", selection: $appTheme) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(20.0)
        .frame(width: 300.0)
    }
}

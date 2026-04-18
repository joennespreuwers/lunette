import SwiftUI

struct SettingsPopoverView: View {
    @AppStorage("defaultStandard")               private var defaultStandard     = "ebu_r128"
    @AppStorage("truePeakWarningThreshold")      private var tpWarnThreshold     = -1.0
    @AppStorage("appTheme")                      private var appTheme            = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title3.bold())
                .padding(.bottom, 4)

            // Default broadcast standard
            VStack(alignment: .leading, spacing: 8) {
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

            // True Peak warning threshold
            VStack(alignment: .leading, spacing: 8) {
                Text("True Peak Warning Threshold")
                    .font(.subheadline.bold())
                HStack {
                    Slider(value: $tpWarnThreshold, in: -6 ... 0, step: 0.5)
                    Text("\(String(format: "%.1f", tpWarnThreshold)) dBTP")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 75, alignment: .trailing)
                }
            }

            Divider()

            // Theme
            VStack(alignment: .leading, spacing: 8) {
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
        .padding(20)
        .frame(width: 300)
    }
}

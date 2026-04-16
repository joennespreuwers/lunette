import SwiftUI

struct DropTargetView: View {
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72))
                .foregroundStyle(isTargeted ? .accent : .secondary)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            VStack(spacing: 6) {
                Text("Drop Audio Files Here")
                    .font(.title2.bold())
                Text("or press ⌘O to open files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("WAV · AIFF · FLAC · MP3 · AAC · M4A · CAF")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .padding(24)
        )
        .background(
            isTargeted ? Color.accentColor.opacity(0.05) : Color.clear
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

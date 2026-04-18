import SwiftUI

struct DropTargetView: View {

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 6) {
                Text("No Files Loaded")
                    .font(.title2.bold())
                Text("Press ⌘O to open audio or video files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("WAV · AIFF · FLAC · MP3 · AAC · M4A · MP4 · MOV")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

struct DropTargetView: View {

    var body: some View {
        VStack(spacing: 20.0) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72.0))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 6.0) {
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

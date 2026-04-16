import AVFoundation

/// Reads an audio file in 65536-frame chunks, converting to interleaved Float32 at native sample rate.
struct AudioReader {

    static let chunkSize = 65536

    struct Metadata {
        let codec: String
        let sampleRate: Double
        let bitDepth: Int
        let channels: Int
        let duration: TimeInterval
    }

    /// Opens the file and returns its metadata without reading samples.
    static func metadata(for url: URL) throws -> Metadata {
        let file = try AVAudioFile(forReading: url)
        let fmt  = file.fileFormat       // on-disk format (for bit depth / codec)
        let sr   = fmt.sampleRate
        let ch   = Int(fmt.channelCount)
        let dur  = Double(file.length) / sr
        return Metadata(
            codec:      codecName(for: url, format: fmt),
            sampleRate: sr,
            bitDepth:   bitDepth(from: fmt),
            channels:   ch,
            duration:   dur
        )
    }

    /// Streams interleaved Float32 chunks to `handler`. Throws on format errors.
    static func stream(url: URL, handler: (UnsafePointer<Float>, Int) throws -> Void) throws {
        let file = try AVAudioFile(forReading: url)

        // AVAudioFile.read(into:) always decodes into processingFormat (deinterleaved Float32).
        // We convert from that to interleaved Float32 for libebur128.
        let srcFormat = file.processingFormat   // Float32, deinterleaved, native SR
        let ch        = srcFormat.channelCount
        let sr        = srcFormat.sampleRate

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sr,
            channels: ch,
            interleaved: true
        ) else {
            throw AnalysisError.unsupportedFormat("Cannot create interleaved Float32 format")
        }

        // For mono the formats are identical (interleaved == deinterleaved for 1 ch),
        // so the converter is a no-op but still correct.
        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw AnalysisError.unsupportedFormat("AVAudioConverter init failed")
        }

        let capacity = AVAudioFrameCount(chunkSize)

        guard let readBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: capacity),
              let outBuf  = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else {
            throw AnalysisError.unsupportedFormat("Cannot allocate PCM buffers")
        }

        while file.framePosition < file.length {
            let remaining    = AVAudioFrameCount(file.length - file.framePosition)
            let framesToRead = min(capacity, remaining)
            readBuf.frameLength = 0

            try file.read(into: readBuf, frameCount: framesToRead)
            guard readBuf.frameLength > 0 else { break }

            var inputConsumed = false
            var convError: NSError?
            outBuf.frameLength = 0

            let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return readBuf
            }

            if let err = convError { throw err }
            if status == .error { throw AnalysisError.unsupportedFormat("AVAudioConverter failed") }
            guard outBuf.frameLength > 0 else { continue }

            // interleaved: all samples in floatChannelData[0]
            guard let floatData = outBuf.floatChannelData else { continue }
            try handler(UnsafePointer(floatData[0]), Int(outBuf.frameLength))
        }
    }

    // MARK: - Private helpers

    private static func bitDepth(from format: AVAudioFormat) -> Int {
        let bits = format.streamDescription.pointee.mBitsPerChannel
        if bits > 0 { return Int(bits) }
        switch format.commonFormat {
        case .pcmFormatFloat32:  return 32
        case .pcmFormatFloat64:  return 64
        case .pcmFormatInt16:    return 16
        case .pcmFormatInt32:    return 32
        case .otherFormat:       return 0
        @unknown default:        return 0
        }
    }

    private static func codecName(for url: URL, format: AVAudioFormat) -> String {
        switch url.pathExtension.lowercased() {
        case "flac":        return "FLAC"
        case "mp3":         return "MP3"
        case "aac":         return "AAC"
        case "m4a":         return "AAC/M4A"
        case "aiff", "aif": return "AIFF"
        case "wav":
            let flags = format.streamDescription.pointee.mFormatFlags
            return (flags & kAudioFormatFlagIsFloat != 0) ? "WAV Float" : "WAV PCM"
        case "caf":         return "CAF"
        case "ogg":         return "OGG Vorbis"
        default:            return url.pathExtension.uppercased()
        }
    }
}

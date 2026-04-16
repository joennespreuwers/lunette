import AVFoundation
import AudioToolbox

/// Reads an audio file in 65536-frame chunks, converting to interleaved Float32 at native sample rate.
struct AudioReader {

    static let chunkSize = 65536

    struct Metadata {
        let codec: String
        let sampleRate: Double
        let bitDepth: Int       // 0 = lossy/unknown
        let channels: Int
        let duration: TimeInterval
    }

    /// Opens the file and returns its metadata without reading samples.
    static func metadata(for url: URL) throws -> Metadata {
        let file = try AVAudioFile(forReading: url)
        let fmt  = file.fileFormat
        let sr   = fmt.sampleRate
        let ch   = Int(fmt.channelCount)
        let dur  = Double(file.length) / sr

        // Use ExtAudioFile to read the on-disk ASBD — more reliable than AVAudioFile.fileFormat
        // for compressed formats (FLAC, ALAC, etc.) where mBitsPerChannel may be 0 in the
        // AVAudioFormat ASBD but is correctly populated by ExtAudioFile.
        let depth = extAudioFileBitDepth(url: url)

        return Metadata(
            codec:      codecName(for: url, format: fmt),
            sampleRate: sr,
            bitDepth:   depth,
            channels:   ch,
            duration:   dur
        )
    }

    /// Streams interleaved Float32 chunks to `handler`. Throws on format errors.
    static func stream(url: URL, handler: (UnsafePointer<Float>, Int) throws -> Void) throws {
        let file = try AVAudioFile(forReading: url)

        // AVAudioFile.read(into:) always decodes into processingFormat (Float32, deinterleaved).
        // We then reinterleave for libebur128.
        let srcFormat = file.processingFormat
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

            guard let floatData = outBuf.floatChannelData else { continue }
            try handler(UnsafePointer(floatData[0]), Int(outBuf.frameLength))
        }
    }

    // MARK: - Private helpers

    /// Uses ExtAudioFile to read mBitsPerChannel from the file's actual data format.
    /// This is reliable for PCM (WAV, AIFF, FLAC, ALAC) and returns 0 for lossy codecs.
    private static func extAudioFileBitDepth(url: URL) -> Int {
        var extRef: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &extRef) == noErr, let ref = extRef else { return 0 }
        defer { ExtAudioFileDispose(ref) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard ExtAudioFileGetProperty(ref, kExtAudioFileProperty_FileDataFormat, &size, &asbd) == noErr else {
            return 0
        }
        return Int(asbd.mBitsPerChannel)
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

import AVFoundation
import AudioToolbox
import CoreMedia

/// Reads an audio or video file in chunks, converting to interleaved Float32.
/// Audio files use AVAudioFile. Video files use AVAssetReader to extract the audio track.
struct AudioReader {

    static let chunkSize = 65536

    struct Metadata {
        let codec: String
        let sampleRate: Double
        let bitDepth: Int       // 0 = lossy / unknown
        let channels: Int
        let duration: TimeInterval
    }

    static func metadata(for url: URL) async throws -> Metadata {
        if isVideoFile(url) {
            return try await videoMetadata(for: url)
        } else {
            return try audioFileMetadata(for: url)
        }
    }

    static func stream(url: URL, handler: (UnsafePointer<Float>, Int) throws -> Void) async throws {
        if isVideoFile(url) {
            try await streamVideo(url: url, handler: handler)
        } else {
            try streamAudio(url: url, handler: handler)
        }
    }

    // MARK: - Audio-only path (AVAudioFile)

    private static func audioFileMetadata(for url: URL) throws -> Metadata {
        let file = try AVAudioFile(forReading: url)
        let fmt  = file.fileFormat
        let sr   = fmt.sampleRate
        let ch   = Int(fmt.channelCount)
        let dur  = Double(file.length) / sr
        return Metadata(
            codec:      codecNameAudio(for: url, format: fmt),
            sampleRate: sr,
            bitDepth:   extAudioFileBitDepth(url: url),
            channels:   ch,
            duration:   dur
        )
    }

    private static func streamAudio(url: URL, handler: (UnsafePointer<Float>, Int) throws -> Void) throws {
        let file      = try AVAudioFile(forReading: url)
        let srcFormat = file.processingFormat   // Float32, deinterleaved, native SR
        let ch        = srcFormat.channelCount
        let sr        = srcFormat.sampleRate

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: ch, interleaved: true
        ) else { throw AnalysisError.unsupportedFormat("Cannot create interleaved Float32 format") }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw AnalysisError.unsupportedFormat("AVAudioConverter init failed")
        }

        let capacity = AVAudioFrameCount(chunkSize)
        guard let readBuf = AVAudioPCMBuffer(pcmFormat: srcFormat,  frameCapacity: capacity),
              let outBuf  = AVAudioPCMBuffer(pcmFormat: dstFormat,  frameCapacity: capacity) else {
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
                if inputConsumed { outStatus.pointee = .noDataNow; return nil }
                inputConsumed = true; outStatus.pointee = .haveData; return readBuf
            }

            if let err = convError { throw err }
            if status == .error { throw AnalysisError.unsupportedFormat("AVAudioConverter failed") }
            guard outBuf.frameLength > 0 else { continue }
            guard let floatData = outBuf.floatChannelData else { continue }
            try handler(UnsafePointer(floatData[0]), Int(outBuf.frameLength))
        }
    }

    // MARK: - Video path (AVAssetReader)

    private static func videoMetadata(for url: URL) async throws -> Metadata {
        let asset       = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw AnalysisError.unsupportedFormat("No audio track in \(url.lastPathComponent)")
        }
        let duration    = try await asset.load(.duration)
        let formatDescs = try await track.load(.formatDescriptions)

        var sr: Double = 44100, ch = 2, bits = 0
        if let desc = formatDescs.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
            if asbd.pointee.mSampleRate    > 0 { sr   = asbd.pointee.mSampleRate }
            if asbd.pointee.mChannelsPerFrame > 0 { ch = Int(asbd.pointee.mChannelsPerFrame) }
            bits = Int(asbd.pointee.mBitsPerChannel)   // 0 for AAC (lossy)
        }

        return Metadata(
            codec:      codecNameVideo(for: url),
            sampleRate: sr,
            bitDepth:   bits,
            channels:   ch,
            duration:   CMTimeGetSeconds(duration)
        )
    }

    private static func streamVideo(url: URL, handler: (UnsafePointer<Float>, Int) throws -> Void) async throws {
        let asset       = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw AnalysisError.unsupportedFormat("No audio track in \(url.lastPathComponent)")
        }

        // Pin SR and channel count explicitly so the decoded output matches
        // what we already told libebur128 (via videoMetadata).
        let formatDescs = try await track.load(.formatDescriptions)
        var nativeSR: Double = 48000
        var nativeCh: Int    = 2
        if let desc = formatDescs.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
            if asbd.pointee.mSampleRate      > 0 { nativeSR = asbd.pointee.mSampleRate }
            if asbd.pointee.mChannelsPerFrame > 0 { nativeCh = Int(asbd.pointee.mChannelsPerFrame) }
        }

        let reader = try AVAssetReader(asset: asset)

        // Output: interleaved Float32 PCM at the file's native SR and channel count.
        let outputSettings: [String: Any] = [
            AVFormatIDKey:               Int(kAudioFormatLinearPCM),
            AVSampleRateKey:             nativeSR,
            AVNumberOfChannelsKey:       nativeCh,
            AVLinearPCMBitDepthKey:      32,
            AVLinearPCMIsFloatKey:       true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey:   false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? AnalysisError.unsupportedFormat("AVAssetReader failed to start")
        }
        defer { reader.cancelReading() }

        while reader.status == .reading {
            guard let sampleBuf = output.copyNextSampleBuffer() else { break }
            let frameCount = CMSampleBufferGetNumSamples(sampleBuf)
            guard frameCount > 0 else { continue }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuf) else { continue }
            var dataPointer: UnsafeMutablePointer<CChar>?
            var totalLength = 0
            let err = CMBlockBufferGetDataPointer(
                blockBuffer, atOffset: 0,
                lengthAtOffsetOut: nil, totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard err == kCMBlockBufferNoErr, let ptr = dataPointer, totalLength > 0 else { continue }

            try ptr.withMemoryRebound(to: Float.self, capacity: totalLength / MemoryLayout<Float>.size) { floatPtr in
                try handler(floatPtr, frameCount)
            }
        }

        if reader.status == .failed {
            throw reader.error ?? AnalysisError.unsupportedFormat("AVAssetReader failed")
        }
    }

    // MARK: - Private helpers

    static func isVideoFile(_ url: URL) -> Bool {
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "mxf", "avi"]
        return videoExts.contains(url.pathExtension.lowercased())
    }

    private static func extAudioFileBitDepth(url: URL) -> Int {
        var extRef: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &extRef) == noErr, let ref = extRef else { return 0 }
        defer { ExtAudioFileDispose(ref) }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard ExtAudioFileGetProperty(ref, kExtAudioFileProperty_FileDataFormat, &size, &asbd) == noErr else { return 0 }
        return Int(asbd.mBitsPerChannel)
    }

    private static func codecNameAudio(for url: URL, format: AVAudioFormat) -> String {
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
        default:            return url.pathExtension.uppercased()
        }
    }

    private static func codecNameVideo(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4":        return "MP4"
        case "mov":        return "MOV"
        case "m4v":        return "M4V"
        case "mxf":        return "MXF"
        case "avi":        return "AVI"
        default:           return url.pathExtension.uppercased()
        }
    }
}

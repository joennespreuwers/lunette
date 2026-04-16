import Foundation

/// Swift wrapper around libebur128. One instance per file — not thread-safe.
final class LoudnessMeter {

    private var statePtr: UnsafeMutablePointer<ebur128_state>?
    let channels: UInt32
    let sampleRate: UInt32

    // History collected every ~100 ms during add_frames calls
    private(set) var momentaryHistory: [Double] = []
    private(set) var shortTermHistory: [Double] = []

    private var framesSinceLastSample: Int = 0
    private let framesPerSample: Int

    init(channels: UInt32, sampleRate: UInt32) throws {
        self.channels = channels
        self.sampleRate = sampleRate
        self.framesPerSample = Int(Double(sampleRate) * 0.1)

        let mode = Int32(bitPattern: EBUR128_MODE_I.rawValue
                        | EBUR128_MODE_LRA.rawValue
                        | EBUR128_MODE_TRUE_PEAK.rawValue
                        | EBUR128_MODE_S.rawValue
                        | EBUR128_MODE_M.rawValue)

        guard let ptr = ebur128_init(channels, UInt(sampleRate), mode) else {
            throw AnalysisError.libebur128InitFailed
        }
        self.statePtr = ptr
    }

    deinit {
        ebur128_destroy(&statePtr)
    }

    /// Add interleaved Float32 frames. Collects history every ~100 ms.
    func addFrames(_ samples: UnsafePointer<Float>, frameCount: Int) throws {
        guard let st = statePtr else { throw AnalysisError.libebur128InitFailed }

        let result = ebur128_add_frames_float(st, samples, frameCount)
        guard result == EBUR128_SUCCESS.rawValue else {
            throw AnalysisError.libebur128AddFramesFailed(result)
        }

        framesSinceLastSample += frameCount
        if framesSinceLastSample >= framesPerSample {
            framesSinceLastSample = 0
            var m = 0.0, s = 0.0
            if ebur128_loudness_momentary(st, &m) == EBUR128_SUCCESS.rawValue {
                momentaryHistory.append(m)
            }
            if ebur128_loudness_shortterm(st, &s) == EBUR128_SUCCESS.rawValue {
                shortTermHistory.append(s)
            }
        }
    }

    // MARK: - Final metric extraction

    func integratedLUFS() throws -> Double {
        guard let st = statePtr else { throw AnalysisError.noResult }
        var v = 0.0
        guard ebur128_loudness_global(st, &v) == EBUR128_SUCCESS.rawValue else {
            throw AnalysisError.noResult
        }
        return v
    }

    func lra() throws -> Double {
        guard let st = statePtr else { throw AnalysisError.noResult }
        var v = 0.0
        guard ebur128_loudness_range(st, &v) == EBUR128_SUCCESS.rawValue else {
            throw AnalysisError.noResult
        }
        return v
    }

    /// Derives LRA low/high from the collected short-term history using 10th/95th percentile.
    /// Returns the integrated relative threshold via ebur128_relative_threshold.
    func lraDetails() -> (low: Double, high: Double, threshold: Double, integratedThreshold: Double) {
        // LRA low/high from short-term history percentiles
        let finite = shortTermHistory.filter { $0.isFinite && $0 > -70 }.sorted()
        var low  = -70.0
        var high = -70.0
        if !finite.isEmpty {
            low  = finite[max(0, Int(Double(finite.count) * 0.10))]
            high = finite[min(finite.count - 1, Int(Double(finite.count) * 0.95))]
        }
        // LRA threshold = high - 20 LU (as per EBU 3342)
        let lraThreshold = high - 20.0

        // Integrated relative threshold from libebur128
        var relThresh = -70.0
        if let st = statePtr {
            _ = ebur128_relative_threshold(st, &relThresh)
        }

        return (low, high, lraThreshold, relThresh)
    }

    /// Returns per-channel true peak in dBTP. `channel` is zero-based.
    func truePeak(channel: UInt32) throws -> Double {
        guard let st = statePtr else { throw AnalysisError.noResult }
        var linear = 0.0
        guard ebur128_true_peak(st, channel, &linear) == EBUR128_SUCCESS.rawValue else {
            throw AnalysisError.noResult
        }
        return 20.0 * log10(max(linear, 1e-10))
    }

    func momentaryMax() -> Double {
        momentaryHistory.filter(\.isFinite).max() ?? -Double.infinity
    }

    func shortTermMax() -> Double {
        shortTermHistory.filter(\.isFinite).max() ?? -Double.infinity
    }
}

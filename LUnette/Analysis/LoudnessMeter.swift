import Foundation

/// Swift wrapper around libebur128. One instance per file — not thread-safe.
final class LoudnessMeter {

    private var statePtr: UnsafeMutablePointer<ebur128_state>?
    let channels: UInt32
    let sampleRate: UInt32

    // Momentary history sampled every 100 ms (for M-max display)
    private(set) var momentaryHistory: [Double] = []
    private var mFramesSince: Int = 0
    private let mFramesPerSample: Int   // 100 ms

    // Short-term history sampled every 1 s — matches EBU 3342's 1-second block hop.
    // Used for lraLow / lraHigh with proper gating; NOT sampled at 100 ms because
    // percentile gating on 100 ms values produces a biased (too-dense) distribution.
    private(set) var shortTermHistory: [Double] = []
    private var stFramesSince: Int = 0
    private let stFramesPerSample: Int  // 1000 ms

    init(
        channels: UInt32,
        sampleRate: UInt32
    ) throws {
        self.channels = channels
        self.sampleRate = sampleRate
        self.mFramesPerSample  = max(1, Int(Double(sampleRate) * 0.1))
        self.stFramesPerSample = max(1, Int(Double(sampleRate) * 1.0))

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

    /// Feeds frames to libebur128 sliced on the M/S sampling boundaries, so the
    /// momentary and short-term history arrays are populated at the cadence the
    /// downstream M-max / S-max readouts expect — independent of the caller's
    /// chunk size.
    func addFrames(
        _ samples: UnsafePointer<Float>,
        frameCount: Int
    ) throws {
        guard let st = statePtr else { throw AnalysisError.libebur128InitFailed }

        let channelsInt = Int(channels)
        var offset = 0
        var remaining = frameCount

        while remaining > 0 {
            let toNextM = mFramesPerSample - mFramesSince
            let toNextS = stFramesPerSample - stFramesSince
            let take = min(remaining, min(toNextM, toNextS))

            let slicePtr = samples.advanced(by: offset * channelsInt)
            let result = ebur128_add_frames_float(st, slicePtr, take)
            guard result == EBUR128_SUCCESS.rawValue else {
                throw AnalysisError.libebur128AddFramesFailed(result)
            }

            mFramesSince += take
            stFramesSince += take

            if mFramesSince >= mFramesPerSample {
                mFramesSince -= mFramesPerSample
                var m = 0.0
                if ebur128_loudness_momentary(st, &m) == EBUR128_SUCCESS.rawValue {
                    momentaryHistory.append(m)
                }
            }

            if stFramesSince >= stFramesPerSample {
                stFramesSince -= stFramesPerSample
                var s = 0.0
                if ebur128_loudness_shortterm(st, &s) == EBUR128_SUCCESS.rawValue {
                    shortTermHistory.append(s)
                }
            }

            offset += take
            remaining -= take
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

    /// Computes LRA low/high/threshold using the EBU 3342 two-pass gate on the 1 s-hopped
    /// short-term history, matching the algorithm libebur128 uses internally:
    ///   Pass 1 — absolute gate: reject blocks below −70 LUFS
    ///   Pass 2 — relative gate: reject blocks below (mean_energy − 20 LU)
    ///   lraLow  = 10th percentile of surviving blocks
    ///   lraHigh = 95th percentile of surviving blocks
    ///   lraThreshold = relative gate threshold
    ///
    /// Note: a small residual difference vs ffmpeg/libebur128's internal value is expected
    /// because libebur128 uses non-overlapping 3 s windows with floating block boundaries
    /// aligned to the first sample, while we sample at fixed 1 s clock ticks. The LRA value
    /// from ebur128_loudness_range() is authoritative; lraLow/lraHigh are derived.
    func lraDetails() -> (low: Double, high: Double, threshold: Double, integratedThreshold: Double) {
        let absGated = shortTermHistory.filter({ $0.isFinite && $0 >= -70.0 })

        var low = -70.0
        var high = -70.0
        var relGate = -70.0

        if !absGated.isEmpty {
            let meanEnergy = absGated
                .map({ pow(10.0, $0 / 10.0) })
                .reduce(0.0, +) / Double(absGated.count)
            relGate = 10.0 * log10(max(meanEnergy, 1e-10)) - 20.0

            let relGated = absGated.filter({ $0 >= relGate }).sorted()

            if !relGated.isEmpty {
                low  = relGated[max(0, Int(Double(relGated.count) * 0.10))]
                high = relGated[min(relGated.count - 1, Int(Double(relGated.count) * 0.95))]
            }
        }

        var relThresh = -70.0
        if let st = statePtr {
            _ = ebur128_relative_threshold(st, &relThresh)
        }

        return (low, high, relGate, relThresh)
    }

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

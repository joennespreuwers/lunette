import Foundation

// MARK: - Clip Flag

enum ClipFlag: Equatable {
    case none
    case warning   // TP > -1 dBTP
    case error     // TP > 0 dBFS
}

// MARK: - Audio File Report

struct AudioFileReport: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    // Format metadata
    let codec: String
    let sampleRate: Double
    let bitDepth: Int           // 0 = lossy/unknown
    let channels: Int
    let duration: TimeInterval

    // Primary metrics
    let integratedLUFS: Double      // LUFS (negative number)
    let lra: Double                 // LU  — from libebur128 directly
    let lraLow: Double              // LUFS — 10th percentile of EBU 3342 gated short-term blocks
    let lraHigh: Double             // LUFS — 95th percentile of EBU 3342 gated short-term blocks
    let lraThreshold: Double        // LUFS — EBU 3342 relative gate applied to short-term blocks
    let integratedThreshold: Double // LUFS — from ebur128_relative_threshold

    let truePeakL: Double           // dBTP
    let truePeakR: Double           // dBTP (equals truePeakL for mono)

    // Secondary metrics
    let plr: Double                 // dB  (Integrated − max TP)
    let momentaryMax: Double        // LUFS
    let shortTermMax: Double        // LUFS
    let clipFlag: ClipFlag

    // Convenience
    var filename: String { url.lastPathComponent }
    var truePeakMax: Double { max(truePeakL, truePeakR) }
    /// Human-readable bit depth: "24-bit", "32-bit float", or "lossy" for 0
    var bitDepthLabel: String {
        guard bitDepth > 0 else { return "lossy" }
        return "\(bitDepth)-bit"
    }

    static func == (lhs: AudioFileReport, rhs: AudioFileReport) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Analysis Error

enum AnalysisError: LocalizedError {
    case fileUnreadable(URL)
    case tooShort(TimeInterval)
    case unsupportedFormat(String)
    case libebur128InitFailed
    case libebur128AddFramesFailed(Int32)
    case noResult

    var errorDescription: String? {
        switch self {
        case .fileUnreadable(let url):  return "Cannot read file: \(url.lastPathComponent)"
        case .tooShort(let d):          return "File too short (\(String(format: "%.2f", d)) s) — need ≥ 0.4 s"
        case .unsupportedFormat(let s): return "Unsupported format: \(s)"
        case .libebur128InitFailed:     return "libebur128 init failed"
        case .libebur128AddFramesFailed(let code): return "libebur128 add_frames error \(code)"
        case .noResult:                 return "Analysis returned no result"
        }
    }
}

// MARK: - Compliance Badge

/// Broadcast: PASS / WARN / FAIL (actual delivery spec).
/// Streaming: OK / LOUD / QUIET (platform normalises anyway — no delivery error).
enum ComplianceBadge {
    // Broadcast
    case pass               // within ±1 LU of target + TP ok
    case warn               // within ±2 LU of target + TP ok
    case fail               // outside ±2 LU or TP too high

    // Streaming
    case ok                 // within ±1 LU of target
    case loud               // louder than target (will be turned down)
    case quiet              // quieter than target (will be turned up)

    var label: String {
        switch self {
        case .pass:  return "PASS"
        case .warn:  return "WARN"
        case .fail:  return "FAIL"
        case .ok:    return "OK"
        case .loud:  return "LOUD"
        case .quiet: return "QUIET"
        }
    }
}

// MARK: - Standards Targets

struct LoudnessStandard: Identifiable {
    let id: String
    let name: String
    let targetLUFS: Double
    let lraMax: Double?          // nil = no LRA requirement
    let truePeakMax: Double      // dBTP
    let isBroadcast: Bool        // true → PASS/WARN/FAIL; false → OK/LOUD/QUIET
    let notes: String?

    func badge(for report: AudioFileReport) -> ComplianceBadge {
        let delta  = report.integratedLUFS - targetLUFS   // positive = louder than target
        let tpOk   = report.truePeakMax <= truePeakMax

        if isBroadcast {
            if abs(delta) <= 1.0 && tpOk { return .pass }
            if abs(delta) <= 2.0 && tpOk { return .warn }
            return .fail
        } else {
            // Streaming: ±1 LU = OK, otherwise directional
            if abs(delta) <= 1.0 { return .ok }
            return delta > 0 ? .loud : .quiet
        }
    }

    func gainDelta(for report: AudioFileReport) -> Double {
        targetLUFS - report.integratedLUFS
    }
}

extension LoudnessStandard {
    static let all: [LoudnessStandard] = [
        .init(id: "ebu_r128",   name: "EBU R128",     targetLUFS: -23, lraMax: 20,  truePeakMax: -1, isBroadcast: true,  notes: "Broadcast EU"),
        .init(id: "atsc_a85",   name: "ATSC A/85",    targetLUFS: -24, lraMax: nil, truePeakMax: -2, isBroadcast: true,  notes: "Broadcast US"),
        .init(id: "arib",       name: "ARIB TR-B32",  targetLUFS: -24, lraMax: nil, truePeakMax: -1, isBroadcast: true,  notes: "Broadcast JP"),
        .init(id: "spotify",    name: "Spotify",       targetLUFS: -14, lraMax: nil, truePeakMax: -1, isBroadcast: false, notes: nil),
        .init(id: "apple",      name: "Apple Music",   targetLUFS: -16, lraMax: nil, truePeakMax: -1, isBroadcast: false, notes: nil),
        .init(id: "youtube",    name: "YouTube",       targetLUFS: -14, lraMax: nil, truePeakMax: -1, isBroadcast: false, notes: nil),
        .init(id: "tidal",      name: "Tidal",         targetLUFS: -14, lraMax: nil, truePeakMax: -1, isBroadcast: false, notes: nil),
        .init(id: "amazon",     name: "Amazon Music",  targetLUFS: -14, lraMax: nil, truePeakMax: -2, isBroadcast: false, notes: nil),
        .init(id: "deezer",     name: "Deezer",        targetLUFS: -15, lraMax: nil, truePeakMax: -1, isBroadcast: false, notes: nil),
        .init(id: "soundcloud", name: "SoundCloud",    targetLUFS: -14, lraMax: nil, truePeakMax: -1, isBroadcast: false, notes: "Lossy encoding"),
    ]
}

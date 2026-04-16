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
    let bitDepth: Int
    let channels: Int
    let duration: TimeInterval

    // Primary metrics
    let integratedLUFS: Double      // LUFS (negative number)
    let lra: Double                 // LU
    let lraLow: Double              // LUFS
    let lraHigh: Double             // LUFS
    let lraThreshold: Double        // LUFS
    let integratedThreshold: Double // LUFS
    let truePeakL: Double           // dBTP
    let truePeakR: Double           // dBTP (nil if mono)

    // Secondary metrics
    let plr: Double                 // dB  (Integrated - max TP)
    let momentaryMax: Double        // LUFS
    let shortTermMax: Double        // LUFS
    let clipFlag: ClipFlag

    // History arrays for plot (sampled every ~100ms)
    let momentaryHistory: [Double]
    let shortTermHistory: [Double]

    // Convenience
    var filename: String { url.lastPathComponent }
    var truePeakMax: Double { max(truePeakL, truePeakR) }

    static func == (lhs: AudioFileReport, rhs: AudioFileReport) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Analysis Error

enum AnalysisError: LocalizedError {
    case fileUnreadable(URL)
    case tooShort(TimeInterval)          // < 0.4 s (need at least one M block)
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

// MARK: - Standards Targets

struct LoudnessStandard: Identifiable {
    let id: String
    let name: String
    let targetLUFS: Double
    let lraMax: Double?          // nil = no LRA requirement
    let truePeakMax: Double      // dBTP
    let notes: String?

    func badge(for report: AudioFileReport) -> ComplianceBadge {
        let delta = report.integratedLUFS - targetLUFS
        let absDelta = abs(delta)
        let tpOk = report.truePeakMax <= truePeakMax
        if absDelta <= 1.0 && tpOk { return .pass }
        if absDelta <= 2.0 && tpOk { return .warn }
        return .fail
    }

    func gainDelta(for report: AudioFileReport) -> Double {
        targetLUFS - report.integratedLUFS
    }
}

enum ComplianceBadge {
    case pass, warn, fail

    var label: String {
        switch self { case .pass: return "PASS"; case .warn: return "WARN"; case .fail: return "FAIL" }
    }
}

extension LoudnessStandard {
    static let all: [LoudnessStandard] = [
        .init(id: "ebu_r128",  name: "EBU R128",      targetLUFS: -23, lraMax: 20, truePeakMax: -1,  notes: "Broadcast EU"),
        .init(id: "atsc_a85",  name: "ATSC A/85",     targetLUFS: -24, lraMax: nil, truePeakMax: -2,  notes: "Broadcast US"),
        .init(id: "arib",      name: "ARIB TR-B32",   targetLUFS: -24, lraMax: nil, truePeakMax: -1,  notes: "Broadcast JP"),
        .init(id: "spotify",   name: "Spotify",        targetLUFS: -14, lraMax: nil, truePeakMax: -1,  notes: nil),
        .init(id: "apple",     name: "Apple Music",    targetLUFS: -16, lraMax: nil, truePeakMax: -1,  notes: nil),
        .init(id: "youtube",   name: "YouTube",        targetLUFS: -14, lraMax: nil, truePeakMax: -1,  notes: nil),
        .init(id: "tidal",     name: "Tidal",          targetLUFS: -14, lraMax: nil, truePeakMax: -1,  notes: nil),
        .init(id: "amazon",    name: "Amazon Music",   targetLUFS: -14, lraMax: nil, truePeakMax: -2,  notes: nil),
        .init(id: "deezer",    name: "Deezer",         targetLUFS: -15, lraMax: nil, truePeakMax: -1,  notes: nil),
        .init(id: "soundcloud",name: "SoundCloud",     targetLUFS: -14, lraMax: nil, truePeakMax: -1,  notes: "Lossy encoding"),
    ]
}

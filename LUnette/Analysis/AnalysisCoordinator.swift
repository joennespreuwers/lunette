import Foundation
import SwiftUI

enum AnalysisState: Equatable {
    case idle
    case running
    case done
    case failed(String)
}

@MainActor
final class AnalysisCoordinator: ObservableObject {
    @Published var reports: [AudioFileReport] = []
    @Published var errors: [(URL, Error)] = []
    @Published var analysisState: AnalysisState = .idle
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""

    /// Set when the user drills into a single file from the batch table.
    /// Clearing this returns to the batch table without destroying the report list.
    @Published var selectedReport: AudioFileReport? = nil

    private let maxConcurrent = 4

    func reset() {
        reports = []
        errors = []
        analysisState = .idle
        progress = 0.0
        statusMessage = ""
        selectedReport = nil
    }

    func analyzeFiles(_ urls: [URL]) async {
        let expanded = expandDirectories(urls)
        guard !expanded.isEmpty else { return }

        selectedReport = nil
        analysisState = .running
        progress = 0.0
        statusMessage = "Analysing \(expanded.count) file\(expanded.count == 1 ? "" : "s")…"

        let total = expanded.count
        var completed = 0

        await withTaskGroup(of: (AudioFileReport?, URL, Error?).self) { group in
            var pending = expanded.makeIterator()
            var running = 0

            while running < maxConcurrent, let url = pending.next() {
                group.addTask { await Self.analyse(url: url) }
                running += 1
            }

            for await (report, url, error) in group {
                if let report {
                    reports.append(report)
                } else if let error {
                    errors.append((url, error))
                }
                completed += 1
                progress = Double(completed) / Double(total)
                statusMessage = "Analysing… \(completed)/\(total)"

                if let url = pending.next() {
                    group.addTask { await Self.analyse(url: url) }
                }
            }
        }

        analysisState = .done
        statusMessage = "\(reports.count) file\(reports.count == 1 ? "" : "s") analysed"
    }

    // MARK: - File-level analysis

    private static func analyse(url: URL) async -> (AudioFileReport?, URL, Error?) {
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try await Self.analyseSync(url: url)
            }.value
            return (report, url, nil)
        } catch {
            return (nil, url, error)
        }
    }

    nonisolated private static func analyseSync(url: URL) async throws -> AudioFileReport {
        let meta = try await AudioReader.metadata(for: url)

        guard meta.duration >= 0.4 else {
            throw AnalysisError.tooShort(meta.duration)
        }

        let meter = try LoudnessMeter(
            channels:   UInt32(meta.channels),
            sampleRate: UInt32(meta.sampleRate)
        )

        try await AudioReader.stream(url: url) { ptr, frameCount in
            try meter.addFrames(ptr, frameCount: frameCount)
        }

        let integrated = try meter.integratedLUFS()
        let lra        = try meter.lra()
        let lraDetails = meter.lraDetails()

        var tpL: Double = -Double.infinity
        var tpR: Double = -Double.infinity
        if meta.channels >= 1 { tpL = (try? meter.truePeak(channel: 0)) ?? -Double.infinity }
        if meta.channels >= 2 { tpR = (try? meter.truePeak(channel: 1)) ?? -Double.infinity }

        let tpMax = max(tpL, tpR)
        let plr   = integrated - tpMax
        let mMax  = meter.momentaryMax()
        let sMax  = meter.shortTermMax()

        let clip: ClipFlag
        if      tpMax > 0  { clip = .error }
        else if tpMax > -1 { clip = .warning }
        else               { clip = .none }

        return AudioFileReport(
            url:                  url,
            codec:                meta.codec,
            sampleRate:           meta.sampleRate,
            bitDepth:             meta.bitDepth,
            channels:             meta.channels,
            duration:             meta.duration,
            integratedLUFS:       integrated,
            lra:                  lra,
            lraLow:               lraDetails.low,
            lraHigh:              lraDetails.high,
            lraThreshold:         lraDetails.threshold,
            integratedThreshold:  lraDetails.integratedThreshold,
            truePeakL:            tpL,
            truePeakR:            tpR,
            plr:                  plr,
            momentaryMax:         mMax,
            shortTermMax:         sMax,
            clipFlag:             clip,
            momentaryHistory:     meter.momentaryHistory,
            shortTermHistory:     meter.shortTermHistory
        )
    }

    // MARK: - Directory expansion

    private func expandDirectories(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        let supportedExts = Set(["wav","aif","aiff","flac","mp3","aac","m4a","caf",
                                  "mp4","mov","m4v","mxf","avi"])

        for url in urls {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        if supportedExts.contains(fileURL.pathExtension.lowercased()) {
                            result.append(fileURL)
                        }
                    }
                }
            } else if supportedExts.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }
}

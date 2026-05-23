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
    @Published var selectedReport: AudioFileReport?

    private let maxConcurrent = 4
    private var analysisTask: Task<Void, Never>?

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        reports = []
        errors = []
        analysisState = .idle
        progress = 0.0
        statusMessage = ""
        selectedReport = nil
    }

    func clearErrors() {
        errors = []
    }

    /// Launches a new analysis run on the given URLs, cancelling any run already in flight.
    func start(urls: [URL]) {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.run(urls: urls)
        }
    }

    private func run(urls: [URL]) async {
        let expanded = expandDirectories(urls)
        guard !expanded.isEmpty else { return }

        selectedReport = nil
        analysisState = .running
        progress = 0.0
        statusMessage = "Analysing \(expanded.count) file\(expanded.count == 1 ? "" : "s")…"

        let tpWarn = Self.currentTruePeakWarningThreshold()
        let total = expanded.count
        var completed = 0

        await withTaskGroup(of: (AudioFileReport?, URL, Error?).self) { group in
            var pending = expanded.makeIterator()

            for _ in 0..<maxConcurrent {
                guard let url = pending.next() else { break }
                group.addTask {
                    await Self.analyse(url: url, tpWarn: tpWarn)
                }
            }

            for await (report, url, error) in group {
                if Task.isCancelled { continue }

                if let report {
                    reports.append(report)
                } else if let error, !(error is CancellationError) {
                    errors.append((url, error))
                }
                completed += 1
                progress = Double(completed) / Double(total)
                statusMessage = "Analysing… \(completed)/\(total)"

                if let url = pending.next() {
                    group.addTask {
                        await Self.analyse(url: url, tpWarn: tpWarn)
                    }
                }
            }
        }

        if Task.isCancelled { return }

        analysisState = .done
        let analysed = "\(reports.count) file\(reports.count == 1 ? "" : "s") analysed"
        statusMessage = errors.isEmpty
            ? analysed
            : "\(analysed), \(errors.count) failed"
    }

    private static func currentTruePeakWarningThreshold() -> Double {
        (UserDefaults.standard.object(forKey: "truePeakWarningThreshold") as? Double) ?? -1.0
    }

    // MARK: - File-level analysis

    nonisolated private static func analyse(
        url: URL,
        tpWarn: Double
    ) async -> (AudioFileReport?, URL, Error?) {
        do {
            let report = try await analyseSync(url: url, tpWarn: tpWarn)
            return (report, url, nil)
        } catch {
            return (nil, url, error)
        }
    }

    nonisolated private static func analyseSync(
        url: URL,
        tpWarn: Double
    ) async throws -> AudioFileReport {
        try Task.checkCancellation()

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
        var tpMax: Double = -Double.infinity
        if meta.channels > 0 {
            for ch in 0..<UInt32(meta.channels) {
                guard let tp = try? meter.truePeak(channel: ch) else { continue }
                if ch == 0 { tpL = tp }
                if ch == 1 { tpR = tp }
                if tp > tpMax { tpMax = tp }
            }
        }

        let plr  = tpMax - integrated
        let mMax = meter.momentaryMax()
        let sMax = meter.shortTermMax()

        let clip: ClipFlag
        if tpMax > 0.0 {
            clip = .error
        } else if tpMax > tpWarn {
            clip = .warning
        } else {
            clip = .none
        }

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
            truePeakMax:          tpMax,
            plr:                  plr,
            momentaryMax:         mMax,
            shortTermMax:         sMax,
            clipFlag:             clip
        )
    }

    // MARK: - Directory expansion

    private func expandDirectories(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        let supportedExts: Set<String> = [
            "wav", "aif", "aiff", "flac", "mp3", "aac", "m4a", "caf",
            "mp4", "mov", "m4v", "mxf", "avi"
        ]

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

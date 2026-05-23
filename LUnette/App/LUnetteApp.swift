import AppKit
import SwiftUI

@main
struct LUnetteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AnalysisCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .onAppear {
                    appDelegate.handler = coordinator.start(urls:)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Handles files opened via the dock icon, `open file.wav` from the terminal, or
/// Finder's "Open With" — `application(_:open:)` receives them all here.
/// URLs that arrive before the SwiftUI view sets `handler` are buffered and
/// drained on first connection so cold-start drops don't get dropped.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var buffer: [URL] = []

    var handler: (([URL]) -> Void)? {
        didSet {
            guard let handler, !buffer.isEmpty else { return }
            let pending = buffer
            buffer = []
            handler(pending)
        }
    }

    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        if let handler {
            handler(urls)
        } else {
            buffer.append(contentsOf: urls)
        }
    }
}

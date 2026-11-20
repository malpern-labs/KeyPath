import Foundation

@MainActor
final class CLISpinner {
    private static let brailleFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let asciiFrames = ["-", "\\", "|", "/"]

    private let noColor: Bool
    private let isEnabled: Bool
    private var message: String
    private var animation: Task<Void, Never>?
    private var frameIndex = 0

    init(context: OutputContext) {
        noColor = context.noColor
        isEnabled = context.isInteractive && !context.quiet && !context.shouldOutputJSON
        message = ""
    }

    deinit {
        animation?.cancel()
    }

    func start(_ message: String) {
        guard isEnabled else { return }
        animation?.cancel()
        self.message = message
        frameIndex = 0
        renderFrame()
        animation = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(80)) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                tick()
            }
        }
    }

    func succeed(_ message: String) {
        guard isEnabled else { return }
        stop()
        let marker = ANSIColor.green("✓", noColor: noColor)
        FileHandle.standardError.write(Data("\r\u{001b}[2K\(marker) \(message)\n".utf8))
    }

    func fail(_ message: String) {
        guard isEnabled else { return }
        stop()
        let marker = ANSIColor.red("✗", noColor: noColor)
        FileHandle.standardError.write(Data("\r\u{001b}[2K\(marker) \(message)\n".utf8))
    }

    func stop() {
        guard let animation else { return }
        animation.cancel()
        self.animation = nil
        FileHandle.standardError.write(Data("\r\u{001b}[2K".utf8))
    }

    private func tick() {
        frameIndex += 1
        renderFrame()
    }

    private func renderFrame() {
        let frames = noColor ? Self.asciiFrames : Self.brailleFrames
        let frame = frames[frameIndex % frames.count]
        let color = noColor ? frame : ANSIColor.yellow(frame, noColor: false)
        FileHandle.standardError.write(Data("\r\u{001b}[2K\(color) \(message)".utf8))
    }
}

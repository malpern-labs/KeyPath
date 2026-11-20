import Foundation
import Synchronization

// MARK: - Protocol

/// Protocol for subprocess execution (enables testability)
public protocol SubprocessRunning: Sendable {
    func run(
        _ executable: String,
        args: [String],
        timeout: TimeInterval?
    ) async throws -> ProcessResult

    func launchctl(_ subcommand: String, _ args: [String]) async throws -> ProcessResult
}

// MARK: - Result Types

/// Result of a subprocess execution
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let duration: TimeInterval

    public init(exitCode: Int32, stdout: String, stderr: String, duration: TimeInterval) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

// MARK: - SubprocessRunner Actor

/// Actor-based subprocess runner that prevents MainActor blocking
///
/// All subprocess execution is isolated to this actor, ensuring that Process().waitUntilExit()
/// never blocks the MainActor. Uses async/await with termination handlers instead of blocking waits.
public actor SubprocessRunner: SubprocessRunning {
    public static let shared = SubprocessRunner()

    private init() {}

    /// Run a subprocess with optional timeout
    ///
    /// - Parameters:
    ///   - executable: Path to the executable
    ///   - args: Command-line arguments
    ///   - timeout: Optional timeout in seconds (default: 30s)
    /// - Returns: ProcessResult with exit code, stdout, stderr, and duration
    /// - Throws: SubprocessError on failure or timeout
    public func run(
        _ executable: String,
        args: [String],
        timeout: TimeInterval? = 30
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let startTime = Date()
        let timeoutInterval = timeout ?? 30.0

        AppLogger.shared.log("⚡ [SubprocessRunner] Executing: \(executable) \(args.joined(separator: " "))")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        let runContext = RunContext()
        let output = ProcessOutputCapture(stdout: stdoutPipe, stderr: stderrPipe)

        @Sendable func terminateIfRunning(_ task: Process) {
            guard task.isRunning else { return }
            task.terminate()
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                runContext.setContinuation(continuation)

                // Set up termination handler (must be set before launching)
                task.terminationHandler = { process in
                    let duration = Date().timeIntervalSince(startTime)
                    let exitCode = process.terminationStatus
                    let (stdoutData, stderrData) = output.read()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    let result = ProcessResult(
                        exitCode: exitCode,
                        stdout: stdout,
                        stderr: stderr,
                        duration: duration
                    )

                    // Log completion
                    if duration > 5.0 {
                        AppLogger.shared.warnUnlessQuietTest(
                            "⚠️ [SubprocessRunner] \(executable) took \(String(format: "%.2f", duration))s (>5s threshold)"
                        )
                    } else {
                        AppLogger.shared.log(
                            "✅ [SubprocessRunner] \(executable) completed in \(String(format: "%.2f", duration))s (exit: \(exitCode))"
                        )
                    }

                    runContext.resume(with: .success(result))
                }

                // Set up timeout task
                runContext.setTimeout(Task {
                    do {
                        try await Task.sleep(for: .seconds(timeoutInterval))
                    } catch {
                        // Task cancelled (process finished or parent cancelled)
                        return
                    }

                    if runContext.resume(
                        with: .failure(SubprocessError.timeout(executable: executable, timeout: timeoutInterval))
                    ) {
                        terminateIfRunning(task)
                        AppLogger.shared.warn(
                            "⏱️ [SubprocessRunner] \(executable) timed out after \(String(format: "%.2f", timeoutInterval))s - terminated"
                        )
                    }
                })

                // Launch process
                do {
                    if try runContext.launch(task.run) {
                        output.start()
                    } else {
                        output.abandon()
                    }
                } catch {
                    output.abandon()
                    AppLogger.shared.errorUnlessQuietTest("❌ [SubprocessRunner] Failed to launch \(executable): \(error)")
                    runContext.resume(
                        with: .failure(SubprocessError.launchFailed(executable: executable, error: error))
                    )
                }
            }
        }, onCancel: {
            if runContext.resume(with: .failure(CancellationError())) {
                terminateIfRunning(task)
            }
        })
    }

    /// Run launchctl command
    ///
    /// - Parameters:
    ///   - subcommand: launchctl subcommand (e.g., "load", "unload", "list")
    ///   - args: Additional arguments
    /// - Returns: ProcessResult
    /// - Throws: SubprocessError on failure
    public func launchctl(_ subcommand: String, _ args: [String]) async throws -> ProcessResult {
        var allArgs = [subcommand]
        allArgs.append(contentsOf: args)
        return try await run("/bin/launchctl", args: allArgs, timeout: 10)
    }
}

/// Drain both streams while the child runs: waiting for termination first can
/// deadlock a child whose output exceeds the pipe buffer. Blocking reads use
/// dispatch workers rather than the Swift cooperative executor or MainActor.
final class ProcessOutputCapture: @unchecked Sendable {
    private let stdout: Pipe
    private let stderr: Pipe
    private let readers = DispatchGroup()
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    init(stdout: Pipe, stderr: Pipe) {
        self.stdout = stdout
        self.stderr = stderr
        readers.enter()
        readers.enter()
    }

    func start() {
        DispatchQueue.global(qos: .utility).async {
            let data = self.stdout.fileHandleForReading.readDataToEndOfFile()
            self.lock.lock()
            self.stdoutData = data
            self.lock.unlock()
            self.readers.leave()
        }
        DispatchQueue.global(qos: .utility).async {
            let data = self.stderr.fileHandleForReading.readDataToEndOfFile()
            self.lock.lock()
            self.stderrData = data
            self.lock.unlock()
            self.readers.leave()
        }
    }

    /// A failed launch schedules no readers; balance the reservations explicitly.
    func abandon() {
        readers.leave()
        readers.leave()
    }

    func read() -> (Data, Data) {
        readers.wait()
        lock.lock()
        defer { lock.unlock() }
        return (stdoutData, stderrData)
    }
}

// MARK: - Run Context

private final class RunContext: Sendable {
    private struct State {
        var hasCompleted = false
        var continuation: CheckedContinuation<ProcessResult, Error>?
        var pendingResult: Result<ProcessResult, Error>?
        var timeout: Task<Void, Never>?
    }

    private let state = Mutex(State())

    func setContinuation(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        let pending = state.withLock { state in
            let pending = state.pendingResult
            state.pendingResult = nil
            if pending == nil {
                state.continuation = continuation
            }
            return pending
        }
        if let pending {
            continuation.resume(with: pending)
        }
    }

    func setTimeout(_ timeout: Task<Void, Never>) {
        let shouldCancel = state.withLock { state in
            if state.hasCompleted { return true }
            state.timeout = timeout
            return false
        }
        if shouldCancel { timeout.cancel() }
    }

    /// Serialize the launch decision with completion. A pre-launch cancellation
    /// prevents spawning the process, and a later one can see that it started.
    func launch(_ start: () throws -> Void) rethrows -> Bool {
        try state.withLock { state in
            guard !state.hasCompleted else { return false }
            try start()
            return true
        }
    }

    @discardableResult
    func resume(with result: Result<ProcessResult, Error>) -> Bool {
        let completion = state.withLock { state -> (CheckedContinuation<ProcessResult, Error>?, Task<Void, Never>?)? in
            guard !state.hasCompleted else { return nil }
            state.hasCompleted = true
            let continuation = state.continuation
            let timeout = state.timeout
            state.continuation = nil
            state.timeout = nil
            if continuation == nil { state.pendingResult = result }
            return (continuation, timeout)
        }

        guard let (continuation, timeout) = completion else { return false }
        timeout?.cancel()
        continuation?.resume(with: result)
        return true
    }
}

// MARK: - Errors

public enum SubprocessError: Error, Sendable {
    case timeout(executable: String, timeout: TimeInterval)
    case launchFailed(executable: String, error: Error)
    case nonZeroExit(exitCode: Int32)

    var localizedDescription: String {
        switch self {
        case let .timeout(executable, timeout):
            "Subprocess '\(executable)' timed out after \(timeout)s"
        case let .launchFailed(executable, error):
            "Failed to launch '\(executable)': \(error.localizedDescription)"
        case let .nonZeroExit(exitCode):
            "Process exited with non-zero code: \(exitCode)"
        }
    }
}

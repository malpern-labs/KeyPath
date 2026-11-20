import Foundation
import KeyPathCore
import KeyPathPermissions

/// Captures live session runtime evidence within a fixed deadline.
/// Permission evidence is sampled and cached by the permission provider.
@MainActor
public final class SystemValidator: WizardSystemValidating {
    static let canonicalCaptureTimeout: TimeInterval = 12

    // MARK: - Dependencies

    private let systemStateProvider: SystemStateProvider
    private let runtimeEvidence: @MainActor @Sendable () async -> (running: Bool, responding: Bool)
    private let snapshotProvider: (@MainActor () -> SystemSnapshot)?

    package init(
        systemStateProvider: SystemStateProvider = .shared,
        runtimeEvidence: @escaping @MainActor @Sendable () async -> (running: Bool, responding: Bool) = { (false, false) },
        snapshotProvider: (@MainActor () -> SystemSnapshot)? = nil
    ) {
        self.systemStateProvider = systemStateProvider
        self.runtimeEvidence = runtimeEvidence
        self.snapshotProvider = snapshotProvider
    }

    public func checkSystem() async -> SystemSnapshot {
        await checkSystem(freshness: .cached)
    }

    public func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        if let snapshotProvider {
            return snapshotProvider()
        }

        return await Self.boundedCapture(timeout: Self.canonicalCaptureTimeout) {
            await self.captureSessionSnapshot(freshness: freshness)
        }
    }

    static func boundedCapture(
        timeout: TimeInterval,
        operation: @MainActor @Sendable @escaping () async -> SystemSnapshot
    ) async -> SystemSnapshot {
        do {
            return try await withTimeout(.seconds(timeout), cancellation: .returnImmediately, operation: operation)
        } catch is OperationTimeoutError {
            let message = "⏱️ [SystemValidator] Canonical capture timed out after \(String(format: "%.2f", timeout))s"
            if TestEnvironment.isRunningTests {
                AppLogger.shared.info(message)
            } else {
                AppLogger.shared.warn(message)
            }
            return .unavailable(captureStatus: .timedOut, source: "system-validator-timeout")
        } catch {
            return .unavailable(captureStatus: .cancelled, source: "system-validator-cancelled")
        }
    }

    private func captureSessionSnapshot(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        guard !Task.isCancelled else {
            return .unavailable(captureStatus: .cancelled, source: "cancelled")
        }

        let permissions = switch freshness {
        case .cached: await systemStateProvider.currentPermissionSnapshot()
        case .fresh: await systemStateProvider.refreshPermissionSnapshot()
        }
        let (running, responding) = await runtimeEvidence()
        let host = KanataRuntimeHost.current()
        let payload = FileManager.default.fileExists(atPath: host.bridgeLibraryPath)
            && FileManager.default.fileExists(atPath: Bundle.main.executablePath ?? "")
        return SystemSnapshot(
            permissions: permissions,
            components: ComponentStatus(kanataBinaryInstalled: payload, requiredRuntimePayloadPresent: payload),
            conflicts: .empty,
            health: HealthStatus(
                kanataProcessRunning: running, kanataTCPResponding: responding,
                kanataRunning: running && responding,
                kanataInputCaptureReady: running,
                activeRuntimePathTitle: String(localized: "Driverless session runtime"),
                activeRuntimePathDetail: String(localized: "Current user · KeyPath app identity · session event tap")
            ),
            compatibility: SystemCompatibilityStatus(macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString),
            timestamp: Date()
        )
    }
}

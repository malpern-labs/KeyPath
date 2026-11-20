import Foundation
@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore

@MainActor
final class StubSystemValidator: WizardSystemValidating {
    private let snapshots: [SystemSnapshot]
    private var nextSnapshotIndex = 0
    private(set) var freshnessRequests: [WizardSystemSnapshotFreshness] = []

    init(snapshot: SystemSnapshot) {
        snapshots = [snapshot]
    }

    init(context: SystemContext) {
        snapshots = [Self.snapshot(from: context)]
    }

    init(contexts: [SystemContext]) {
        precondition(!contexts.isEmpty)
        snapshots = contexts.map(Self.snapshot(from:))
    }

    init(snapshots: [SystemSnapshot]) {
        precondition(!snapshots.isEmpty)
        self.snapshots = snapshots
    }

    func checkSystem() async -> SystemSnapshot {
        nextSnapshot()
    }

    func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        freshnessRequests.append(freshness)
        return nextSnapshot()
    }

    private func nextSnapshot() -> SystemSnapshot {
        let snapshot = snapshots[nextSnapshotIndex]
        if nextSnapshotIndex < snapshots.count - 1 {
            nextSnapshotIndex += 1
        }
        return snapshot
    }

    private static func snapshot(from context: SystemContext) -> SystemSnapshot {
        SystemSnapshot(
            id: context.snapshotID,
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            compatibility: SystemCompatibilityStatus(
                macOSVersion: context.system.macOSVersion
            ),
            timestamp: context.timestamp
        )
    }
}

@MainActor
extension SystemValidator {
    static func readyTestFixture() -> SystemValidator {
        SystemValidator(snapshotProvider: {
            let now = Date()
            return SystemSnapshot(
                permissions: PermissionOracle.Snapshot(
                    accessibility: .granted,
                    runtimeKeyAccess: .init(status: .granted, source: "test-stub", confidence: .high, timestamp: now),
                    timestamp: now
                ),
                components: ComponentStatus(kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true),
                conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
                health: HealthStatus(kanataRunning: true),
                compatibility: SystemCompatibilityStatus(macOSVersion: "test"),
                timestamp: now
            )
        })
    }
}

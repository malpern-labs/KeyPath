import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import Synchronization
import Testing

@Suite("Explicit reload cooldown")
@MainActor
struct ExplicitReloadCooldownTests {
    private final class State {
        var waits = 0
        var reloads = 0
        var wantsRunning = true
        var intent: UInt64 = 0
    }

    private func coordinator(_ monitor: ReloadSafetyMonitor, state: State,
                             wait: @escaping @MainActor @Sendable (TimeInterval) async throws -> Void) -> ConfigReloadCoordinator
    {
        ConfigReloadCoordinator(
            reloadSafetyMonitor: monitor,
            healthStatusProvider: { .healthy() },
            reloadEngine: { state.reloads += 1; return .success(response: "applied") },
            runtimeWantsRunning: { state.wantsRunning },
            runtimeIntentGeneration: { state.intent },
            sessionValidationOverride: { (.valid, false) },
            cooldownWait: wait
        )
    }

    @Test func waitsForCooldownThenVerifiesEngine() async {
        let clock = Mutex(Date(timeIntervalSince1970: 1000))
        let monitor = ReloadSafetyMonitor(now: { clock.withLock { $0 } })
        await monitor.recordReloadAttempt(succeeded: true)
        let state = State()
        let sut = coordinator(monitor, state: state) { delay in
            state.waits += 1
            clock.withLock { $0 = $0.addingTimeInterval(delay) }
        }
        let result = await sut.triggerConfigReload(scheduleRetryOnPending: false, waitForCooldown: true)
        #expect(result.disposition == .applied)
        #expect(state.waits == 1)
        #expect(state.reloads == 1)
    }

    @Test func manualStopDuringWaitDoesNotReload() async {
        let monitor = ReloadSafetyMonitor()
        await monitor.recordReloadAttempt(succeeded: true)
        let state = State()
        let sut = coordinator(monitor, state: state) { _ in
            state.wantsRunning = false
            state.intent += 1
        }
        let result = await sut.triggerConfigReload(scheduleRetryOnPending: false, waitForCooldown: true)
        #expect(result.disposition == .pending)
        #expect(state.reloads == 0)
    }

    @Test func cancelledWaitDoesNotReload() async {
        let monitor = ReloadSafetyMonitor()
        await monitor.recordReloadAttempt(succeeded: true)
        let state = State()
        let sut = coordinator(monitor, state: state) { _ in throw CancellationError() }
        let result = await sut.triggerConfigReload(scheduleRetryOnPending: false, waitForCooldown: true)
        #expect(result.disposition == .pending)
        #expect(state.reloads == 0)
    }

    @Test func competingCooldownIsBoundedAndNeverBypassed() async {
        let clock = Mutex(Date(timeIntervalSince1970: 1000))
        let monitor = ReloadSafetyMonitor(now: { clock.withLock { $0 } })
        await monitor.recordReloadAttempt(succeeded: true)
        let state = State()
        let sut = coordinator(monitor, state: state) { _ in state.waits += 1 }
        let result = await sut.triggerConfigReload(scheduleRetryOnPending: false, waitForCooldown: true)
        #expect(result.disposition == .pending)
        #expect(state.waits == 3)
        #expect(state.reloads == 0)
    }
}

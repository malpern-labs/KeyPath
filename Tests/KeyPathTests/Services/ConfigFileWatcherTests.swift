import Foundation
@testable import KeyPathAppKit
import Testing
import XCTest

@Suite("ConfigFileWatcher")
@MainActor
struct ConfigFileWatcherTests {
    private func makeTempFile() throws -> (dir: URL, path: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("config.kbd").path
        FileManager.default.createFile(atPath: path, contents: Data("initial".utf8))
        return (dir, path)
    }

    @Test("a real background file event reaches the main actor")
    func backgroundFileEventUsesMainActor() async throws {
        let (directory, path) = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let changed = XCTestExpectation(description: "file change delivered on main actor")
        let watcher = ConfigFileWatcher(delay: { _ in })
        watcher.startWatching(path: path) {
            MainActor.preconditionIsolated()
            changed.fulfill()
        }
        defer { watcher.stopWatching() }
        try "external update".write(toFile: path, atomically: false, encoding: .utf8)
        let outcome = await XCTWaiter.fulfillment(of: [changed], timeout: 2)
        #expect(outcome == .completed)
    }

    @Test("stopping a watch cancels a suspended rebind")
    func stoppedWatchCannotRebind() async throws {
        let (directory, path) = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = WatcherDelayGate()
        let watcher = ConfigFileWatcher(delay: { duration in
            if duration == .milliseconds(50) { await gate.wait() }
        })
        watcher.startWatching(path: path) {}
        let pendingRebind = Task { await watcher.rebindForTesting() }
        let outcome = await XCTWaiter.fulfillment(of: [gate.started], timeout: 2)
        #expect(outcome == .completed)
        watcher.stopWatching()
        gate.release()
        await pendingRebind.value
        #expect(!watcher.isActive)
    }

    @Test("internal revision claims do not survive a different watch")
    func replacementWatchDoesNotInheritInternalClaim() async throws {
        let (directory, firstPath) = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secondPath = directory.appendingPathComponent("second.kbd").path
        try "second baseline".write(toFile: secondPath, atomically: false, encoding: .utf8)
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: firstPath) {}
        watcher.claimInternalContent("same bytes, different watch")
        watcher.stopWatching()
        var callbacks = 0
        watcher.startWatching(path: secondPath) { callbacks += 1 }
        defer { watcher.stopWatching() }
        try "same bytes, different watch".write(toFile: secondPath, atomically: false, encoding: .utf8)
        await watcher.reconcileFileChangeForTesting()
        #expect(callbacks == 1)
    }

    @Test("isActive is false before startWatching")
    func isActiveInitially() {
        let watcher = ConfigFileWatcher()
        #expect(watcher.isActive == false)
    }

    @Test("isActive is true after startWatching")
    @MainActor
    func isActiveAfterStart() throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        #expect(watcher.isActive == true)
        watcher.stopWatching()
    }

    @Test("stopWatching sets isActive to false")
    @MainActor
    func stopWatchingClearsActive() throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        watcher.stopWatching()
        #expect(watcher.isActive == false)
    }

    @Test("starting a new watch stops the previous one")
    @MainActor
    func restartWatchStopsPrevious() throws {
        let (dir, path1) = try makeTempFile()
        let path2 = dir.appendingPathComponent("config2.kbd").path
        FileManager.default.createFile(atPath: path2, contents: Data("second".utf8))

        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path1) {}
        #expect(watcher.isActive == true)

        watcher.startWatching(path: path2) {}
        #expect(watcher.isActive == true)
        watcher.stopWatching()
    }

    @Test("internal revision consumes only its matching write")
    @MainActor
    func internalRevisionConsumesMatchingWrite() async throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()

        var callbackCount = 0
        watcher.startWatching(path: path) { callbackCount += 1 }
        watcher.claimInternalContent("internal-write")

        try "internal-write".write(toFile: path, atomically: true, encoding: .utf8)
        await watcher.reconcileFileChangeForTesting()

        #expect(callbackCount == 0)
        try "external-write".write(toFile: path, atomically: true, encoding: .utf8)
        await watcher.reconcileFileChangeForTesting()
        #expect(callbackCount == 1)
        watcher.stopWatching()
    }

    @Test("rebinding after an atomic save does not swallow the external change")
    @MainActor
    func rebindKeepsExternalChangePending() async throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        var callbackCount = 0
        watcher.startWatching(path: path) { callbackCount += 1 }

        // The rebind runs about 50 ms after the rename, before the 500 ms debounce.
        try "external-write".write(toFile: path, atomically: true, encoding: .utf8)
        await watcher.rebindForTesting()

        await watcher.reconcileFileChangeForTesting()
        #expect(callbackCount == 1)
        await watcher.reconcileFileChangeForTesting()
        #expect(callbackCount == 1, "one change reloads once")
        watcher.stopWatching()
    }

    @Test("rebinding after the app's own atomic save does not reload")
    @MainActor
    func rebindKeepsInternalSaveQuiet() async throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        var callbackCount = 0
        watcher.startWatching(path: path) { callbackCount += 1 }
        watcher.claimInternalContent("internal-write")

        try "internal-write".write(toFile: path, atomically: true, encoding: .utf8)
        await watcher.rebindForTesting()
        await watcher.reconcileFileChangeForTesting()

        #expect(callbackCount == 0)
        watcher.stopWatching()
    }

    @Test("same-mtime external rewrite is reconciled by content")
    @MainActor
    func sameMtimeRewriteTriggersCallback() async throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        var callbackCount = 0
        watcher.startWatching(path: path) { callbackCount += 1 }
        let originalDate = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        try "changed".write(toFile: path, atomically: true, encoding: .utf8)
        if let originalDate {
            try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: path)
        }
        await watcher.reconcileFileChangeForTesting()
        #expect(callbackCount == 1)
        watcher.stopWatching()
    }

    @Test("spurious event retains the pending internal content claim")
    @MainActor
    func spuriousEventRetainsInternalClaim() async throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        var callbackCount = 0
        watcher.startWatching(path: path) { callbackCount += 1 }
        watcher.claimInternalContent("internal-write")
        await watcher.reconcileFileChangeForTesting()
        try "internal-write".write(toFile: path, atomically: true, encoding: .utf8)
        await watcher.reconcileFileChangeForTesting()
        #expect(callbackCount == 0)
        watcher.stopWatching()
    }

    @Test("watches directory when file does not exist yet")
    @MainActor
    func watchesDirectoryForNonExistentFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("not-yet.kbd").path

        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        #expect(watcher.isActive == true)
        watcher.stopWatching()
    }

    @Test("stopWatching is idempotent")
    @MainActor
    func stopWatchingIdempotent() throws {
        let (_, path) = try makeTempFile()
        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: path) {}
        watcher.stopWatching()
        watcher.stopWatching()
        #expect(watcher.isActive == false)
    }
}

@MainActor
private final class WatcherDelayGate {
    let started = XCTestExpectation(description: "rebind reached controlled delay")
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if waiters.isEmpty { started.fulfill() }
            waiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

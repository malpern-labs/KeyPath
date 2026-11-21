import Darwin
@testable import KeyPathCLISupport
import KeyPathCore
@preconcurrency import XCTest

/// ADR-046: the engine admits only the app that launched it, so the CLI's engine
/// commands are runtime-control requests the app answers. These tests stand in a
/// fake app on a socket and check what the facade asks and how it reads answers.
final class ConfigFacadeEngineViaAppTests: XCTestCase {
    /// Serves one canned response per connection and records each request.
    /// One per test: its answers can change, and only its own thread closes its
    /// socket, so a stopped fake can never pick up a later fake's connections.
    private final class FakeApp: @unchecked Sendable {
        typealias Respond = @Sendable (RuntimeControl.Request) -> RuntimeControl.Response
        let path: String
        private let fd: Int32
        private let lock = NSLock()
        private var requests: [RuntimeControl.Request] = []
        private var respond: Respond
        private var stopped = false

        init(respond: @escaping Respond) throws {
            self.respond = respond
            let dir = "/tmp/kp-fa-\(UUID().uuidString.prefix(8))"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            path = dir + "/r.sock"
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = try RuntimeControl.makeAddress(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
            Thread.detachNewThread { [self] in serve() }
        }

        var received: [RuntimeControl.Request] {
            lock.withLock { requests }
        }

        func answer(with respond: @escaping Respond) {
            lock.withLock { self.respond = respond }
        }

        private func serve() {
            defer { close(fd) }
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                defer { close(client) }
                if lock.withLock({ stopped }) { return }
                RuntimeControl.setTimeouts(client, seconds: 2)
                guard let line = try? RuntimeControl.readLine(client),
                      let request = try? JSONDecoder().decode(RuntimeControl.Request.self, from: line)
                else { continue }
                let respond = lock.withLock { () -> Respond in
                    requests.append(request)
                    return self.respond
                }
                if var data = try? JSONEncoder().encode(respond(request)) {
                    data.append(0x0A)
                    try? RuntimeControl.writeAll(client, data)
                }
            }
        }

        /// Wakes the serving thread, which then closes the socket itself.
        func stop() {
            let first = lock.withLock { () -> Bool in
                defer { stopped = true }
                return !stopped
            }
            guard first else { return }
            _ = try? RuntimeControl.send(.init(operation: .status), timeout: 1, socketPath: path)
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
    }

    private static func answer(_ operation: RuntimeControl.Operation, ok: Bool = true, layer: String? = nil,
                               layers: [String]? = nil, hrm: RuntimeControl.HrmStatsSummary? = nil,
                               error: String? = nil) -> RuntimeControl.Response
    {
        var response = RuntimeControl.Response(ok: ok, operation: operation, state: .running, workerPID: 42,
                                               failure: nil, lastError: error, layer: layer, appPID: 1,
                                               appVersion: "test")
        response.layers = layers
        response.hrmStats = hrm
        return response
    }

    private var fake: FakeApp?
    override func tearDown() {
        fake?.stop()
        fake = nil
    }

    private func makeFacade() throws -> ConfigFacade {
        try ConfigFacade(appControlSocketPath: XCTUnwrap(fake).path)
    }

    private func useFakeApp(_ respond: @escaping @Sendable (RuntimeControl.Request) -> RuntimeControl.Response) throws -> FakeApp {
        let app = try FakeApp(respond: respond)
        fake = app
        return app
    }

    func testCurrentLayerAndLayerNamesComeFromTheApp() async throws {
        let app = try useFakeApp { request in
            switch request.operation {
            case .layer: Self.answer(.layer, layer: "nav")
            case .layers: Self.answer(.layers, layers: ["base", "nav"])
            default: Self.answer(request.operation, ok: false, error: "unexpected")
            }
        }
        let facade = try makeFacade()
        let layer = try await facade.tcpGetCurrentLayer()
        let layers = try await facade.tcpGetLayers()
        XCTAssertEqual(layer, "nav")
        XCTAssertEqual(layers, ["base", "nav"])
        XCTAssertEqual(app.received.map(\.operation), [.layer, .layers])
    }

    func testChangeLayerSendsTheNameAndReportsTheAppsAnswer() async throws {
        let app = try useFakeApp { request in
            Self.answer(.changeLayer, ok: request.argument == "nav", error: "no such layer")
        }
        let facade = try makeFacade()
        let switched = await facade.tcpChangeLayer("nav")
        let refused = await facade.tcpChangeLayer("missing")
        XCTAssertTrue(switched)
        XCTAssertFalse(refused)
        XCTAssertEqual(app.received.map(\.argument), ["nav", "missing"])
    }

    func testReloadIsAskedOfTheAppAndFailsWhenItSaysSo() async throws {
        let app = try useFakeApp { _ in Self.answer(.reload) }
        let reloaded = try await makeFacade().tcpReload()
        XCTAssertTrue(reloaded)
        XCTAssertEqual(app.received.map(\.operation), [.reload])

        app.answer { _ in Self.answer(.reload, ok: false, error: "config invalid") }
        let failed = try await makeFacade().tcpReload()
        XCTAssertFalse(failed)
    }

    /// An `ok: false` answer becomes an error carrying the app's own message.
    func testRefusalSurfacesTheAppsMessage() async throws {
        _ = try useFakeApp { _ in Self.answer(.layer, ok: false, error: "The remapping engine did not answer") }
        do {
            _ = try await makeFacade().tcpGetCurrentLayer()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("did not answer"), "\(error)")
        }
    }

    /// Health means the engine answered through the app, not just "running".
    func testHealthNeedsAnEngineAnswer() async throws {
        let app = try useFakeApp { _ in Self.answer(.layer, layer: "base") }
        let healthy = try await makeFacade().tcpCheckHealth()
        XCTAssertTrue(healthy)

        app.answer { _ in Self.answer(.layer, layer: nil) }
        let unhealthy = try await makeFacade().tcpCheckHealth()
        XCTAssertFalse(unhealthy)
    }

    func testHrmStatsAreRelayed() async throws {
        let app = try useFakeApp { request in
            request.operation == .hrmStats
                ? Self.answer(.hrmStats, hrm: .init(totalDecisions: 9, tapCount: 6, holdCount: 3))
                : Self.answer(request.operation)
        }
        let facade = try makeFacade()
        let stats = try await facade.tcpGetHrmStats()
        try await facade.tcpResetHrmStats()
        XCTAssertEqual([stats.totalDecisions, stats.tapCount, stats.holdCount], [9, 6, 3])
        XCTAssertEqual(app.received.map(\.operation), [.hrmStats, .resetHrmStats])
    }

    func testNoAppMeansNotAvailable() async {
        let facade = ConfigFacade(appControlSocketPath: "/tmp/kp-no-app-\(UUID().uuidString.prefix(8)).sock")
        let healthy = await facade.tcpCheckHealth()
        let reloaded = await facade.tcpReload()
        XCTAssertFalse(healthy)
        XCTAssertFalse(reloaded)
    }

    func testConcurrentFacadesKeepTheirOwnAppEndpoints() async throws {
        let firstApp = try FakeApp { _ in Self.answer(.layer, layer: "first") }
        defer { firstApp.stop() }
        let secondApp = try FakeApp { _ in Self.answer(.layer, layer: "second") }
        defer { secondApp.stop() }
        let firstFacade = ConfigFacade(appControlSocketPath: firstApp.path)
        let secondFacade = ConfigFacade(appControlSocketPath: secondApp.path)

        async let firstLayer = firstFacade.tcpGetCurrentLayer()
        async let secondLayer = secondFacade.tcpGetCurrentLayer()
        let layers = try await (firstLayer, secondLayer)
        XCTAssertEqual(layers.0, "first")
        XCTAssertEqual(layers.1, "second")
        XCTAssertEqual(firstApp.received.map(\.operation), [.layer])
        XCTAssertEqual(secondApp.received.map(\.operation), [.layer])
    }
}

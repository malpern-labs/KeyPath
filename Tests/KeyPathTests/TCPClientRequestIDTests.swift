@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Protocol parsing and response-classification tests for KanataTCPClient.
final class TCPClientRequestIDTests: XCTestCase {
    // MARK: - Protocol Parsing Tests

    /// Test that we can parse responses with request_id
    /// This tests our Codable implementation, which could break
    func testRequestIDParsing() throws {
        // HelloOk with request_id
        let helloJson = """
        {"HelloOk":{"version":"1.10.0","protocol":1,"capabilities":["reload"],"request_id":42}}
        """
        let helloData = try XCTUnwrap(helloJson.data(using: .utf8))

        // Extract the HelloOk payload
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: helloData) as? [String: Any])
        let helloOkPayload = try XCTUnwrap(json["HelloOk"] as? [String: Any])
        let payloadData = try JSONSerialization.data(withJSONObject: helloOkPayload)

        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: payloadData)
        XCTAssertEqual(hello.request_id, 42, "Should parse request_id from HelloOk")

        // StatusInfo with request_id
        let statusJson = """
        {"StatusInfo":{"engine_version":"1.10.0","uptime_s":100,"ready":true,"last_reload":{"ok":true,"at":"1234567890"},"request_id":99}}
        """
        let statusData = try XCTUnwrap(statusJson.data(using: .utf8))
        let statusJsonObj = try XCTUnwrap(try JSONSerialization.jsonObject(with: statusData) as? [String: Any])
        let statusPayload = try XCTUnwrap(statusJsonObj["StatusInfo"] as? [String: Any])
        let statusPayloadData = try JSONSerialization.data(withJSONObject: statusPayload)

        let status = try JSONDecoder().decode(
            KanataTCPClient.TcpStatusInfo.self, from: statusPayloadData
        )
        XCTAssertEqual(status.request_id, 99, "Should parse request_id from StatusInfo")
    }

    /// Test that we can parse responses WITHOUT request_id (backward compatibility)
    /// Critical for working with old servers
    func testBackwardCompatibilityParsing() throws {
        // HelloOk without request_id (old server)
        let helloJson = """
        {"HelloOk":{"version":"1.10.0","protocol":1,"capabilities":["reload"]}}
        """
        let helloData = try XCTUnwrap(helloJson.data(using: .utf8))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: helloData) as? [String: Any])
        let helloOkPayload = try XCTUnwrap(json["HelloOk"] as? [String: Any])
        let payloadData = try JSONSerialization.data(withJSONObject: helloOkPayload)

        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: payloadData)
        XCTAssertNil(hello.request_id, "Should parse HelloOk without request_id (old server)")
        XCTAssertEqual(hello.version, "1.10.0", "Should still parse other fields")

        // StatusInfo without request_id
        let statusJson = """
        {"StatusInfo":{"engine_version":"1.10.0","uptime_s":100,"ready":true,"last_reload":{"ok":true,"at":"1234567890"}}}
        """
        let statusData = try XCTUnwrap(statusJson.data(using: .utf8))
        let statusJsonObj = try XCTUnwrap(try JSONSerialization.jsonObject(with: statusData) as? [String: Any])
        let statusPayload = try XCTUnwrap(statusJsonObj["StatusInfo"] as? [String: Any])
        let statusPayloadData = try JSONSerialization.data(withJSONObject: statusPayload)

        let status = try JSONDecoder().decode(
            KanataTCPClient.TcpStatusInfo.self, from: statusPayloadData
        )
        XCTAssertNil(status.request_id, "Should parse StatusInfo without request_id (old server)")
        XCTAssertTrue(status.ready, "Should still parse other fields")
    }

    /// Ensure we can extract request_id from top-level ServerResponse payloads
    func testExtractsTopLevelRequestId() {
        let client = KanataTCPClient(timeout: 0.1)
        let payload = #"{"status":"Ok","request_id":123}"#.data(using: .utf8)!
        let extracted = client._testExtractRequestId(from: payload)
        XCTAssertEqual(extracted, 123)
    }

    // MARK: - Response Detection Tests (Allowlist)

    /// Test that known command responses are correctly identified
    func testIsCommandResponseRecognizesAllResponseTypes() throws {
        let client = KanataTCPClient(timeout: 0.1)

        let responseMessages: [(String, String)] = [
            ("status Ok", #"{"status":"Ok"}"#),
            ("status Error", #"{"status":"Error","msg":"bad config"}"#),
            ("status Ok with request_id", #"{"status":"Ok","request_id":1}"#),
            ("HelloOk", #"{"HelloOk":{"version":"1.10.0","protocol":1}}"#),
            ("StatusInfo", #"{"StatusInfo":{"engine_version":"1.10.0","uptime_s":100}}"#),
            ("ReloadResult", #"{"ReloadResult":{"ok":true}}"#),
            ("LayerNames", #"{"LayerNames":{"names":["base","nav"]}}"#),
            ("FakeKeyNames", #"{"FakeKeyNames":{"names":["lctl","lsft"]}}"#),
            ("CurrentLayerName", #"{"CurrentLayerName":{"name":"base"}}"#),
            ("CurrentLayerInfo", #"{"CurrentLayerInfo":{"keys":{}}}"#),
            (
                "HrmStats",
                #"{"HrmStats":{"schema_version":1,"decisions_total":0,"tap_count":0,"hold_count":0,"reason_counts":{"timeout":0,"release_before_decide":0,"opposite_hand_key":0,"same_hand_key":0,"neutral_key":0,"unknown_hand_key":0,"explicit_policy":0},"avg_decide_latency_ms":0.0,"latency_histogram":{"bucket_0_10":0,"bucket_11_25":0,"bucket_26_50":0,"bucket_51_100":0,"bucket_101_200":0,"bucket_200_plus":0},"same_hand_suppressed_count":0,"opposite_hand_hold_count":0,"neutral_decisions_count":0}}"#
            ),
        ]

        for (name, json) in responseMessages {
            let data = try XCTUnwrap(json.data(using: .utf8))
            XCTAssertTrue(
                client.isCommandResponse(data),
                "\(name) should be recognized as a command response"
            )
        }
    }

    /// Test that broadcast events are NOT classified as command responses
    func testIsCommandResponseRejectsBroadcasts() throws {
        let client = KanataTCPClient(timeout: 0.1)

        let broadcastMessages: [(String, String)] = [
            ("LayerChange", #"{"LayerChange":{"new":"nav"}}"#),
            ("ConfigFileReload", #"{"ConfigFileReload":{}}"#),
            ("MessagePush", #"{"MessagePush":{"msg":"hello"}}"#),
            ("Ready", #"{"Ready":{}}"#),
            ("ConfigError", #"{"ConfigError":{"msg":"bad config"}}"#),
            ("TapActivated", #"{"TapActivated":{"key":"spc"}}"#),
            ("HoldActivated", #"{"HoldActivated":{"key":"spc"}}"#),
            ("KeyInput", #"{"KeyInput":{"key":"a","action":"press"}}"#),
            ("OneShotActivated", #"{"OneShotActivated":{"key":"lsft"}}"#),
            ("ChordResolved", #"{"ChordResolved":{"keys":["a","b"]}}"#),
            ("TapDanceResolved", #"{"TapDanceResolved":{"key":"td1","count":2}}"#),
            ("HrmTrace", #"{"HrmTrace":{"schema_version":1,"key":"f","decision":"hold","reason":"opposite_hand_key","decide_latency_ms":33}}"#),
        ]

        for (name, json) in broadcastMessages {
            let data = try XCTUnwrap(json.data(using: .utf8))
            XCTAssertFalse(
                client.isCommandResponse(data),
                "\(name) should NOT be recognized as a command response"
            )
        }
    }

    /// Test that unknown future broadcast types are automatically filtered
    func testIsCommandResponseRejectsUnknownEventTypes() throws {
        let client = KanataTCPClient(timeout: 0.1)

        let unknownMessages = [
            #"{"NewEventType":{"data":"something"}}"#,
            #"{"FutureFeature":{"value":42}}"#,
            #"{"CustomBroadcast":{}}"#,
        ]

        for json in unknownMessages {
            let data = try XCTUnwrap(json.data(using: .utf8))
            XCTAssertFalse(
                client.isCommandResponse(data),
                "Unknown event type should NOT be classified as a command response: \(json)"
            )
        }
    }

    /// Test edge cases for isCommandResponse
    func testIsCommandResponseEdgeCases() throws {
        let client = KanataTCPClient(timeout: 0.1)

        // Invalid JSON should not be a response
        XCTAssertFalse(try client.isCommandResponse(XCTUnwrap("not json".data(using: .utf8))))

        // Empty object should not be a response
        XCTAssertFalse(try client.isCommandResponse(XCTUnwrap("{}".data(using: .utf8))))

        // Array should not be a response
        XCTAssertFalse(try client.isCommandResponse(XCTUnwrap("[]".data(using: .utf8))))
    }
}

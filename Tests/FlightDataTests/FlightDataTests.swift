//
//  FlightDataTests.swift
//  FlightDataTests
//
//  Created by David Sherlock on 2026.
//
//  Offline, on bodies recorded from opensky-network.org on 2026-09-05.
//  The positional array is the thing worth pinning: index 8 is a boolean
//  sitting between two numbers, and reading it as one would put every
//  aircraft in the air.
//

import Foundation
import XCTest
@testable import FlightData

final class FlightDataTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        var requests: [URLRequest] = []
        let body: String
        let status: Int
        init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
        var transport: FlightData.Transport {
            { [self] request in
                requests.append(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: nil, headerFields: [:])!
                return (Data(body.utf8), response)
            }
        }
    }

    /// Trimmed verbatim from a real `/api/states/all` response.
    private let statesBody = """
    { "time": 1788603288, "states": [
      ["46b831", "AEE6AV  ", "Greece", 1788603288, 1788603288,
       -0.451, 51.4685, 3200.4, false, 231.5, 275.3, -5.2, null, 3350.2, "1000", false, 0],
      ["4008f2", "BAW417  ", "United Kingdom", 1788603280, 1788603288,
       -0.4543, 51.4700, null, true, 0, 90.0, null, null, null, null, false, 0] ] }
    """

    // MARK: - The positional array

    func testAStateVectorIsReadFromItsPositionsWithTheRightTypes() async throws {
        let recorder = Recorder(statesBody)
        let states = try await FlightData(transport: recorder.transport).states()

        XCTAssertEqual(states.count, 2)
        let flying = try XCTUnwrap(states.first)
        XCTAssertEqual(flying.id, "46b831")
        XCTAssertEqual(flying.callsign, "AEE6AV", "the wire pads callsigns to eight characters")
        XCTAssertEqual(flying.originCountry, "Greece")
        XCTAssertEqual(flying.latitude ?? 0, 51.4685, accuracy: 0.0001)
        XCTAssertEqual(flying.longitude ?? 0, -0.451, accuracy: 0.0001)
        XCTAssertEqual(flying.altitude ?? 0, 3200.4, accuracy: 0.1)
        XCTAssertFalse(flying.onGround, "index 8 is a boolean between two numbers")
        XCTAssertEqual(flying.squawk, "1000")
        XCTAssertEqual(flying.verticalRate ?? 0, -5.2, accuracy: 0.1)
        XCTAssertEqual(flying.isClimbing, false, "a negative rate is a descent")
    }

    func testAnAircraftOnTheGroundIsNotReportedAsFlying() async throws {
        let recorder = Recorder(statesBody)
        let states = try await FlightData(transport: recorder.transport).states()

        let parked = try XCTUnwrap(states.last)
        XCTAssertEqual(parked.callsign, "BAW417")
        XCTAssertTrue(parked.onGround)
        XCTAssertNil(parked.altitude, "a null in the row must stay nil, not become zero")
        XCTAssertNil(parked.isClimbing, "level, not climbing and not descending")
    }

    func testNullsAndShortRowsDoNotTrap() throws {
        let short = try JSONDecoder().decode(StateVector.self, from: Data("""
        ["abc123", null, "Ireland"]
        """.utf8))
        XCTAssertEqual(short.id, "abc123")
        XCTAssertNil(short.callsign, "a null callsign is nil, not an empty string")
        XCTAssertNil(short.latitude)
        XCTAssertFalse(short.onGround, "a missing ground flag defaults to airborne, not to a crash")
    }

    func testABlankCallsignIsNilRatherThanWhitespace() throws {
        let blank = try JSONDecoder().decode(StateVector.self, from: Data("""
        ["abc123", "        ", "Ireland"]
        """.utf8))
        XCTAssertNil(blank.callsign)
    }

    // MARK: - Units

    func testUnitsAreConvertedToWhatAviationActuallyStates() async throws {
        let recorder = Recorder(statesBody)
        let states = try await FlightData(transport: recorder.transport).states()
        let flying = try XCTUnwrap(states.first)

        // 231.5 m/s is about 450 knots; 3200 m is about 10,500 feet.
        XCTAssertEqual(flying.speedKnots ?? 0, 450.0, accuracy: 1.0)
        XCTAssertEqual(flying.altitudeFeet ?? 0, 10_500, accuracy: 20)
    }

    // MARK: - Callsign search

    func testACallsignIsMatchedIgnoringCaseAndPadding() async throws {
        let recorder = Recorder(statesBody)
        let client = FlightData(transport: recorder.transport)

        let found = try await client.flight(callsign: "baw417")
        XCTAssertEqual(found?.id, "4008f2")
        let padded = try await client.flight(callsign: "  BAW417 ")
        XCTAssertEqual(padded?.id, "4008f2")
        let missing = try await client.flight(callsign: "XXX999")
        XCTAssertNil(missing, "not in the air is an answer, not an error")
    }

    // MARK: - Bounding boxes

    func testAReversedBoxIsRefusedBecauseTheAPIWouldJustReturnNothing() {
        // The API answers a reversed box with an empty list, which reads as
        // "no aircraft here" rather than "your box is inside out".
        XCTAssertThrowsError(try BoundingBox(minimumLatitude: 51.8, minimumLongitude: -0.6,
                                             maximumLatitude: 51.2, maximumLongitude: 0.4))
        XCTAssertThrowsError(try BoundingBox(minimumLatitude: 51.2, minimumLongitude: 0.4,
                                             maximumLatitude: 51.8, maximumLongitude: -0.6))
        XCTAssertThrowsError(try BoundingBox(minimumLatitude: -91, minimumLongitude: 0,
                                             maximumLatitude: 10, maximumLongitude: 1))
        XCTAssertNoThrow(try BoundingBox(minimumLatitude: 51.2, minimumLongitude: -0.6,
                                         maximumLatitude: 51.8, maximumLongitude: 0.4))
    }

    func testABoxAroundAPointIsClampedAtThePoles() throws {
        let polar = try BoundingBox.around(latitude: 89.8, longitude: 0, degrees: 1)
        XCTAssertEqual(polar.maximumLatitude, 90, "a box may not run off the top of the world")
        XCTAssertEqual(polar.minimumLatitude, 88.8, accuracy: 0.0001)
    }

    func testTheBoxReachesTheRequestAsFourParameters() async throws {
        let recorder = Recorder(#"{ "states": [] }"#)
        _ = try await FlightData(transport: recorder.transport).states(in: .london)

        let url = try XCTUnwrap(recorder.requests.first?.url?.absoluteString)
        for parameter in ["lamin=", "lomin=", "lamax=", "lomax="] {
            XCTAssertTrue(url.contains(parameter), "\(parameter) missing from \(url)")
        }
        let agent = try XCTUnwrap(recorder.requests.first?.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(agent.contains("swift-flight-data"))
    }

    // MARK: - What is no longer anonymous

    /// OpenSky closed these to anonymous callers in 2025. A bare 403 would
    /// look like an outage; naming the cause is the difference between a
    /// user fixing it and filing a bug.
    func testAHistoricalEndpointExplainsThatItNeedsCredentials() async {
        let recorder = Recorder("", status: 403)
        do {
            _ = try await FlightData(transport: recorder.transport)
                .arrivals(airport: "EGLL", from: Date(timeIntervalSince1970: 0), to: Date())
            XCTFail("403 must not pass")
        } catch let error as FlightError {
            guard case .credentialsRequired(let what) = error else {
                return XCTFail("expected .credentialsRequired, got \(error)")
            }
            XCTAssertEqual(what, "Arrivals")
        } catch { XCTFail("unexpected \(error)") }
    }

    func testAQuietAirportIsEmptyNotAnError() async throws {
        // OpenSky answers "nothing in that window" with a 404 and no body.
        let recorder = Recorder("", status: 404)
        let flights = try await FlightData(transport: recorder.transport)
            .arrivals(airport: "EGLL", from: Date(timeIntervalSince1970: 0), to: Date())
        XCTAssertTrue(flights.isEmpty, "a quiet airport must not look like an outage")
    }

    func testARateLimitIsItsOwnError() async {
        let recorder = Recorder("", status: 429)
        do {
            _ = try await FlightData(transport: recorder.transport).states()
            XCTFail("429 must not pass")
        } catch let error as FlightError {
            XCTAssertEqual(error, .rateLimited(retryAfter: nil))
        } catch { XCTFail("unexpected \(error)") }
    }

    // MARK: - Encoding

    func testAStateVectorEncodesAsAnObjectNotAPositionalArray() async throws {
        let recorder = Recorder(statesBody)
        let states = try await FlightData(transport: recorder.transport).states()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(states[0])) as? [String: Any]
        )
        XCTAssertEqual(object["callsign"] as? String, "AEE6AV")
        XCTAssertEqual(object["onGround"] as? Bool, false)
        XCTAssertNotNil(object["speedKnots"], "the useful unit is written alongside the source's")
    }
}

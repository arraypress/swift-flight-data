//
//  LiveTests.swift
//  FlightDataTests
//
//      FD_LIVE=1 swift test --filter LiveTests
//

import Foundation
import XCTest
@testable import FlightData

final class LiveTests: XCTestCase {

    private var isEnabled: Bool { ProcessInfo.processInfo.environment["FD_LIVE"] == "1" }

    func testLivePositionsStillAnswerAnonymously() async throws {
        try XCTSkipUnless(isEnabled, "set FD_LIVE=1 to run")

        let states = try await FlightData().states(in: .london)
        XCTAssertFalse(states.isEmpty, "there is always something over London")

        for state in states.prefix(20) {
            XCTAssertFalse(state.id.isEmpty)
            if let latitude = state.latitude {
                XCTAssertTrue((-90...90).contains(latitude), "\(latitude)")
            }
            if let knots = state.speedKnots {
                XCTAssertLessThan(knots, 1_200, "\(state.callsign ?? state.id) at \(knots) knots")
            }
        }
        // At least one aircraft should be broadcasting a callsign.
        XCTAssertTrue(states.contains { $0.callsign != nil })
    }

    /// Pins the 2025 closure, so if OpenSky ever reopens these the test tells
    /// us rather than the README quietly going stale.
    func testHistoricalEndpointsStillRefuseAnonymousCallers() async throws {
        try XCTSkipUnless(isEnabled, "set FD_LIVE=1 to run")
        do {
            let flights = try await FlightData().arrivals(
                airport: "EDDF",
                from: Date().addingTimeInterval(-172_800),
                to: Date().addingTimeInterval(-86_400)
            )
            // If this ever succeeds, the README's scope section needs updating.
            XCTAssertTrue(flights.isEmpty, "anonymous historical access appears to have reopened")
        } catch let error as FlightError {
            guard case .credentialsRequired = error else {
                return XCTFail("expected .credentialsRequired, got \(error)")
            }
        }
    }
}

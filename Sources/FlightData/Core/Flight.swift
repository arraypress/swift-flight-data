//
//  Flight.swift
//  FlightData
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One completed flight leg, from the historical endpoints.
public struct Flight: Sendable, Codable, Equatable {
    /// The ICAO 24-bit address — the aircraft's permanent id, `46b831`.
    public let icao24: String
    /// The flight number as broadcast, trimmed — `BAW417`.
    public let callsign: String?
    /// ICAO code of the departure airport, when it could be estimated.
    public let departureAirport: String?
    /// ICAO code of the arrival airport, likewise.
    public let arrivalAirport: String?
    /// When the aircraft was first picked up on this flight.
    public let firstSeen: Date?
    /// When it was last picked up.
    public let lastSeen: Date?

    private enum CodingKeys: String, CodingKey {
        case icao24, callsign
        case departureAirport = "estDepartureAirport"
        case arrivalAirport = "estArrivalAirport"
        case firstSeen, lastSeen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.icao24 = (try? container.decode(String.self, forKey: .icao24)) ?? ""
        let raw = ((try? container.decodeIfPresent(String.self, forKey: .callsign)) ?? nil)?
            .trimmingCharacters(in: .whitespaces)
        self.callsign = (raw?.isEmpty ?? true) ? nil : raw
        self.departureAirport = ((try? container.decodeIfPresent(String.self, forKey: .departureAirport)) ?? nil)
        self.arrivalAirport = ((try? container.decodeIfPresent(String.self, forKey: .arrivalAirport)) ?? nil)
        self.firstSeen = ((try? container.decodeIfPresent(Int.self, forKey: .firstSeen)) ?? nil)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        self.lastSeen = ((try? container.decodeIfPresent(Int.self, forKey: .lastSeen)) ?? nil)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

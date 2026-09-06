//
//  StateVector.swift
//  FlightData
//
//  Created by David Sherlock on 2026.
//
//  One aircraft's live position.
//
//  OpenSky sends these as **bare arrays**, not objects: seventeen positional
//  elements, mixed types, any of which can be null.
//
//      ["46b831", "AEE6AV  ", "Greece", 1788603288, 1788603288,
//       -0.451, 51.4685, null, true, 0, 0, null, …]
//
//  Index 8 is a boolean, 2 is a string, most of the rest are numbers. Reading
//  it by position is unavoidable; doing it in one place, with the indices
//  named, is what keeps it honest.
//

import Foundation

/// An aircraft, as last seen.
public struct StateVector: Sendable, Codable, Equatable, Identifiable {

    /// The ICAO 24-bit address — the aircraft's permanent id, `46b831`.
    public let id: String
    /// The flight number as broadcast, trimmed — `BAW417`. Absent when the
    /// crew has not set one.
    public let callsign: String?
    /// The country the registration belongs to.
    public let originCountry: String
    /// When the position was last updated.
    public let lastUpdate: Date?
    /// Degrees east. Absent when the aircraft is not reporting a position.
    public let longitude: Double?
    /// Degrees north. Absent when the aircraft is not reporting a position.
    public let latitude: Double?
    /// Barometric altitude, metres.
    public let altitude: Double?
    /// Geometric altitude, metres.
    public let geometricAltitude: Double?
    /// Whether the aircraft is on the ground.
    public let onGround: Bool
    /// Ground speed, metres per second.
    public let velocity: Double?
    /// Track over ground, degrees clockwise from north.
    public let heading: Double?
    /// Rate of climb, metres per second; negative is a descent.
    public let verticalRate: Double?
    /// The transponder squawk.
    public let squawk: String?

    /// Ground speed in knots, which is how aviation states it.
    public var speedKnots: Double? { velocity.map { $0 * 1.943_844 } }
    /// Altitude in feet, likewise.
    public var altitudeFeet: Double? { (altitude ?? geometricAltitude).map { $0 * 3.280_84 } }
    /// Whether the aircraft is climbing, descending or level.
    public var isClimbing: Bool? {
        guard let verticalRate else { return nil }
        return abs(verticalRate) < 0.5 ? nil : verticalRate > 0
    }

    /// The positional indices, named once.
    private enum Index {
        static let icao24 = 0, callsign = 1, originCountry = 2
        static let timePosition = 3, lastContact = 4
        static let longitude = 5, latitude = 6, baroAltitude = 7
        static let onGround = 8, velocity = 9, trueTrack = 10, verticalRate = 11
        static let geoAltitude = 13, squawk = 14
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        // Decode the row into a loosely-typed array first: the elements are of
        // different types and any can be null, so positional reads have to be
        // tolerant rather than typed at the container.
        var row: [Element] = []
        while !container.isAtEnd {
            row.append((try? container.decode(Element.self)) ?? .none)
        }

        self.id = row[safe: Index.icao24]?.string ?? ""
        // The callsign is space-padded to eight characters in the wire format.
        let raw = row[safe: Index.callsign]?.string?.trimmingCharacters(in: .whitespaces)
        self.callsign = (raw?.isEmpty ?? true) ? nil : raw
        self.originCountry = row[safe: Index.originCountry]?.string ?? ""

        let stamp = row[safe: Index.timePosition]?.number ?? row[safe: Index.lastContact]?.number
        self.lastUpdate = stamp.map { Date(timeIntervalSince1970: $0) }

        self.longitude = row[safe: Index.longitude]?.number
        self.latitude = row[safe: Index.latitude]?.number
        self.altitude = row[safe: Index.baroAltitude]?.number
        self.geometricAltitude = row[safe: Index.geoAltitude]?.number
        self.onGround = row[safe: Index.onGround]?.boolean ?? false
        self.velocity = row[safe: Index.velocity]?.number
        self.heading = row[safe: Index.trueTrack]?.number
        self.verticalRate = row[safe: Index.verticalRate]?.number
        self.squawk = row[safe: Index.squawk]?.string
    }

    public init(id: String, callsign: String?, originCountry: String, lastUpdate: Date? = nil,
                longitude: Double? = nil, latitude: Double? = nil, altitude: Double? = nil,
                geometricAltitude: Double? = nil, onGround: Bool = false, velocity: Double? = nil,
                heading: Double? = nil, verticalRate: Double? = nil, squawk: String? = nil) {
        self.id = id
        self.callsign = callsign
        self.originCountry = originCountry
        self.lastUpdate = lastUpdate
        self.longitude = longitude
        self.latitude = latitude
        self.altitude = altitude
        self.geometricAltitude = geometricAltitude
        self.onGround = onGround
        self.velocity = velocity
        self.heading = heading
        self.verticalRate = verticalRate
        self.squawk = squawk
    }

    /// One element of the mixed-type row.
    private enum Element: Decodable {
        case string(String), number(Double), boolean(Bool), none

        var string: String? { if case .string(let value) = self { return value }; return nil }
        var number: Double? { if case .number(let value) = self { return value }; return nil }
        var boolean: Bool? { if case .boolean(let value) = self { return value }; return nil }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .none; return }
            // Bool before Double: JSONDecoder will happily read `true` as 1.
            if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
            if let value = try? container.decode(Double.self) { self = .number(value); return }
            if let value = try? container.decode(String.self) { self = .string(value); return }
            self = .none
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

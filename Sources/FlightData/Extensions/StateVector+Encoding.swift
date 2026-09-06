//
//  StateVector+Encoding.swift
//  FlightData
//
//  Created by David Sherlock on 2026.
//
//  Encodes as an OBJECT, where the source sends a bare positional array.
//  Nobody downstream should have to know that index 8 is "on ground".
//

import Foundation

extension StateVector {
    private enum OutputKeys: String, CodingKey {
        case id, callsign, originCountry, lastUpdate, longitude, latitude
        case altitude, altitudeFeet, geometricAltitude, onGround
        case velocity, speedKnots, heading, verticalRate, squawk, isClimbing
    }

    /// Writes the named shape, not the positional array OpenSky sends.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: OutputKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(callsign, forKey: .callsign)
        try container.encode(originCountry, forKey: .originCountry)
        try container.encodeIfPresent(lastUpdate, forKey: .lastUpdate)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(altitude, forKey: .altitude)
        try container.encodeIfPresent(altitudeFeet, forKey: .altitudeFeet)
        try container.encodeIfPresent(geometricAltitude, forKey: .geometricAltitude)
        try container.encode(onGround, forKey: .onGround)
        try container.encodeIfPresent(velocity, forKey: .velocity)
        try container.encodeIfPresent(speedKnots, forKey: .speedKnots)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encodeIfPresent(verticalRate, forKey: .verticalRate)
        try container.encodeIfPresent(squawk, forKey: .squawk)
        try container.encodeIfPresent(isClimbing, forKey: .isClimbing)
    }
}

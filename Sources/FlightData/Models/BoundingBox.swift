//
//  BoundingBox.swift
//  FlightData
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A latitude/longitude box to search within.
public struct BoundingBox: Sendable, Equatable {
    public let minimumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLatitude: Double
    public let maximumLongitude: Double

    /// A box, validated.
    ///
    /// - Throws: ``FlightError/badBoundingBox(_:)`` if the corners are
    ///   swapped or out of range — the API answers a reversed box with an
    ///   empty list rather than an error, which reads as "no aircraft".
    public init(minimumLatitude: Double, minimumLongitude: Double,
                maximumLatitude: Double, maximumLongitude: Double) throws {
        guard (-90...90).contains(minimumLatitude), (-90...90).contains(maximumLatitude) else {
            throw FlightError.badBoundingBox("latitude must be between -90 and 90")
        }
        guard (-180...180).contains(minimumLongitude), (-180...180).contains(maximumLongitude) else {
            throw FlightError.badBoundingBox("longitude must be between -180 and 180")
        }
        guard minimumLatitude < maximumLatitude else {
            throw FlightError.badBoundingBox("minimum latitude must be south of the maximum")
        }
        guard minimumLongitude < maximumLongitude else {
            throw FlightError.badBoundingBox("minimum longitude must be west of the maximum")
        }
        self.minimumLatitude = minimumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLatitude = maximumLatitude
        self.maximumLongitude = maximumLongitude
    }

    /// A box of `radius` degrees around a point.
    ///
    /// Degrees, not kilometres, on purpose: a degree of longitude is a
    /// different distance at every latitude, and pretending otherwise would
    /// make the box quietly wrong near the poles.
    public static func around(latitude: Double, longitude: Double,
                              degrees radius: Double = 0.5) throws -> BoundingBox {
        try BoundingBox(
            minimumLatitude: max(-90, latitude - radius),
            minimumLongitude: max(-180, longitude - radius),
            maximumLatitude: min(90, latitude + radius),
            maximumLongitude: min(180, longitude + radius)
        )
    }

    /// A few boxes worth having by name.
    public static var london: BoundingBox { try! BoundingBox(minimumLatitude: 51.2, minimumLongitude: -0.6,
                                                             maximumLatitude: 51.8, maximumLongitude: 0.4) }
    public static var newYork: BoundingBox { try! BoundingBox(minimumLatitude: 40.4, minimumLongitude: -74.3,
                                                              maximumLatitude: 41.0, maximumLongitude: -73.6) }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "lamin", value: String(minimumLatitude)),
            URLQueryItem(name: "lomin", value: String(minimumLongitude)),
            URLQueryItem(name: "lamax", value: String(maximumLatitude)),
            URLQueryItem(name: "lomax", value: String(maximumLongitude)),
        ]
    }
}

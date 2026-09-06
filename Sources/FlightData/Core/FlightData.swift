//
//  FlightData.swift
//  FlightData
//
//  Created by David Sherlock on 2026.
//
//  Live aircraft positions, keyless.
//
//  OpenSky's network of receivers publishes what every transponder in range is
//  broadcasting. `/states/all` still answers anonymously; the historical
//  `/flights/*` endpoints were closed to anonymous callers in 2025 and now
//  return 403 without OAuth2 credentials. Measured 2026-09-05.
//
//  So the honest split is:
//
//    keyless   where an aircraft is, right now — position, altitude, speed,
//              heading, callsign, whether it is on the ground
//    keyed     historical arrivals and departures by airport
//    neither   gates, terminals and scheduled-vs-actual delay times, which
//              OpenSky does not carry at all — those come from an airline
//              schedule provider, not from a transponder
//
//  That last line matters: this library will not tell you a flight is delayed.
//  It will tell you the aircraft is still on the ground in Frankfurt.
//

//

import Foundation

/// A keyless client for live aircraft positions.
public struct FlightData: Sendable {

    /// How requests are performed — injectable so tests run on recordings.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Sent on every request, so OpenSky can see who is calling.
    public static let defaultUserAgent = "swift-flight-data/0.1 (+https://github.com/arraypress/swift-flight-data)"
    /// The API host. Overridable so tests can point somewhere else.
    public static let defaultHost = "opensky-network.org"

    /// Sent on every request made by this client.
    public let userAgent: String
    private let host: String
    private let transport: Transport

    public init(userAgent: String = FlightData.defaultUserAgent,
                host: String = FlightData.defaultHost,
                transport: Transport? = nil) {
        self.userAgent = userAgent
        self.host = host
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FlightError.malformed("not an HTTP response")
            }
            return (data, http)
        }
    }

    // MARK: - Live positions

    /// Every aircraft currently reporting inside `box`.
    ///
    /// A box is strongly advised: without one the request returns the whole
    /// world, which is megabytes and burns the anonymous allowance fast.
    public func states(in box: BoundingBox? = nil) async throws -> [StateVector] {
        let data = try await get("/api/states/all", query: box?.queryItems ?? [])
        struct Response: Decodable { let time: Int?; let states: [StateVector]? }
        return try decode(Response.self, from: data).states ?? []
    }

    /// The aircraft flying a callsign right now, if it is in the air.
    ///
    /// - Parameters:
    ///   - callsign: `BAW417`, `KLM627`. Matched case-insensitively and
    ///     ignoring the padding the wire format adds.
    ///   - box: Narrow the search; without one this scans the world's traffic,
    ///     which is a large download for one aircraft.
    public func flight(callsign: String, in box: BoundingBox? = nil) async throws -> StateVector? {
        let wanted = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !wanted.isEmpty else { return nil }
        return try await states(in: box).first {
            $0.callsign?.uppercased() == wanted
        }
    }

    /// Aircraft near a point.
    public func near(latitude: Double, longitude: Double,
                     degrees radius: Double = 0.5) async throws -> [StateVector] {
        try await states(in: BoundingBox.around(latitude: latitude, longitude: longitude, degrees: radius))
    }

    // MARK: - Historical (credentials required)

    /// Arrivals at an ICAO airport code in a time window.
    ///
    /// - Note: **Needs OpenSky credentials.** This endpoint stopped answering
    ///   anonymous callers in 2025; calling it without them throws
    ///   ``FlightError/credentialsRequired(_:)`` rather than a bare 403.
    public func arrivals(airport: String, from: Date, to: Date) async throws -> [Flight] {
        try await flights("arrival", airport: airport, from: from, to: to)
    }

    /// Departures from an ICAO airport code in a time window.
    ///
    /// - Note: **Needs OpenSky credentials** — see ``arrivals(airport:from:to:)``.
    public func departures(airport: String, from: Date, to: Date) async throws -> [Flight] {
        try await flights("departure", airport: airport, from: from, to: to)
    }

    private func flights(_ kind: String, airport: String, from: Date, to: Date) async throws -> [Flight] {
        let data = try await get("/api/flights/\(kind)", query: [
            URLQueryItem(name: "airport", value: airport.uppercased()),
            URLQueryItem(name: "begin", value: String(Int(from.timeIntervalSince1970))),
            URLQueryItem(name: "end", value: String(Int(to.timeIntervalSince1970))),
        ], needsCredentials: "\(kind == "arrival" ? "Arrivals" : "Departures")")
        return try decode([Flight].self, from: data)
    }

    // MARK: - Transport

    private func get(_ path: String, query: [URLQueryItem],
                     needsCredentials: String? = nil) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else {
            throw FlightError.malformed("could not build a URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 200:
            return data
        case 404:
            // OpenSky answers "no flights in that window" with a 404 and an
            // empty body. That is not an error, and treating it as one would
            // make a quiet airport look like an outage.
            return Data("[]".utf8)
        case 401, 403:
            if let needsCredentials {
                throw FlightError.credentialsRequired(needsCredentials)
            }
            throw FlightError.http(response.statusCode)
        case 429:
            let after = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw FlightError.rateLimited(retryAfter: after)
        default:
            throw FlightError.http(response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FlightError.malformed(error.localizedDescription)
        }
    }
}

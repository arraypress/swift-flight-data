//
//  FlightError.swift
//  FlightData
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong tracking aircraft.
public enum FlightError: Error, LocalizedError, Sendable, Equatable {
    case http(Int)
    case rateLimited(retryAfter: Int?)
    case malformed(String)
    /// The endpoint asked for needs credentials this client does not have.
    ///
    /// OpenSky closed its historical `/flights/*` endpoints to anonymous
    /// callers in 2025; live positions stayed open.
    case credentialsRequired(String)
    /// A bounding box that is not a box.
    case badBoundingBox(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "OpenSky answered HTTP \(code)"
        case .rateLimited(let after):
            return "OpenSky is rate-limiting" + (after.map { " (retry after \($0)s)" } ?? "")
        case .malformed(let what): return "unexpected response shape: \(what)"
        case .credentialsRequired(let what):
            return "\(what) needs OpenSky credentials — live positions do not"
        case .badBoundingBox(let why): return "bad bounding box: \(why)"
        }
    }
}

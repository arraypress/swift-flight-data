# swift-flight-data

Where aircraft are, right now. No key.

```swift
import FlightData

let flights = FlightData()

try await flights.states(in: .london)        // everything overhead
try await flights.flight(callsign: "BAW417") // one aircraft
try await flights.near(latitude: 51.47, longitude: -0.45)
```

## What this can and cannot tell you

OpenSky's receiver network publishes what transponders are broadcasting. That
makes the honest scope narrower than "flight status":

| Access | What you get |
|---|---|
| **Keyless** | position, altitude, ground speed, heading, climb rate, callsign, squawk, whether it is on the ground |
| **Needs credentials** | historical arrivals and departures by airport — closed to anonymous callers in 2025 |
| **Not available at all** | gates, terminals, scheduled-vs-actual times, delay status |

That last row is the important one. **This library will not tell you a flight is
delayed.** It will tell you the aircraft is still on the ground in Frankfurt,
which is often the same information arrived at honestly. Gates and schedules
come from an airline schedule provider, not from a transponder.

Measured 2026-09-05: `/api/states/all` answers anonymously; `/api/flights/*`
returns 403 without OAuth2 credentials.

## Use

```swift
try await flights.states(in: .london)
try await flights.states(in: try BoundingBox(minimumLatitude: 51.2, minimumLongitude: -0.6,
                                             maximumLatitude: 51.8, maximumLongitude: 0.4))
try await flights.near(latitude: 40.64, longitude: -73.78, degrees: 0.3)
try await flights.flight(callsign: "KLM627", in: .london)
```

Pass a bounding box. Without one the request returns the whole world's traffic —
megabytes, and it burns the anonymous allowance quickly.

Readings come out in the units aviation actually uses, alongside the source's
metric ones:

```swift
state.altitudeFeet   // 10,500 — where the source sends 3200.4 metres
state.speedKnots     // 450    — where the source sends 231.5 m/s
state.isClimbing     // true, false, or nil for level flight
state.onGround
```

## The shape trap

State vectors arrive as **bare positional arrays**, not objects — seventeen
mixed-type elements, any of which can be null:

```json
["46b831", "AEE6AV  ", "Greece", 1788603288, 1788603288,
 -0.451, 51.4685, 3200.4, false, 231.5, 275.3, -5.2, …]
```

Index 8 is a boolean sitting between two numbers, and `JSONDecoder` will read
`true` as `1` if you ask it for a number — putting every aircraft in the air.
Callsigns are space-padded to eight characters. This library reads the row by
named index, once, and **encodes back out as an object**, so nothing downstream
needs to know that position 8 means "on ground".

## Two failures that are not failures

- A **reversed bounding box** is refused locally. The API answers one with an
  empty list, which reads as "no aircraft here" rather than "your box is inside
  out".
- A **404 from the historical endpoints means "no flights in that window"**, not
  an error — a quiet airport must not look like an outage. It comes back as an
  empty list.

## Tested

15 tests. Thirteen offline on recorded bodies, pinning the positional decoding,
the null handling, the unit conversions and both non-failures. Two live: that
anonymous position access still works, and that the historical endpoints still
refuse — so if OpenSky ever reopens them, the test says so rather than this
README quietly going stale. Both passed 2026-09-05.

```console
$ FD_LIVE=1 swift test --filter LiveTests
```

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-flight-data.git", from: "0.1.0")
```

## Licence

MIT for this code. OpenSky's data is free for non-commercial use; check their
terms for anything else.

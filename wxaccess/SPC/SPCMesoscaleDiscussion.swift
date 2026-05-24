import Foundation
import CoreLocation

struct SPCMesoscaleDiscussion: Sendable, Identifiable {
    let id: String
    let number: Int
    let issued: Date
    let expires: Date
    let concerning: String
    let affected: String
    let polygon: [CLLocationCoordinate2D]

    var isActive: Bool { expires > .now }

    var accessibilityLabel: String {
        "Mesoscale Discussion \(number): \(concerning). Affects \(affected). Expires \(expires.formatted(date: .omitted, time: .shortened)) UTC."
    }
}

import Foundation

/// Sendable is spelled out because public types don't get the implicit
/// conformance non-public ones do — without it, consumers can't hold items
/// in a `static let` under Swift 6.
public struct TabItem: Equatable, Sendable {
    public let title: String
    public let systemImage: String

    /// - Parameter systemImage: an SF Symbol name.
    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
}

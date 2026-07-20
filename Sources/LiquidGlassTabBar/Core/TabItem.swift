import Foundation

public struct TabItem: Equatable {
    public let title: String
    public let systemImage: String

    /// - Parameter systemImage: an SF Symbol name.
    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
}

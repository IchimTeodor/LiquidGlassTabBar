import Foundation

/// The mark drawn at a tab item's top-trailing corner.
///
/// Set one on a `TabItem` to give it a starting badge, or change it later
/// with the bar's `setBadge(_:at:)` — badges are state, not configuration.
public enum TabBadge: Equatable, Sendable {
    /// No badge.
    case none
    /// A small filled circle with no content — "something changed".
    case dot
    /// Arbitrary short text. Empty text draws nothing, so a value computed
    /// from state can be passed straight through.
    case text(String)
}

public extension TabBadge {
    /// A numeric badge, clamped so large values read as e.g. "99+".
    ///
    /// A factory rather than a case: counts are just text once rendered, and
    /// keeping the enum to three cases means callers switching over a badge
    /// have three things to handle instead of four. Zero returns `.none`, so
    /// an unread count can be bound directly without special-casing empty.
    static func count(_ value: Int, maximum: Int = 99) -> TabBadge {
        guard value > 0 else { return .none }
        return .text(value > maximum ? "\(maximum)+" : "\(value)")
    }
}

extension TabBadge {
    /// The text drawn inside the badge, or nil for a bare dot / no badge.
    var displayText: String? {
        switch self {
        case .none, .dot: return nil
        case .text(let text): return text.isEmpty ? nil : text
        }
    }

    /// Whether anything is drawn at all.
    var isVisible: Bool {
        switch self {
        case .none: return false
        case .dot: return true
        case .text(let text): return !text.isEmpty
        }
    }
}

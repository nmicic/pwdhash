import Foundation

/// ContinuousClock includes device sleep and is unaffected by wall-clock edits.
/// Holds no credentials. The UI must clear before accepting an expired action.
struct IdleDeadline {
    static let timeout: Duration = .seconds(300)
    private(set) var deadline: ContinuousClock.Instant?

    mutating func touch(at now: ContinuousClock.Instant = .now) {
        deadline = now.advanced(by: Self.timeout)
    }

    func isExpired(at now: ContinuousClock.Instant = .now) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    mutating func reset() { deadline = nil }
}

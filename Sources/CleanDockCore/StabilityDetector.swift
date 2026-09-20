import Foundation

/// Tells a tracking burst when the observed state changed and when it has been quiet long enough to stop.
public struct StabilityDetector<State: Equatable> {
    private let quietPeriod: TimeInterval
    private var last: State?
    private var hasValue = false
    private var changedAt: TimeInterval = 0

    public init(quietPeriod: TimeInterval) { self.quietPeriod = quietPeriod }

    public mutating func observe(_ state: State, at time: TimeInterval) -> (changed: Bool, settled: Bool) {
        let changed = !hasValue || last != state
        if changed {
            last = state
            hasValue = true
            changedAt = time
        }
        return (changed, time - changedAt > quietPeriod)
    }
}

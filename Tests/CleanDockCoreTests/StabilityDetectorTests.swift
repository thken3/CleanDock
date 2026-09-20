import Testing
@testable import CleanDockCore

@Test func firstObservationIsAChange() {
    var detector = StabilityDetector<Int>(quietPeriod: 0.3)
    let r = detector.observe(1, at: 10)
    #expect(r.changed)
    #expect(!r.settled)
}

@Test func settlesAfterTheQuietPeriod() {
    var detector = StabilityDetector<Int>(quietPeriod: 0.3)
    _ = detector.observe(1, at: 10)
    #expect(detector.observe(1, at: 10.1) == (false, false))
    #expect(detector.observe(1, at: 10.25) == (false, false))
    #expect(detector.observe(1, at: 10.31) == (false, true))
}

@Test func aChangeRestartsTheQuietPeriod() {
    var detector = StabilityDetector<Int>(quietPeriod: 0.3)
    _ = detector.observe(1, at: 10)
    #expect(detector.observe(2, at: 10.25) == (true, false))
    #expect(detector.observe(2, at: 10.5) == (false, false))
    #expect(detector.observe(2, at: 10.56) == (false, true))
}

@Test func optionalStatesCompareByValue() {
    var detector = StabilityDetector<Int?>(quietPeriod: 0.3)
    #expect(detector.observe(nil, at: 0).changed)
    #expect(!detector.observe(nil, at: 0.1).changed)
    #expect(detector.observe(5, at: 0.2).changed)
}

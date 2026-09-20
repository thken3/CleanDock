import CleanDockCore
import Foundation

/// Owns all Dock reads. Idle: a cheap outline check every 0.5 s and a full comparison every 2 s (catches badge changes).
/// Burst: reads the Dock as fast as it answers and forwards every change, until it has been stable for 0.3 s.
final class MotionTracker {
    private let reader: DockReader
    private let apply: (DockSnapshot?) -> Void
    private let queue = DispatchQueue(label: "app.cleandock.tracker", qos: .userInteractive)
    private let lock = NSLock()
    private var bursting = false
    private var kickedAt: TimeInterval = 0
    private var timer: DispatchSourceTimer?

    // Only touched on `queue`.
    private var lastOutline: DockOutline?
    private var lastSnapshot: DockSnapshot?
    private var ticks = 0

    init(reader: DockReader, apply: @escaping (DockSnapshot?) -> Void) {
        self.reader = reader
        self.apply = apply
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.idleTick() }
        timer.resume()
        self.timer = timer
        kick()
    }

    /// Starts a burst, or keeps the running one alive for at least another 0.3 s. Safe from any thread.
    func kick() {
        lock.lock()
        kickedAt = ProcessInfo.processInfo.systemUptime
        let start = !bursting
        bursting = true
        lock.unlock()
        if start { queue.async { [weak self] in self?.burst() } }
    }

    private func burst() {
        var detector = StabilityDetector<DockSnapshot?>(quietPeriod: 0.3)
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let snapshot = reader.snapshot()
            let result = detector.observe(snapshot, at: now)
            if result.changed {
                lastSnapshot = snapshot
                DispatchQueue.main.async { [apply] in apply(snapshot) }
            }
            lock.lock()
            let done = result.settled && now - kickedAt > 0.3
            if done { bursting = false }
            lock.unlock()
            if done { break }
            usleep(4000)
        }
        lastOutline = reader.outline()
    }

    private func idleTick() {
        lock.lock()
        let busy = bursting
        lock.unlock()
        if busy { return }
        ticks += 1
        if ticks % 4 == 0 {
            if reader.snapshot() != lastSnapshot { kick() }
        } else if reader.outline() != lastOutline {
            kick()
        }
    }
}

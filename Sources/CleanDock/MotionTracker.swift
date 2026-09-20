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

    // Coalescing for the main-queue hop: at most one hop in flight, always delivering the newest snapshot.
    private var hopScheduled = false
    private var pendingSnapshot: DockSnapshot?

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
                scheduleApply(snapshot)
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

    /// Keeps only the newest snapshot and schedules at most one pending hop to the main queue,
    /// so a slow `apply` cannot let the main queue grow unbounded during a fast burst.
    private func scheduleApply(_ snapshot: DockSnapshot?) {
        lock.lock()
        pendingSnapshot = snapshot
        let alreadyScheduled = hopScheduled
        hopScheduled = true
        lock.unlock()
        guard !alreadyScheduled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let next = self.pendingSnapshot
            self.hopScheduled = false
            self.lock.unlock()
            self.apply(next)
        }
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

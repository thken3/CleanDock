import CleanDockCore
import Foundation

/// Owns all Dock reads. What it costs depends on the mode `AppController` sets from the status it computes:
///
/// - `.tracking`: a cheap outline check every 0.5 s (plus a full comparison every fourth tick, which catches
///   badge changes), and on every `kick()` a burst that reads the Dock as fast as it answers and forwards
///   every change until it has been stable for 0.3 s.
/// - `.watching`: the overlay is not drawn, so there is nothing to follow. The timer ticks every 2 s and only
///   compares the cheap outline; a change, and every `kick()`, costs exactly one snapshot read. That one read
///   is what lets `AppController` notice the Dock came back to a 1x display.
/// - `.suspended`: the timer is suspended, `kick()` does nothing, and no Accessibility call is made at all.
final class MotionTracker {
    enum Mode { case tracking, watching, suspended }

    private let reader: DockReader
    private let apply: (DockSnapshot?) -> Void
    private let queue = DispatchQueue(label: "app.cleandock.tracker", qos: .userInteractive)
    private let lock = NSLock()
    private var mode = Mode.tracking
    private var bursting = false
    private var kickedAt: TimeInterval = 0
    /// Counts kicks so a read can tell whether one arrived while it was running. Guarded by `lock`.
    private var kicks: UInt64 = 0

    // Coalescing for the main-queue hop: at most one hop in flight, always delivering the newest snapshot.
    private var hopScheduled = false
    private var pendingSnapshot: DockSnapshot?

    // Only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var timerRunning = false
    private var timerInterval: TimeInterval = 0
    private var lastOutline: DockOutline?
    private var lastSnapshot: DockSnapshot?
    private var ticks = 0

    init(reader: DockReader, apply: @escaping (DockSnapshot?) -> Void) {
        self.reader = reader
        self.apply = apply
    }

    deinit {
        // A suspended dispatch source must not be released.
        if let timer, !timerRunning { timer.resume() }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.setEventHandler { [weak self] in self?.idleTick() }
            self.timer = timer                  // created suspended; `scheduleTimer` starts it in the right mode
            self.scheduleTimer()
        }
        kick()
    }

    /// Safe from any thread. Takes effect on the next burst iteration and on the next timer tick.
    func setMode(_ new: Mode) {
        lock.lock()
        let changed = mode != new
        mode = new
        lock.unlock()
        guard changed else { return }
        queue.async { [weak self] in self?.scheduleTimer() }
    }

    /// Starts a read, or keeps a running burst alive for at least another 0.3 s. Safe from any thread.
    /// Does nothing while suspended.
    func kick() {
        lock.lock()
        guard mode != .suspended else { return lock.unlock() }
        kickedAt = ProcessInfo.processInfo.systemUptime
        kicks &+= 1
        let start = !bursting
        bursting = true
        lock.unlock()
        if start { queue.async { [weak self] in self?.burst() } }
    }

    /// Only on `queue`.
    private func scheduleTimer() {
        guard let timer else { return }
        lock.lock()
        let mode = self.mode
        lock.unlock()
        guard mode != .suspended else {
            if timerRunning { timer.suspend(); timerRunning = false }
            return
        }
        let interval: TimeInterval = mode == .tracking ? 0.5 : 2
        if timerInterval != interval {
            timerInterval = interval
            timer.schedule(deadline: .now() + interval, repeating: interval)
        }
        if !timerRunning { timer.resume(); timerRunning = true }
    }

    private func burst() {
        var detector = StabilityDetector<DockSnapshot?>(quietPeriod: 0.3)
        while true {
            lock.lock()
            let mode = self.mode
            let seen = kicks
            lock.unlock()

            guard mode != .suspended else {
                lock.lock()
                bursting = false
                lock.unlock()
                return                          // no Accessibility call, and no outline read either
            }

            let now = ProcessInfo.processInfo.systemUptime
            let snapshot = reader.snapshot()
            let result = detector.observe(snapshot, at: now)
            if result.changed {
                lastSnapshot = snapshot
                scheduleApply(snapshot)
            }

            lock.lock()
            // `.tracking` keeps reading until the Dock has been quiet for 0.3 s and no kick is newer than that.
            // `.watching` stops after this one read unless a kick arrived while it was running. Both decisions
            // are made in the same critical section that `kick()` uses, so a kick can never be lost: either it
            // lands before this and forces another iteration, or it lands after `bursting` went false and
            // starts a new burst itself.
            let done = mode == .tracking ? (result.settled && now - kickedAt > 0.3) : (kicks == seen)
            if done { bursting = false }
            lock.unlock()
            if done { break }
            // The Accessibility round trip, not this sleep, is what limits the rate; the sleep only keeps
            // a tight loop from spinning the core when the Dock answers unusually fast.
            if mode == .tracking { usleep(4000) }
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
        let mode = self.mode
        lock.unlock()
        guard !busy, mode != .suspended else { return }
        ticks += 1
        // The outline is always compared; the full snapshot comparison is an extra, not a replacement.
        if reader.outline() != lastOutline { return kick() }
        guard mode == .tracking, ticks % 4 == 0 else { return }
        if reader.snapshot() != lastSnapshot { kick() }
    }
}

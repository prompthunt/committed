import Foundation

/// The refresh timer, fired by hand, so no test waits on real time. Pass `timer.sleep` as
/// `RefreshCoordinator(sleep:)` (Mac tests) or `AppDependencies.timerSleep` (iPhone tests).
/// Compiled into both test targets. A paused timer's wait is cancelled, so it stops at once.
final class ManualTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: (id: UUID, continuation: CheckedContinuation<Void, any Error>)?
    private var waits = 0
    private var onWait: [(after: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Whether the timer is counting down to a refresh.
    var isWaiting: Bool { lock.withLock { waiter != nil } }

    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                startWaiting(id: id, continuation)
            }
        } onCancel: {
            stopWaiting(id: id)
        }
    }

    private func startWaiting(id: UUID, _ continuation: CheckedContinuation<Void, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        waiter = (id, continuation)
        waits += 1
        for entry in onWait where entry.after < waits { entry.continuation.resume() }
        onWait.removeAll { $0.after < waits }
    }

    private func stopWaiting(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let current = waiter, current.id == id else { return }
        current.continuation.resume(throwing: CancellationError())
        waiter = nil
    }

    /// Fire the timer once and return when it's waiting again, so its refresh has finished.
    func tick() async {
        await waitForWait(after: 0)
        let fired = fire()
        await waitForWait(after: fired)
    }

    /// Ends the current wait; returns how many waits had started.
    private func fire() -> Int {
        lock.lock()
        defer { lock.unlock() }
        waiter?.continuation.resume()
        waiter = nil
        return waits
    }

    /// Returns once the timer has started more than `after` waits and is waiting now.
    private func waitForWait(after: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            defer { lock.unlock() }
            if waits > after, waiter != nil {
                continuation.resume()
            } else {
                onWait.append((after, continuation))
            }
        }
    }
}

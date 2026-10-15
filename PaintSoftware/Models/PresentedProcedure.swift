import Foundation

/// One immutable tick has one producer and one matching presentation. Mutation boundaries can
/// settle its completed result without asking a second producer to repeat the work.
final class PresentedProcedure<Value> {
    private let lock = NSCondition()
    private var value: Value?
    private var presented = false
    private var rejected = false
    private var finish: ((Value) -> Void)?
    private var cancelled = false
    private var computations = 0
    private var resolving = false

    var completedValue: Value? { locked { value } }

    var isPending: Bool { locked { finish != nil } }
    var isPresented: Bool { locked { presented } }
    var resolutionCount: Int { locked { computations } }
    var isResolving: Bool { locked { resolving } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    func resolve(_ compute: () -> Value) -> Value {
        lock.lock()
        while resolving { lock.wait() }
        if let value { lock.unlock(); return value }
        resolving = true
        computations += 1
        lock.unlock()
        let result = compute()
        lock.lock()
        value = result
        resolving = false
        lock.broadcast()
        lock.unlock()
        return result
    }

    func didPresent() {
        lock.lock()
        presented = true
        let result = value
        let callback = result == nil ? nil : finish
        if callback != nil { finish = nil }
        lock.unlock()
        if let result { callback?(result) }
    }

    /// A completed draw that failed validation is an outcome too, but never a shown picture.
    /// Called by the presenter's main-thread completion, not by the producer.
    func didReject() {
        lock.lock()
        rejected = true
        let result = value
        let callback = result == nil ? nil : finish
        if callback != nil { finish = nil }
        lock.unlock()
        if let result { callback?(result) }
    }

    func finishWhenPresented(_ callback: @escaping (Value) -> Void) {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        let ready = (presented || rejected) ? value : nil
        if ready == nil { finish = callback }
        lock.unlock()
        if let ready { callback(ready) }
    }

    func settlePending(_ compute: () -> Value) {
        lock.lock()
        let callback = finish
        finish = nil
        lock.unlock()
        if let callback { callback(compute()) }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        finish = nil
    }
}

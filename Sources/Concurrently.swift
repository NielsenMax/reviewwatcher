import Foundation

/// Runs `body` for every item side by side and hands back each outcome in the items' order.
func concurrently<Item, Value>(_ items: [Item], _ body: (Item) throws -> Value) -> [Result<Value, Error>] {
    var results = [Result<Value, Error>?](repeating: nil, count: items.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: items.count) { index in
        let result = Result { try body(items[index]) }
        lock.lock()
        results[index] = result
        lock.unlock()
    }
    return results.map { $0 ?? .failure(WatcherError.setup("concurrentPerform skipped an item")) }
}

import Foundation
import Vision

/// Bridges Swift task cancellation to Vision's synchronous request API by forwarding the
/// cancellation signal to every registered VNRequest.
final class VisionRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var requests: [VNRequest] = []

    func register(_ request: VNRequest) {
        lock.lock()
        if cancelled {
            lock.unlock()
            request.cancel()
            return
        }
        requests.append(request)
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let activeRequests = requests
        requests.removeAll()
        lock.unlock()

        activeRequests.forEach { $0.cancel() }
    }
}

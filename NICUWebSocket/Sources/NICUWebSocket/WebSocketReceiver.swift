import Foundation

/// Connects to a WebSocket URL and exposes incoming messages as an async stream.
///
/// Call ``connect(to:)`` to start; cancel the stream task or call ``cancel()`` to close the socket.
public final class WebSocketReceiver: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    deinit {
        cancel()
    }

    /// Closes the WebSocket using `.goingAway`.
    public func cancel() {
        lock.lock()
        let t = task
        task = nil
        lock.unlock()
        t?.cancel(with: .goingAway, reason: nil)
    }

    /// Opens a WebSocket to `url` and yields each received frame until the connection ends or fails.
    ///
    /// The underlying task is cancelled when the stream is terminated (e.g. the consuming `for try await` loop is broken or the task is cancelled).
    public func connect(to url: URL) -> AsyncThrowingStream<WebSocketIncoming, Error> {
        AsyncThrowingStream { continuation in
            let socketTask = self.urlSession.webSocketTask(with: url)

            self.lock.lock()
            self.task = socketTask
            self.lock.unlock()

            socketTask.resume()

            func receiveNext() {
                socketTask.receive { result in
                    switch result {
                    case .success(let message):
                        switch message {
                        case .string(let text):
                            continuation.yield(.text(text))
                        case .data(let data):
                            continuation.yield(.binary(data))
                        @unknown default:
                            break
                        }
                        receiveNext()
                    case .failure(let error):
                        self.clearTaskIfMatches(socketTask)
                        continuation.finish(throwing: error)
                    }
                }
            }

            receiveNext()

            continuation.onTermination = { @Sendable _ in
                socketTask.cancel(with: .goingAway, reason: nil)
                self.clearTaskIfMatches(socketTask)
            }
        }
    }

    private func clearTaskIfMatches(_ socketTask: URLSessionWebSocketTask) {
        lock.lock()
        if task === socketTask {
            task = nil
        }
        lock.unlock()
    }
}

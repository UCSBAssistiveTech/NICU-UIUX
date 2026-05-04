import Foundation

/// A single message from the server.
public enum WebSocketIncoming: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

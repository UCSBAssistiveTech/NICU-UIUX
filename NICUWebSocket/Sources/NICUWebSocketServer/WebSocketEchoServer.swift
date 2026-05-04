import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// A minimal WebSocket **server** (listener) that accepts upgrades and **echoes** each text and binary frame.
///
/// Requires macOS 14 / iOS 17 / tvOS 17 / visionOS 1 or later (SwiftNIO async server APIs).
///
/// - Note: Run ``run()`` from a `Task`. Cancelling that task stops accepting new connections.
@available(macOS 14, iOS 17, tvOS 17, visionOS 1, *)
public struct WebSocketEchoServer: Sendable {
    public var host: String
    public var port: Int
    /// HTTP request path that may upgrade to WebSocket (e.g. `"/"` or `"/ws"`).
    public var path: String
    public var eventLoopGroup: MultiThreadedEventLoopGroup

    private let landingHTML: String

    public init(
        host: String = "127.0.0.1",
        port: Int,
        path: String = "/",
        eventLoopGroup: MultiThreadedEventLoopGroup = .singleton
    ) {
        self.host = host
        self.port = port
        self.path = path.hasPrefix("/") ? path : "/\(path)"
        self.eventLoopGroup = eventLoopGroup
        self.landingHTML = Self.makeLandingPage(port: port, path: self.path)
    }

    public func run() async throws {
        enum UpgradeResult {
            case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
            case notUpgraded(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
        }

        let upgradePath = path

        let channel: NIOAsyncChannel<EventLoopFuture<UpgradeResult>, Never> = try await ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let upgrader = NIOTypedWebSocketServerUpgrader<UpgradeResult>(
                        shouldUpgrade: { (ch, head) in
                            guard head.uri == upgradePath || head.uri.hasPrefix(upgradePath + "?") else {
                                return ch.eventLoop.makeSucceededFuture(nil)
                            }
                            return ch.eventLoop.makeSucceededFuture(HTTPHeaders())
                        },
                        upgradePipelineHandler: { (channel, _) in
                            channel.eventLoop.makeCompletedFuture {
                                let asyncChannel = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(
                                    wrappingChannelSynchronously: channel
                                )
                                return UpgradeResult.websocket(asyncChannel)
                            }
                        }
                    )

                    let serverUpgradeConfiguration = NIOTypedHTTPServerUpgradeConfiguration(
                        upgraders: [upgrader],
                        notUpgradingCompletionHandler: { channel in
                            channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(HTTPByteBufferResponsePartHandler())
                                let asyncChannel = try NIOAsyncChannel<
                                    HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>
                                >(wrappingChannelSynchronously: channel)
                                return UpgradeResult.notUpgraded(asyncChannel)
                            }
                        }
                    )

                    let negotiationResultFuture = try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(
                        configuration: .init(upgradeConfiguration: serverUpgradeConfiguration)
                    )

                    return negotiationResultFuture
                }
            }

        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await upgradeResult in inbound {
                    group.addTask {
                        await Self.handleUpgradeResult(upgradeResult, landingHTML: landingHTML)
                    }
                }
            }
        }
    }

    private static func handleUpgradeResult(
        _ upgradeResult: EventLoopFuture<UpgradeResult>,
        landingHTML: String
    ) async {
        do {
            switch try await upgradeResult.get() {
            case .websocket(let websocketChannel):
                try await handleWebsocketChannel(websocketChannel)
            case .notUpgraded(let httpChannel):
                try await handleHTTPChannel(httpChannel, landingHTML: landingHTML)
            }
        } catch {}
    }

    private static func handleWebsocketChannel(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
        try await channel.executeThenClose { inbound, outbound in
            for try await frame in inbound {
                switch frame.opcode {
                case .text, .binary:
                    let echoed = WebSocketFrame(fin: true, opcode: frame.opcode, data: frame.unmaskedData)
                    try await outbound.write(echoed)
                case .ping:
                    var frameData = frame.data
                    if let maskingKey = frame.maskKey {
                        frameData.webSocketUnmask(maskingKey)
                    }
                    let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
                    try await outbound.write(responseFrame)
                case .connectionClose:
                    var data = frame.unmaskedData
                    let closeDataCode = data.readSlice(length: 2) ?? ByteBuffer()
                    let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
                    try await outbound.write(closeFrame)
                    return
                case .pong, .continuation:
                    break
                default:
                    return
                }
            }
        }
    }

    private static func handleHTTPChannel(
        _ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>,
        landingHTML: String
    ) async throws {
        try await channel.executeThenClose { inbound, outbound in
            for try await requestPart in inbound {
                guard case .head(let head) = requestPart else {
                    return
                }

                guard case .GET = head.method else {
                    try await respond405(writer: outbound)
                    return
                }

                var responseBody = ByteBuffer(string: landingHTML)

                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
                headers.add(name: "Content-Length", value: String(responseBody.readableBytes))
                headers.add(name: "Connection", value: "close")
                let responseHead = HTTPResponseHead(
                    version: .init(major: 1, minor: 1),
                    status: .ok,
                    headers: headers
                )

                try await outbound.write(
                    contentsOf: [
                        .head(responseHead),
                        .body(responseBody),
                        .end(nil),
                    ]
                )
            }
        }
    }

    private static func respond405(
        writer: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        var headers = HTTPHeaders()
        headers.add(name: "Connection", value: "close")
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .methodNotAllowed,
            headers: headers
        )

        try await writer.write(
            contentsOf: [
                .head(head),
                .end(nil),
            ]
        )
    }

    private static func makeLandingPage(port: Int, path: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8"><title>NICU WebSocket echo</title></head>
        <body>
        <p>Echo server. Connect a WebSocket client to <code>ws://127.0.0.1:\(port)\(path)</code></p>
        <pre id="log"></pre>
        <script>
          const ws = new WebSocket("ws://127.0.0.1:\(port)\(path)");
          const log = document.getElementById("log");
          ws.onmessage = (e) => { log.textContent += e.data + "\\n"; };
          ws.onopen = () => { ws.send("hello"); };
        </script>
        </body>
        </html>
        """
    }
}

final class HTTPByteBufferResponsePartHandler: ChannelOutboundHandler {
    typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
    typealias OutboundOut = HTTPServerResponsePart

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let part = Self.unwrapOutboundIn(data)
        switch part {
        case .head(let head):
            context.write(Self.wrapOutboundOut(.head(head)), promise: promise)
        case .body(let buffer):
            context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
        case .end(let trailers):
            context.write(Self.wrapOutboundOut(.end(trailers)), promise: promise)
        }
    }
}

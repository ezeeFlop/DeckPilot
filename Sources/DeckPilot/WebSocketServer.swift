import Foundation
import Network

/// Petit serveur WebSocket, limité à la machine locale, par lequel les extensions parlent à l'application.
/// Tout est délivré sur le fil principal.
final class WebSocketServer {
    typealias ConnectionID = Int

    var onMessage: ((ConnectionID, String) -> Void)?
    var onClose: ((ConnectionID) -> Void)?
    private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private var connections: [ConnectionID: NWConnection] = [:]
    private var nextID = 1

    /// Ouvre le serveur sur un port libre de 127.0.0.1 ; `ready` reçoit le port.
    func start(ready: @escaping (UInt16) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            self?.port = port
            ready(port)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    func send(_ text: String, to id: ConnectionID) {
        guard let connection = connections[id] else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func accept(_ connection: NWConnection) {
        let id = nextID
        nextID += 1
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(id)
            default: break
            }
        }
        connection.start(queue: .main)
        receive(on: connection, id: id)
    }

    private func receive(on connection: NWConnection, id: ConnectionID) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self, error == nil else {
                self?.drop(id)
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .close {
                self.drop(id)
                return
            }
            if let content, !content.isEmpty, metadata?.opcode == .text || metadata?.opcode == .binary {
                self.onMessage?(id, String(decoding: content, as: UTF8.self))
            }
            self.receive(on: connection, id: id)
        }
    }

    private func drop(_ id: ConnectionID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.cancel()
        onClose?(id)
    }
}

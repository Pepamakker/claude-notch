import Foundation
import Network

/// Servidor HTTP minúsculo em 127.0.0.1 (só o próprio Mac enxerga).
/// O hook do Claude Code faz um POST /event com o JSON do evento.
final class EventServer {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    /// Recebe a requisição e devolve o texto da resposta. Chamado na fila do servidor (não é a main).
    var onRequest: ((Request) -> String)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "br.com.bigodinho.apple.server")

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        do {
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: NSLog("Bigodinho: ouvindo em http://127.0.0.1:%d", Int(port))
                case .failed(let e): NSLog("Bigodinho: servidor falhou: %@", "\(e)")
                default: break
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            NSLog("Bigodinho: não consegui abrir a porta %d: %@", Int(port), "\(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        var buffer = Data()
        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
                guard let self = self else { conn.cancel(); return }
                if let d = data { buffer.append(d) }
                if let req = EventServer.parse(buffer) {
                    let body = self.onRequest?(req) ?? "ok"
                    self.respond(conn, body: body)
                } else if isComplete || error != nil || buffer.count > (1 << 20) {
                    conn.cancel()
                } else {
                    receive()
                }
            }
        }
        conn.start(queue: queue)
        receive()
    }

    private func respond(_ conn: NWConnection, body: String) {
        let data = Data(body.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(data)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Devolve nil enquanto a requisição ainda não chegou inteira.
    private static func parse(_ buf: Data) -> Request? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headData = buf.subdata(in: buf.startIndex..<sep.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let i = line.firstIndex(of: ":") else { continue }
            let k = line[..<i].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            headers[k] = v
        }
        let len = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard buf.endIndex - bodyStart >= len else { return nil }
        let body = buf.subdata(in: bodyStart..<(bodyStart + len))
        return Request(method: String(first[0]), path: String(first[1]), headers: headers, body: body)
    }
}

import Foundation
import Network

public final class LoopbackHTTPServer: @unchecked Sendable {
    public private(set) var port: UInt16?
    public let token: String
    private let router: LectureAPIRouter
    private let queue = DispatchQueue(label: "com.jiyuanyi.Lecture.HTTP")
    private var listener: NWListener?

    public init(routerFactory: (String) -> LectureAPIRouter) {
        token = Self.makeToken()
        router = routerFactory(token)
    }

    public func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<UInt16>(continuation)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else { gate.resume(throwing: ServerError.noPort); return }
                    self?.port = port; gate.resume(returning: port)
                case .failed(let error): gate.resume(throwing: error)
                case .cancelled: gate.resume(throwing: ServerError.cancelled)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() { listener?.cancel(); listener = nil; port = nil }

    public func browserURL() -> URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/?token=\(token)")
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                Task {
                    let response = await self.router.handle(request)
                    let payload = Self.serialize(response)
                    connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if isComplete || error != nil || buffer.count > 1_048_576 {
                connection.cancel()
            } else {
                self.receive(on: connection, accumulated: buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator), let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let firstParts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard firstParts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        let components = URLComponents(string: firstParts[1])
        var query: [String: String] = [:]
        components?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        return HTTPRequest(method: firstParts[0], path: components?.path ?? firstParts[1], query: query, headers: headers, body: body)
    }

    private static func serialize(_ response: HTTPResponse) -> Data {
        let reason: String = [200: "OK", 201: "Created", 206: "Partial Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict", 416: "Range Not Satisfiable", 500: "Internal Server Error"][response.status] ?? "OK"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        headers["X-Content-Type-Options"] = "nosniff"
        headers["X-Frame-Options"] = "DENY"
        headers["Referrer-Policy"] = "no-referrer"
        headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        var text = "HTTP/1.1 \(response.status) \(reason)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) { text += "\(key): \(value)\r\n" }
        text += "\r\n"
        var data = Data(text.utf8); data.append(response.body); return data
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess { return UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private enum ServerError: Error { case noPort, cancelled }

private final class ContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func resume(returning value: Value) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock(); defer { lock.unlock() }
        let value = continuation; continuation = nil; return value
    }
}

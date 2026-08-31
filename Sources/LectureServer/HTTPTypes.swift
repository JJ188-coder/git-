import Foundation

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method.uppercased()
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200, encoder: JSONEncoder = LectureJSON.encoder) -> HTTPResponse {
        do {
            return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: try encoder.encode(value))
        } catch {
            return HTTPResponse.jsonError(status: 500, message: "无法编码响应")
        }
    }

    public static func jsonError(status: Int, message: String) -> HTTPResponse {
        struct Failure: Encodable { let error: String }
        let data = (try? LectureJSON.encoder.encode(Failure(error: message))) ?? Data("{\"error\":\"请求失败\"}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }
}

public enum LectureJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

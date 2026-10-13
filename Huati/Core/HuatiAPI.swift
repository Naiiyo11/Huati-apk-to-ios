import Foundation
import CommonCrypto
import Security

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct HuatiAPI {
    static let host = "run.ecust.edu.cn"
    let headers: [String: String]
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    init(config: JSON) throws {
        guard config.text("host") == Self.host else { throw AppError("请先登录或导入有效会话") }
        headers = try Self.clean(config.object("headers"))
    }
    private init(headers: [String: String]) { self.headers = headers }
    static func clean(_ input: JSON) throws -> [String: String] {
        var result: [String: String] = [:]
        for (key, raw) in input {
            let lower = key.lowercased()
            guard ["x-session-id", "authorization", "user-agent", "referer"].contains(lower) else { continue }
            guard let value = raw as? String, value.utf8.count <= 8192, !value.contains("\r"), !value.contains("\n") else { throw AppError("会话文件格式无效") }
            if !value.isEmpty { result[lower] = value }
        }
        guard let session = result["x-session-id"], !session.isEmpty, session != "1111" else { throw AppError("会话缺少有效登录信息") }
        return result
    }
    static func login(_ path: String, body: JSON) async throws -> JSON {
        guard ["/xcxapi/sendSMS/", "/xcxapi/login/", "/xcxapi/userLogin/"].contains(path) else { throw AppError("登录路径无效") }
        return try await HuatiAPI(headers: ["X-Session-ID": "1111"]).request(path, body: body)
    }
    func request(_ path: String, body: JSON? = nil) async throws -> JSON {
        guard (path.hasPrefix("/xcxapi/") || path.hasPrefix("/xcxtapi/")), !path.contains("#"),
              let url = URL(string: "https://" + Self.host + path), url.host == Self.host else { throw AppError("请求路径无效") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError("服务器响应无效") }
        if [401, 403].contains(http.statusCode) { throw AppError("登录已失效，请重新登录") }
        guard (200..<300).contains(http.statusCode) else { throw AppError("服务器返回 \(http.statusCode)，请查询记录状态") }
        guard data.count <= 2 * 1024 * 1024, let value = try JSONSerialization.jsonObject(with: data) as? JSON else { throw AppError("响应格式无效或过大") }
        return value
    }
    static func success(_ result: JSON) throws -> Any {
        if result.number("code", -1) == -2 { throw AppError("登录会话已失效，请重新登录") }
        guard result.number("code", -1) == 1, let data = result["data"] else { throw AppError(result.text("message", result.text("msg", "请求未成功"))) }
        return data
    }
    func value(_ path: String, body: JSON? = nil) async throws -> Any { try Self.success(await request(path, body: body)) }
    static func encrypt(_ value: JSON, iv supplied: Data? = nil) throws -> String {
        let clear = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        let key = Data("A7fK92LmXyQw8vRp".utf8)
        var iv = supplied ?? Data(count: kCCBlockSizeAES128)
        if supplied == nil {
            guard iv.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, $0.baseAddress!) }) == errSecSuccess else { throw AppError("随机加密参数生成失败") }
        }
        guard iv.count == kCCBlockSizeAES128 else { throw AppError("加密参数无效") }
        let capacity = clear.count + kCCBlockSizeAES128
        var output = Data(count: capacity), written = 0
        let status = output.withUnsafeMutableBytes { out in
            clear.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count, ivBytes.baseAddress, input.baseAddress, clear.count, out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw AppError("提交数据加密失败") }
        output.count = written
        return iv.base64EncodedString() + ":" + output.base64EncodedString()
    }
}

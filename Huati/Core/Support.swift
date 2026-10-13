import Foundation
import JavaScriptCore

typealias JSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func text(_ key: String, _ fallback: String = "") -> String {
        guard let value = self[key], !(value is NSNull) else { return fallback }
        return value as? String ?? String(describing: value)
    }
    func number(_ key: String, _ fallback: Double = 0) -> Double {
        (self[key] as? NSNumber)?.doubleValue ?? Double(text(key)) ?? fallback
    }
    func flag(_ key: String) -> Bool { (self[key] as? Bool) ?? false }
    func object(_ key: String) -> JSON { self[key] as? JSON ?? [:] }
    func objects(_ key: String) -> [JSON] { self[key] as? [JSON] ?? [] }
}

struct AppError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum Clock {
    static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded(.down) }
    static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
    static func label(_ ms: Double, precise: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = precise ? "MM-dd HH:mm:ss.SSS" : "MM-dd HH:mm:ss"
        return formatter.string(from: date(ms))
    }
    static func duration(_ ms: Double) -> String {
        let value = max(0, Int(ms))
        return String(format: "%02d:%02d.%03d", value / 60000, value / 1000 % 60, value % 1000)
    }
}

@MainActor final class CoreBridge {
    private let context: JSContext
    let map: JSON
    let graph: JSON
    var boundary: [[Double]] { map["boundary"] as? [[Double]] ?? [] }

    init() throws {
        guard let context = JSContext(),
              let scriptURL = Bundle.main.url(forResource: "run-core", withExtension: "js", subdirectory: "Resources/Core"),
              let mapURL = Bundle.main.url(forResource: "campus-map", withExtension: "json", subdirectory: "Resources"),
              let graphURL = Bundle.main.url(forResource: "campus-roads", withExtension: "json", subdirectory: "Resources") else {
            throw AppError("缺少应用内置资源，请重新安装")
        }
        self.context = context
        map = try JSONSerialization.jsonObject(with: Data(contentsOf: mapURL)) as? JSON ?? [:]
        graph = try JSONSerialization.jsonObject(with: Data(contentsOf: graphURL)) as? JSON ?? [:]
        context.evaluateScript(try String(contentsOf: scriptURL, encoding: .utf8))
        guard context.exception == nil, context.objectForKeyedSubscript("dispatchCore")?.isObject == true else {
            throw AppError("本地规则加载失败")
        }
    }

    func call(_ name: String, _ args: [Any] = []) throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed])
        guard let text = String(data: data, encoding: .utf8),
              let output = context.objectForKeyedSubscript("dispatchCore")?.call(withArguments: [name, text])?.toString(),
              let raw = output.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: raw) as? JSON else { throw AppError("本地计算失败") }
        guard result.flag("ok") else { throw AppError(result.text("error", "本地计算失败")) }
        return result["value"] ?? NSNull()
    }
    func object(_ name: String, _ args: [Any] = []) throws -> JSON { try call(name, args) as? JSON ?? [:] }
    func number(_ name: String, _ args: [Any] = []) throws -> Double { (try call(name, args) as? NSNumber)?.doubleValue ?? 0 }
    func flag(_ name: String, _ args: [Any] = []) throws -> Bool { try call(name, args) as? Bool ?? false }
    func plan(_ preview: JSON, metres: Int, scheduled: Bool, roads: Bool) throws -> JSON {
        if roads { return try object("road", [preview, metres, scheduled, graph, boundary, UInt32.random(in: 1...UInt32.max)]) }
        return try object("basic", [preview, metres, scheduled])
    }
}

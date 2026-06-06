import Foundation

/// 从松散的 JSON 字典中按路径读取值的小工具，容忍字段缺失/类型差异。
struct JSONDigger {
    let root: [String: Any]

    init?(_ data: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        self.root = obj
    }

    init(_ dict: [String: Any]) {
        self.root = dict
    }

    func dict(_ key: String) -> JSONDigger? {
        guard let value = root[key] as? [String: Any] else { return nil }
        return JSONDigger(value)
    }

    /// 容忍数字以 Number 或 String 形式出现。
    func double(_ key: String) -> Double? {
        if let n = root[key] as? Double { return n }
        if let n = root[key] as? Int { return Double(n) }
        if let s = root[key] as? String { return Double(s) }
        if let n = root[key] as? NSNumber { return n.doubleValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = root[key] as? Int { return n }
        if let n = root[key] as? Double { return Int(n) }
        if let s = root[key] as? String { return Int(s) }
        return nil
    }

    func string(_ key: String) -> String? {
        if let s = root[key] as? String { return s }
        if let n = root[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        root[key] as? Bool
    }
}

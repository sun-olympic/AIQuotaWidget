import Foundation
import SQLite3

/// 从本地 Cursor `state.vscdb` 只读取出的凭证。令牌仅驻内存，绝不落盘。
struct CursorCredentials: Equatable {
    var accessToken: String
    var refreshToken: String?
    var cachedEmail: String?
    var membershipType: String?
}

enum CredentialError: Error, LocalizedError {
    case databaseNotFound
    case openFailed
    case accessTokenMissing

    var errorDescription: String? {
        switch self {
        case .databaseNotFound: return "Cursor state database not found"
        case .openFailed: return "Failed to open Cursor state database (read-only)"
        case .accessTokenMissing: return "Access token not found, please sign in to Cursor"
        }
    }
}

/// 以只读 `mode=ro&immutable=1` 打开 `state.vscdb`，读取 cursorAuth 相关键值。
/// MUST NOT 修改文件、MUST NOT 触发 Keychain 弹窗、MUST NOT 依赖浏览器 Cookie。
struct CredentialStore {

    private let dbURL: URL

    init(dbURL: URL = LocalPaths.stateDBURL) {
        self.dbURL = dbURL
    }

    func load() throws -> CursorCredentials {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw CredentialError.databaseNotFound
        }

        var db: OpaquePointer?
        // 只读、不可变方式打开，避免 -wal/-shm 写入与锁竞争。
        let uri = "file:\(dbURL.path)?mode=ro&immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db = db else {
            if let db = db { sqlite3_close(db) }
            throw CredentialError.openFailed
        }
        defer { sqlite3_close(db) }

        let access = readValue(db: db, key: CredentialKeys.accessToken)
        guard let accessToken = access, !accessToken.isEmpty else {
            throw CredentialError.accessTokenMissing
        }

        return CursorCredentials(
            accessToken: accessToken,
            refreshToken: nonEmpty(readValue(db: db, key: CredentialKeys.refreshToken)),
            cachedEmail: nonEmpty(readValue(db: db, key: CredentialKeys.cachedEmail)),
            membershipType: nonEmpty(readValue(db: db, key: CredentialKeys.membershipType))
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    private func readValue(db: OpaquePointer, key: String) -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT：让 sqlite 复制字符串。
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }
}

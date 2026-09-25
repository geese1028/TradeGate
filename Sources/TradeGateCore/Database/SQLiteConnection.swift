import Foundation
import SQLite3

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case null
}

final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(db)
            throw TradeGateError.sqlite(message)
        }
        handle = db
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 5000;")
        try execute("PRAGMA journal_mode = WAL;")
    }

    deinit {
        sqlite3_close(handle)
        handle = nil
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sqlite error \(rc)"
            sqlite3_free(error)
            throw TradeGateError.sqlite(message)
        }
    }

    func query(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        _ row: (OpaquePointer) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                try row(statement)
            } else if rc == SQLITE_DONE {
                return
            } else {
                throw TradeGateError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    func run(_ sql: String, bindings: [SQLiteValue]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE else {
            throw TradeGateError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func stringPragma(_ name: String) throws -> String {
        var value = ""
        try query("PRAGMA \(name);") { statement in
            value = columnText(statement, 0) ?? ""
        }
        return value
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            throw TradeGateError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .text(let text):
                rc = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .integer(let number):
                rc = sqlite3_bind_int64(statement, index, number)
            case .null:
                rc = sqlite3_bind_null(statement, index)
            }
            guard rc == SQLITE_OK else {
                throw TradeGateError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}

func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    guard let raw = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: raw)
}

func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int64 {
    sqlite3_column_int64(statement, index)
}

func columnBool(_ statement: OpaquePointer, _ index: Int32) -> Bool {
    columnInt(statement, index) != 0
}

func decimalColumn(_ statement: OpaquePointer, _ index: Int32) throws -> DecimalValue? {
    guard let text = columnText(statement, index) else { return nil }
    return try DecimalValue(parsing: text)
}

func textBinding(_ value: String?) -> SQLiteValue {
    value.map(SQLiteValue.text) ?? .null
}

func intBinding(_ value: Bool) -> SQLiteValue {
    .integer(value ? 1 : 0)
}

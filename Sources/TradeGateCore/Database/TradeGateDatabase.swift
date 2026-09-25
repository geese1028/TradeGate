import Foundation

public final class TradeGateDatabase: PlanStoring, AuditVerifying, @unchecked Sendable {
    public let path: String
    let connection: SQLiteConnection
    let lock = NSLock()

    public init(path: String) throws {
        self.path = path
        self.connection = try SQLiteConnection(path: path)
        try migrate()
    }

    public func status() throws -> StoreStatus {
        try locked {
            let version = try schemaVersion()
            let foreignKeys = try connection.stringPragma("foreign_keys") == "1"
            let journal = try connection.journalMode()
            return StoreStatus(
                schemaVersion: version,
                foreignKeysEnabled: foreignKeys,
                journalMode: journal
            )
        }
    }

    public func settings() throws -> TradeGateSettings {
        try locked {
            try readSettings()
        }
    }

    public func updateSettings(_ settings: TradeGateSettings) throws {
        guard UnlockDuration(rawValue: settings.unlockDurationSeconds) != nil else {
            throw TradeGateError.invalidSettings("unlock duration must be 30, 60, 90, 120, or 180")
        }
        guard settings.emergencyCountdownSeconds > 0 else {
            throw TradeGateError.invalidSettings("emergency countdown must be positive")
        }
        try locked {
            try connection.run(
                "UPDATE settings SET value = ? WHERE key = 'unlock_duration_seconds';",
                bindings: [.text(String(settings.unlockDurationSeconds))]
            )
            try connection.run(
                "UPDATE settings SET value = ? WHERE key = 'emergency_countdown_seconds';",
                bindings: [.text(String(settings.emergencyCountdownSeconds))]
            )
            try connection.run(
                "UPDATE settings SET value = ? WHERE key = 'start_at_login';",
                bindings: [.text(settings.startAtLogin ? "1" : "0")]
            )
            try connection.run(
                "UPDATE settings SET value = ? WHERE key = 'notifications_enabled';",
                bindings: [.text(settings.notificationsEnabled ? "1" : "0")]
            )
            if let location = settings.databaseLocation {
                try connection.run(
                    """
                    INSERT INTO settings (key, value) VALUES ('database_location', ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                    """,
                    bindings: [.text(location)]
                )
            }
        }
    }

    func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try connection.execute("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try connection.execute("COMMIT;")
            return value
        } catch {
            try? connection.execute("ROLLBACK;")
            throw error
        }
    }

    private func migrate() throws {
        try locked {
            let version = try schemaVersion()
            if version == Schema.version {
                return
            }
            if version != 0 {
                throw TradeGateError.invalidState("unknown schema version \(version)")
            }
            try transaction {
                try connection.execute(Schema.migration)
                try connection.run(
                    "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(Int64(Schema.version)), .text(Timestamp.string(from: Date()))]
                )
            }
        }
    }

    func schemaVersion() throws -> Int {
        var exists = false
        try connection.query(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations';"
        ) { _ in
            exists = true
        }
        guard exists else { return 0 }
        var version = 0
        try connection.query("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;") { statement in
            version = Int(columnInt(statement, 0))
        }
        return version
    }

    func readSettings() throws -> TradeGateSettings {
        var values: [String: String] = [:]
        try connection.query("SELECT key, value FROM settings;") { statement in
            if let key = columnText(statement, 0), let value = columnText(statement, 1) {
                values[key] = value
            }
        }
        return TradeGateSettings(
            unlockDurationSeconds: Int(values["unlock_duration_seconds"] ?? "120") ?? 120,
            emergencyCountdownSeconds: Int(values["emergency_countdown_seconds"] ?? "20") ?? 20,
            startAtLogin: values["start_at_login"] == "1",
            notificationsEnabled: values["notifications_enabled"] != "0",
            databaseLocation: values["database_location"]
        )
    }
}

extension SQLiteConnection {
    func journalMode() throws -> String {
        var mode = ""
        try query("PRAGMA journal_mode;") { statement in
            mode = columnText(statement, 0) ?? ""
        }
        return mode
    }
}

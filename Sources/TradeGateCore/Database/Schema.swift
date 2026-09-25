enum Schema {
    static let version = 1

    static let migration = """
    CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        applied_at TEXT NOT NULL
    );

    CREATE TABLE managed_devices (
        id TEXT PRIMARY KEY NOT NULL,
        serial_number TEXT NOT NULL UNIQUE,
        product_name TEXT NOT NULL,
        firmware_version TEXT NOT NULL,
        managed_fido2 INTEGER NOT NULL CHECK (managed_fido2 IN (0, 1)),
        managed_u2f INTEGER NOT NULL CHECK (managed_u2f IN (0, 1)),
        created_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1))
    );

    CREATE TABLE trade_plans (
        id TEXT PRIMARY KEY NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        application TEXT NOT NULL,
        raw_symbol TEXT NOT NULL,
        normalized_symbol TEXT NOT NULL,
        plan_type TEXT NOT NULL,
        status TEXT NOT NULL,
        timeframe TEXT,
        major_pullback TEXT,
        medium_pullback TEXT,
        small_divergence_timeframe TEXT,
        small_divergence_custom TEXT,
        signal_status TEXT,
        signal_timeframe TEXT,
        stop_price TEXT,
        position_mode TEXT,
        position_value TEXT,
        secondary_state TEXT,
        exit_strategy TEXT,
        custom_exit_strategy TEXT,
        planned_exit_price TEXT,
        exit_position_mode TEXT,
        exit_position_value TEXT
    );

    CREATE TABLE plan_revisions (
        id TEXT PRIMARY KEY NOT NULL,
        plan_id TEXT NOT NULL REFERENCES trade_plans(id),
        revision_number INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        UNIQUE (plan_id, revision_number)
    );

    CREATE TABLE executions (
        id TEXT PRIMARY KEY NOT NULL,
        plan_id TEXT REFERENCES trade_plans(id),
        executed_at TEXT NOT NULL,
        execution_price TEXT NOT NULL,
        execution_position_mode TEXT NOT NULL,
        execution_position_value TEXT,
        confirmed_by_user INTEGER NOT NULL CHECK (confirmed_by_user IN (0, 1)),
        review_required INTEGER NOT NULL CHECK (review_required IN (0, 1))
    );

    CREATE TABLE emergency_overrides (
        id TEXT PRIMARY KEY NOT NULL,
        application TEXT NOT NULL,
        raw_symbol TEXT NOT NULL,
        normalized_symbol TEXT NOT NULL,
        reason_category TEXT NOT NULL,
        reason_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        review_required INTEGER NOT NULL CHECK (review_required IN (0, 1))
    );

    CREATE TABLE reviews (
        id TEXT PRIMARY KEY NOT NULL,
        execution_id TEXT REFERENCES executions(id),
        emergency_override_id TEXT REFERENCES emergency_overrides(id),
        created_at TEXT NOT NULL,
        completed_at TEXT,
        actual_json TEXT NOT NULL,
        plan_adherence TEXT,
        deviation_reason TEXT,
        notes TEXT,
        CHECK (
            (execution_id IS NOT NULL AND emergency_override_id IS NULL)
            OR (execution_id IS NULL AND emergency_override_id IS NOT NULL)
        )
    );

    CREATE TABLE unlock_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        application TEXT NOT NULL,
        symbol TEXT NOT NULL,
        plan_id TEXT REFERENCES trade_plans(id),
        requested_at TEXT NOT NULL,
        approved_at TEXT,
        unlocked_at TEXT,
        locked_at TEXT,
        duration_seconds INTEGER,
        result TEXT NOT NULL
    );

    CREATE TABLE audit_events (
        id TEXT PRIMARY KEY NOT NULL,
        timestamp TEXT NOT NULL,
        event_type TEXT NOT NULL,
        application TEXT,
        symbol TEXT,
        plan_id TEXT,
        execution_id TEXT,
        review_id TEXT,
        unlock_session_id TEXT,
        metadata_json TEXT NOT NULL,
        prev_hash TEXT NOT NULL,
        event_hash TEXT NOT NULL UNIQUE
    );

    CREATE TABLE settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
    );

    CREATE INDEX idx_trade_plans_symbol ON trade_plans(normalized_symbol);
    CREATE INDEX idx_plan_revisions_plan ON plan_revisions(plan_id, revision_number);
    CREATE INDEX idx_executions_plan ON executions(plan_id);
    CREATE INDEX idx_reviews_execution ON reviews(execution_id);
    CREATE INDEX idx_reviews_emergency ON reviews(emergency_override_id);
    CREATE INDEX idx_audit_events_timestamp ON audit_events(timestamp);
    CREATE INDEX idx_audit_events_type ON audit_events(event_type);

    CREATE TRIGGER audit_events_no_update
    BEFORE UPDATE ON audit_events
    BEGIN
        SELECT RAISE(ABORT, 'audit_events is append-only');
    END;

    CREATE TRIGGER audit_events_no_delete
    BEFORE DELETE ON audit_events
    BEGIN
        SELECT RAISE(ABORT, 'audit_events is append-only');
    END;

    INSERT INTO settings (key, value) VALUES
        ('unlock_duration_seconds', '120'),
        ('emergency_countdown_seconds', '20'),
        ('start_at_login', '0'),
        ('notifications_enabled', '1');
    """
}

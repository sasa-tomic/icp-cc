-- ICPay payment integration: purchases ledger (SQLite variant).
--
-- Records a successful ICPay payment that grants an account entitlement to a
-- paid script's bundle. The `UNIQUE(account_id, script_id)` constraint makes
-- ICPay webhook redelivery idempotent: the repository issues an
-- `INSERT ... ON CONFLICT(account_id, script_id) DO NOTHING` so a duplicate
-- delivery from ICPay is a no-op rather than an error.
--
-- See 006_create_purchases.sql for the Postgres twin and the full rationale.

CREATE TABLE IF NOT EXISTS purchases (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    script_id TEXT NOT NULL,
    icpay_intent_id TEXT,
    icpay_transaction_id TEXT,
    usd_amount REAL NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL,
    paid_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (account_id, script_id)
);

CREATE INDEX IF NOT EXISTS idx_purchases_account ON purchases(account_id);
CREATE INDEX IF NOT EXISTS idx_purchases_script ON purchases(script_id);

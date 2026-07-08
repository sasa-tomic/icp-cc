-- ICPay payment integration: purchases ledger (Postgres variant).
--
-- Records a successful ICPay payment that grants an account entitlement to a
-- paid script's bundle. The `UNIQUE(account_id, script_id)` constraint makes
-- ICPay webhook redelivery idempotent: a second `INSERT` for the same
-- (account, script) pair is rejected by the constraint, and the repository
-- issues an `ON CONFLICT (account_id, script_id) DO NOTHING` so the duplicate
-- is a no-op rather than an error.
--
-- One row = one entitlement. An account that re-buys the same script (after a
-- refund flow deletes the row) simply gets a new row with a fresh
-- `icpay_intent_id` / `icpay_transaction_id`.

CREATE TABLE IF NOT EXISTS purchases (
    id VARCHAR(64) PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    script_id VARCHAR(64) NOT NULL,
    icpay_intent_id VARCHAR(255),
    icpay_transaction_id VARCHAR(255),
    usd_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    status VARCHAR(32) NOT NULL,
    paid_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (account_id, script_id)
);

CREATE INDEX IF NOT EXISTS idx_purchases_account ON purchases(account_id);
CREATE INDEX IF NOT EXISTS idx_purchases_script ON purchases(script_id);

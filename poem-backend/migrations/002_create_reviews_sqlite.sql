-- Create reviews table (SQLite)
CREATE TABLE IF NOT EXISTS reviews (
    id TEXT PRIMARY KEY,
    script_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_reviews_script_id ON reviews(script_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON reviews(rating);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON reviews(created_at DESC);

-- Trigger to update updated_at timestamp
CREATE TRIGGER IF NOT EXISTS update_reviews_updated_at
    AFTER UPDATE ON reviews
    FOR EACH ROW
BEGIN
    UPDATE reviews SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- Triggers to update script rating and review count
CREATE TRIGGER IF NOT EXISTS update_script_rating_on_insert
    AFTER INSERT ON reviews
    FOR EACH ROW
BEGIN
    UPDATE scripts
    SET
        rating = COALESCE((SELECT AVG(rating) FROM reviews WHERE script_id = NEW.script_id), 0.0),
        review_count = (SELECT COUNT(*) FROM reviews WHERE script_id = NEW.script_id)
    WHERE id = NEW.script_id;
END;

CREATE TRIGGER IF NOT EXISTS update_script_rating_on_update
    AFTER UPDATE ON reviews
    FOR EACH ROW
BEGIN
    UPDATE scripts
    SET
        rating = COALESCE((SELECT AVG(rating) FROM reviews WHERE script_id = NEW.script_id), 0.0),
        review_count = (SELECT COUNT(*) FROM reviews WHERE script_id = NEW.script_id)
    WHERE id = NEW.script_id;
END;

CREATE TRIGGER IF NOT EXISTS update_script_rating_on_delete
    AFTER DELETE ON reviews
    FOR EACH ROW
BEGIN
    UPDATE scripts
    SET
        rating = COALESCE((SELECT AVG(rating) FROM reviews WHERE script_id = OLD.script_id), 0.0),
        review_count = (SELECT COUNT(*) FROM reviews WHERE script_id = OLD.script_id)
    WHERE id = OLD.script_id;
END;
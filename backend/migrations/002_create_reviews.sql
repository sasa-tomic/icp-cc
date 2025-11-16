-- Create reviews table
CREATE TABLE IF NOT EXISTS reviews (
    id VARCHAR(64) PRIMARY KEY,
    script_id VARCHAR(64) NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_reviews_script_id ON reviews(script_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON reviews(rating);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON reviews(created_at DESC);

-- Trigger to update updated_at timestamp
CREATE TRIGGER update_reviews_updated_at
    BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger to update script rating and review count when a review is added or updated
CREATE OR REPLACE FUNCTION update_script_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE scripts
    SET
        rating = COALESCE(
            (SELECT AVG(rating) FROM reviews WHERE script_id = NEW.script_id),
            0
        ),
        review_count = (
            SELECT COUNT(*) FROM reviews WHERE script_id = NEW.script_id
        )
    WHERE id = NEW.script_id;

    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_script_rating_on_insert
    AFTER INSERT ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_script_rating();

CREATE TRIGGER update_script_rating_on_update
    AFTER UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_script_rating();

CREATE TRIGGER update_script_rating_on_delete
    AFTER DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_script_rating();
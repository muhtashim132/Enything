-- =============================================================================
-- Migration: 100x Pixel Overloading Fortress
-- Description:
--   1. Protects against "Pixel Overloading" / Payload Bombing.
--   2. Enforces maximum length constraints on unbound text fields.
--   3. Purely additive constraint checks.
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_comment_length') THEN
        ALTER TABLE reviews ADD CONSTRAINT reviews_comment_length CHECK (char_length(comment) <= 1000);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_rejection_msg_length') THEN
        ALTER TABLE orders ADD CONSTRAINT orders_rejection_msg_length CHECK (char_length(rejection_message) <= 1000);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_cancelled_rsn_length') THEN
        ALTER TABLE orders ADD CONSTRAINT orders_cancelled_rsn_length CHECK (char_length(cancelled_reason) <= 1000);
    END IF;
END $$;


-- =============================================================================
-- Migration: 100x Pixel Overloading Fortress
-- Description:
--   1. Protects against "Pixel Overloading" / Payload Bombing.
--   2. Enforces maximum length constraints on unbound text fields.
--   3. Purely additive constraint checks.
-- =============================================================================

ALTER TABLE reviews ADD CONSTRAINT reviews_comment_length CHECK (char_length(comment) <= 1000);
ALTER TABLE orders ADD CONSTRAINT orders_rejection_msg_length CHECK (char_length(rejection_message) <= 1000);
ALTER TABLE orders ADD CONSTRAINT orders_cancelled_rsn_length CHECK (char_length(cancelled_reason) <= 1000);

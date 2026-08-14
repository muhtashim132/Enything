-- =============================================================================
-- Migration: 20290000000064_allow_verification_failed_transition.sql
-- =============================================================================
-- Description:
--   Allows valid state transition to 'verification_failed' when a medical/pharmacy
--   seller rejects an order due to invalid/unreadable/expired prescription.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_order_status_transitions()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow initial state on INSERT
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Only validate if status is actually changing
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    CASE OLD.status
        WHEN 'awaiting_payment' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'cancelled', 'pending', 'confirmed', 'payment_failed', 'verification_failed', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'awaiting_acceptance' THEN
            IF NEW.status NOT IN ('pending', 'awaiting_payment', 'confirmed', 'seller_rejected', 'verification_failed', 'cancelled', 'timeout') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'pending' THEN
            IF NEW.status NOT IN ('confirmed', 'seller_rejected', 'verification_failed', 'cancelled', 'timeout', 'awaiting_acceptance', 'awaiting_payment') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'confirmed' THEN
            IF NEW.status NOT IN ('preparing', 'ready_for_pickup', 'cancelled', 'seller_rejected', 'verification_failed') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'preparing' THEN
            IF NEW.status NOT IN ('ready_for_pickup', 'cancelled', 'seller_rejected', 'verification_failed') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'ready_for_pickup' THEN
            IF NEW.status NOT IN ('picked_up', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'picked_up' THEN
            IF NEW.status NOT IN ('out_for_delivery', 'delivered', 'cancelled', 'shop_dispute') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'out_for_delivery' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'shop_dispute' THEN
            IF NEW.status NOT IN ('cancelled', 'delivered', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        -- Terminal states cannot be changed
        WHEN 'delivered', 'cancelled', 'seller_rejected', 'verification_failed',
             'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider',
             'partner_rejected', 'rider_rejected' THEN
            RAISE EXCEPTION 'Cannot change status of a terminal order (%) to %', OLD.status, NEW.status;

        ELSE
            RAISE EXCEPTION 'Unknown order status: %', OLD.status;
    END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

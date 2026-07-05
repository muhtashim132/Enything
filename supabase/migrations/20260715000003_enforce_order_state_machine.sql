-- 20260715000003_enforce_order_state_machine.sql
-- 100x Architecture Hardening: Enforce strict order state transitions at the database level.
-- This prevents API bypasses, skipped states (e.g. going from awaiting_acceptance straight to delivered),
-- and geofence-related premature updates by forcing a strict state machine.

CREATE OR REPLACE FUNCTION validate_order_status_transition()
RETURNS TRIGGER AS $$
BEGIN
    -- No restrictions on initial insertion (usually handled by RLS)
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Only validate if status is actually changing
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    -- Define strict allowable transitions.
    -- (Admin overriding might need a bypass flag in a real-world scenario, but this sets standard flow)
    CASE OLD.status
        WHEN 'awaiting_payment' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'cancelled', 'pending') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'awaiting_acceptance' THEN
            IF NEW.status NOT IN ('pending', 'awaiting_payment', 'confirmed', 'seller_rejected', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'pending' THEN
            IF NEW.status NOT IN ('confirmed', 'seller_rejected', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'confirmed' THEN
            IF NEW.status NOT IN ('preparing', 'ready_for_pickup', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'preparing' THEN
            IF NEW.status NOT IN ('ready_for_pickup', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'ready_for_pickup' THEN
            IF NEW.status NOT IN ('picked_up', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'picked_up' THEN
            IF NEW.status NOT IN ('out_for_delivery', 'delivered') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        WHEN 'out_for_delivery' THEN
            IF NEW.status NOT IN ('delivered') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;
            
        -- Terminal states cannot be changed
        WHEN 'delivered', 'cancelled', 'seller_rejected' THEN
            RAISE EXCEPTION 'Cannot change status of a terminal order (%) to %', OLD.status, NEW.status;
            
        ELSE
            RAISE EXCEPTION 'Unknown order status: %', OLD.status;
    END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists (re-runnable script)
DROP TRIGGER IF EXISTS tr_validate_order_status ON public.orders;

-- Attach the trigger
CREATE TRIGGER tr_validate_order_status
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION validate_order_status_transition();

-- Dual-Acceptance integrity check removed to support asynchronous rider/seller acceptance
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS chk_orders_dual_acceptance;

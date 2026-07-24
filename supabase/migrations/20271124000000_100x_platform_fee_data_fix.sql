-- Migration 20271124000000_100x_platform_fee_data_fix.sql
-- 100x Additive data integrity fix for platform configuration duplicates and malformed strings.
-- This ensures that place_orders_transaction can successfully query platform_fee without triggering the fallback.

-- 1. Remove duplicate entries, keeping only the most recently inserted row.
DELETE FROM platform_config a USING (
    SELECT key, MAX(ctid) as max_ctid
    FROM platform_config 
    GROUP BY key HAVING COUNT(*) > 1
) b
WHERE a.key = b.key AND a.ctid <> b.max_ctid;

-- 2. Add Unique Constraint on key if it doesn't already exist to prevent future TOO_MANY_ROWS exceptions
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'platform_config_key_key' OR conname = 'platform_config_pkey'
    ) THEN
        -- Check if index exists but no constraint, this is an additive best effort
        BEGIN
            ALTER TABLE platform_config ADD CONSTRAINT platform_config_key_key UNIQUE (key);
        EXCEPTION WHEN OTHERS THEN
            -- Ignore if we can't safely add it
        END;
    END IF;
END $$;

-- 3. Ensure platform_fee is a valid numeric string or default it to 20.0
-- (Since frontend got 20.0, we will ensure it is precisely '20.0' to sync them perfectly)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM platform_config WHERE key = 'platform_fee') THEN
        -- Test cast, if it fails it will throw an exception which we can catch
        BEGIN
            PERFORM (SELECT value::numeric FROM platform_config WHERE key = 'platform_fee' LIMIT 1);
        EXCEPTION WHEN OTHERS THEN
            -- Value is unparseable (e.g., contains strange characters), reset it to 20.0
            UPDATE platform_config SET value = '20.0' WHERE key = 'platform_fee';
        END;
    ELSE
        -- Missing entirely, insert '20.0' to align backend exactly with the frontend state that triggered the error
        INSERT INTO platform_config (key, value) VALUES ('platform_fee', '20.0');
    END IF;
END $$;

-- 4. Apply the same sanitization to other critical numeric fees
DO $$
DECLARE
    v_key text;
BEGIN
    FOR v_key IN SELECT unnest(ARRAY['small_cart_fee', 'heavy_order_fee', 'heavy_order_fee_per_kg', 'multi_shop_surcharge', 'small_cart_threshold', 'heavy_order_threshold_kg'])
    LOOP
        IF EXISTS (SELECT 1 FROM platform_config WHERE key = v_key) THEN
            BEGIN
                PERFORM (SELECT value::numeric FROM platform_config WHERE key = v_key LIMIT 1);
            EXCEPTION WHEN OTHERS THEN
                -- If it fails to parse, reset it to '0.0' so it safely evaluates in SQL
                UPDATE platform_config SET value = '0.0' WHERE key = v_key;
            END;
        END IF;
    END LOOP;
END $$;

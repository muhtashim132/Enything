-- =============================================================================
-- Migration: 100x Pixel Overloading Core Fortress (Phase 2)
-- Description:
--   Adds strict text length boundaries to core table string fields to prevent 
--   Payload Bombing / Pixel Overloading attacks (OOM crashes).
--   All constraints are added as NOT VALID to prevent locking active tables,
--   making this purely additive for new/updated rows.
-- =============================================================================

DO $$
BEGIN
    -- PROFILES TABLE
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_name_len') THEN
        ALTER TABLE profiles ADD CONSTRAINT profiles_name_len CHECK (char_length(name) <= 255) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_full_name_len') THEN
        ALTER TABLE profiles ADD CONSTRAINT profiles_full_name_len CHECK (char_length(full_name) <= 255) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_avatar_url_len') THEN
        ALTER TABLE profiles ADD CONSTRAINT profiles_avatar_url_len CHECK (char_length(avatar_url) <= 2000) NOT VALID;
    END IF;

    -- SHOPS TABLE
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_name_len') THEN
        ALTER TABLE shops ADD CONSTRAINT shops_name_len CHECK (char_length(name) <= 255) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_description_len') THEN
        ALTER TABLE shops ADD CONSTRAINT shops_description_len CHECK (char_length(description) <= 2000) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_address_len') THEN
        ALTER TABLE shops ADD CONSTRAINT shops_address_len CHECK (char_length(address) <= 1000) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_image_url_len') THEN
        ALTER TABLE shops ADD CONSTRAINT shops_image_url_len CHECK (char_length(image_url) <= 2000) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_banner_url_len') THEN
        ALTER TABLE shops ADD CONSTRAINT shops_banner_url_len CHECK (char_length(banner_url) <= 2000) NOT VALID;
    END IF;

    -- PRODUCTS TABLE
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_name_len') THEN
        ALTER TABLE products ADD CONSTRAINT products_name_len CHECK (char_length(name) <= 255) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_description_len') THEN
        ALTER TABLE products ADD CONSTRAINT products_description_len CHECK (char_length(description) <= 2000) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_image_url_len') THEN
        ALTER TABLE products ADD CONSTRAINT products_image_url_len CHECK (char_length(image_url) <= 2000) NOT VALID;
    END IF;

    -- ORDERS TABLE
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_delivery_notes_len') THEN
        ALTER TABLE orders ADD CONSTRAINT orders_delivery_notes_len CHECK (char_length(delivery_notes) <= 1000) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_address_len') THEN
        ALTER TABLE orders ADD CONSTRAINT orders_address_len CHECK (char_length(address) <= 1000) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_address_label_len') THEN
        ALTER TABLE orders ADD CONSTRAINT orders_address_label_len CHECK (char_length(address_label) <= 100) NOT VALID;
    END IF;
END $$;


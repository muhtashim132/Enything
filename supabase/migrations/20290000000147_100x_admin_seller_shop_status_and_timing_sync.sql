-- =============================================================================
-- Migration: 20290000000147_100x_admin_seller_shop_status_and_timing_sync.sql
-- Description: 100x Forensic Parity & Bidirectional Synchronization between
--              Admin Panel and Seller Dashboard for Shop Open/Closed Status
--              (is_accepting_orders / is_open) and Store Operating Timings (open_time, close_time).
--
-- Guarantees:
-- 1. Admin toggling ON/OFF performs the exact same operation as Seller toggling
--    ON/OFF (updates is_accepting_orders, is_open, is_manually_closed, and ensures is_active).
-- 2. Store operating timings can be viewed and edited from both Seller and Admin panels.
-- 3. Trigger trg_sync_shop_hours respects explicit manual toggles while automatically
--    evaluating operating hours during schedule changes (supporting cross-midnight shifts).
-- 4. Provides atomic RPCs: admin_toggle_shop_accepting_orders and admin_update_shop_operating_hours.
-- 5. Updates admin_toggle_active for entity 'shop' to keep is_accepting_orders in sync.
-- 6. Self-contained with safe_cast_time helper and dual-column compatibility
--    (open_time/opening_time, close_time/closing_time, is_accepting_orders/is_open).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 0: Helper safe_cast_time
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.safe_cast_time(t text)
RETURNS time AS $$
BEGIN
    IF t IS NULL OR trim(t) = '' THEN
        RETURN NULL;
    END IF;
    RETURN t::time;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

GRANT EXECUTE ON FUNCTION public.safe_cast_time(text) TO authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Hardened trg_sync_shop_hours with Explicit Toggle Protection
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_sync_shop_hours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now   time;
    v_open  time;
    v_close time;
BEGIN
    v_now   := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;
    v_open  := public.safe_cast_time(COALESCE(NEW.open_time, NEW.opening_time)::text);
    v_close := public.safe_cast_time(COALESCE(NEW.close_time, NEW.closing_time)::text);

    -- Mirror column pairs for seamless compatibility
    IF NEW.open_time IS NOT NULL AND NEW.opening_time IS NULL THEN
        NEW.opening_time := NEW.open_time;
    ELSIF NEW.opening_time IS NOT NULL AND NEW.open_time IS NULL THEN
        NEW.open_time := NEW.opening_time;
    END IF;

    IF NEW.close_time IS NOT NULL AND NEW.closing_time IS NULL THEN
        NEW.closing_time := NEW.close_time;
    ELSIF NEW.closing_time IS NOT NULL AND NEW.close_time IS NULL THEN
        NEW.close_time := NEW.closing_time;
    END IF;

    -- If operating hours are changed, reset manual closure override
    IF (NEW.open_time IS DISTINCT FROM OLD.open_time OR NEW.close_time IS DISTINCT FROM OLD.close_time)
       OR (NEW.opening_time IS DISTINCT FROM OLD.opening_time OR NEW.closing_time IS DISTINCT FROM OLD.closing_time) THEN
        NEW.is_manually_closed := false;
    END IF;

    -- Smart Reset inline: If time is outside the operating hours, reset manual closure flag
    IF NEW.is_manually_closed = true AND v_open IS NOT NULL AND v_close IS NOT NULL THEN
        IF v_open <= v_close THEN
            IF v_now < v_open OR v_now > v_close THEN
                NEW.is_manually_closed := false;
            END IF;
        ELSE
            IF v_now < v_open AND v_now > v_close THEN
                NEW.is_manually_closed := false;
            END IF;
        END IF;
    END IF;

    -- Evaluate is_accepting_orders:
    -- If caller explicitly provided/updated is_accepting_orders, respect it!
    IF NEW.is_accepting_orders IS NOT DISTINCT FROM OLD.is_accepting_orders THEN
        IF NEW.is_active = false THEN
            NEW.is_accepting_orders := false;
        ELSIF v_open IS NOT NULL AND v_close IS NOT NULL THEN
            IF NEW.is_manually_closed = true THEN
                NEW.is_accepting_orders := false;
            ELSE
                IF v_open <= v_close THEN
                    NEW.is_accepting_orders := ( v_now >= v_open AND v_now <= v_close );
                ELSE
                    NEW.is_accepting_orders := ( v_now >= v_open OR  v_now <= v_close );
                END IF;
            END IF;
        END IF;
    END IF;

    -- Sync is_open with is_accepting_orders
    NEW.is_open := NEW.is_accepting_orders;

    RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Atomic RPC admin_toggle_shop_accepting_orders
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_toggle_shop_accepting_orders(
  p_shop_id UUID,
  p_is_open BOOLEAN
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop RECORD;
BEGIN
  -- Strict Authorization Barrier: Admin or Super Admin
  IF NOT (public.is_active_admin(auth.uid()) OR public.is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Access denied: platform admin only';
  END IF;

  -- Update shop status atomically
  -- When opening: is_accepting_orders = true, is_open = true, is_manually_closed = false, is_active = true
  -- When closing: is_accepting_orders = false, is_open = false, is_manually_closed = true
  UPDATE public.shops
  SET 
    is_accepting_orders = p_is_open,
    is_open = p_is_open,
    is_manually_closed = NOT p_is_open,
    is_active = CASE WHEN p_is_open THEN true ELSE is_active END,
    updated_at = NOW()
  WHERE id = p_shop_id
  RETURNING id, name, is_active, is_accepting_orders, is_open, is_manually_closed, open_time, close_time, opening_time, closing_time
  INTO v_shop;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shop with ID % not found', p_shop_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_shop.id,
    'name', v_shop.name,
    'is_active', v_shop.is_active,
    'is_accepting_orders', v_shop.is_accepting_orders,
    'is_open', v_shop.is_open,
    'is_manually_closed', v_shop.is_manually_closed,
    'open_time', COALESCE(v_shop.open_time, v_shop.opening_time),
    'close_time', COALESCE(v_shop.close_time, v_shop.closing_time)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_toggle_shop_accepting_orders(UUID, BOOLEAN) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Atomic RPC admin_update_shop_operating_hours
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_shop_operating_hours(
  p_shop_id UUID,
  p_open_time TEXT,
  p_close_time TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop RECORD;
  v_now TIME;
  v_open TIME;
  v_close TIME;
  v_is_within_hours BOOLEAN;
BEGIN
  -- Strict Authorization Barrier
  IF NOT (public.is_active_admin(auth.uid()) OR public.is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Access denied: platform admin only';
  END IF;

  -- Validate time strings (e.g. '09:00', '21:00')
  BEGIN
    v_open := p_open_time::time;
    v_close := p_close_time::time;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid time format. Expected HH:MI format (e.g. 09:00)';
  END;

  v_now := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;

  -- Determine if current time is within new hours (supporting night shifts)
  IF v_open <= v_close THEN
    v_is_within_hours := (v_now >= v_open AND v_now <= v_close);
  ELSE
    v_is_within_hours := (v_now >= v_open OR v_now <= v_close);
  END IF;

  -- Update hours across both column pairs, reset manual closure, and evaluate status
  UPDATE public.shops
  SET 
    open_time = p_open_time,
    close_time = p_close_time,
    opening_time = p_open_time,
    closing_time = p_close_time,
    is_manually_closed = false,
    is_accepting_orders = CASE 
      WHEN is_active = false THEN false
      ELSE v_is_within_hours
    END,
    is_open = CASE 
      WHEN is_active = false THEN false
      ELSE v_is_within_hours
    END,
    updated_at = NOW()
  WHERE id = p_shop_id
  RETURNING id, name, is_active, is_accepting_orders, is_open, is_manually_closed, open_time, close_time, opening_time, closing_time
  INTO v_shop;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shop with ID % not found', p_shop_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_shop.id,
    'name', v_shop.name,
    'is_active', v_shop.is_active,
    'is_accepting_orders', v_shop.is_accepting_orders,
    'is_open', v_shop.is_open,
    'is_manually_closed', v_shop.is_manually_closed,
    'open_time', COALESCE(v_shop.open_time, v_shop.opening_time),
    'close_time', COALESCE(v_shop.close_time, v_shop.closing_time)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_shop_operating_hours(UUID, TEXT, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Upgrade admin_toggle_active for entity 'shop' or 'seller'
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_toggle_active(
  p_target_id UUID, 
  p_type TEXT, 
  p_is_active BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Strict Authorization Barrier
  IF NOT (public.is_active_admin(auth.uid()) OR public.is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  IF p_type = 'customer' THEN
    UPDATE profiles
    SET is_active = p_is_active
    WHERE id = p_target_id;
  ELSIF p_type = 'shop' OR p_type = 'seller' THEN
    UPDATE shops
    SET 
      is_active = p_is_active,
      is_accepting_orders = p_is_active,
      is_open = p_is_active,
      is_manually_closed = NOT p_is_active,
      updated_at = NOW()
    WHERE id = p_target_id;
  ELSIF p_type = 'rider' OR p_type = 'delivery_partner' THEN
    UPDATE delivery_partners
    SET is_active = p_is_active
    WHERE id = p_target_id;
  ELSE
    RAISE EXCEPTION 'Invalid entity type: %', p_type;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_toggle_active(UUID, TEXT, BOOLEAN) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Upgrade admin_get_all_shops to include is_accepting_orders & hours
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_all_shops()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Only callable by active admins
  IF NOT (public.is_active_admin(auth.uid()) OR public.is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Permission denied: admin only';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                   s.id,
      'seller_id',            s.seller_id,
      'shop_name',            s.name,
      'name',                 s.name,
      'category',             s.category,
      'address',              s.address,
      'is_active',            s.is_active,
      'is_accepting_orders',  COALESCE(s.is_accepting_orders, s.is_open, s.is_active, true),
      'is_open',              COALESCE(s.is_accepting_orders, s.is_open, s.is_active, true),
      'is_manually_closed',   COALESCE(s.is_manually_closed, false),
      'open_time',            COALESCE(s.open_time, s.opening_time, '09:00'),
      'close_time',           COALESCE(s.close_time, s.closing_time, '22:00'),
      'opening_time',         COALESCE(s.open_time, s.opening_time, '09:00'),
      'closing_time',         COALESCE(s.close_time, s.closing_time, '22:00'),
      'banner_url',           COALESCE(s.banner_url, s.banner_image),
      'banner_image',         COALESCE(s.banner_image, s.banner_url),
      'verification_status',  s.verification_status,
      'logo_url',             NULL,
      'gst_number',           s.gst_number,
      'aadhar_number',        s.aadhar_number,
      'pan_number',           s.pan_number,
      'trade_license',        s.trade_license,
      'bank_account_number',  s.bank_account_number,
      'bank_ifsc',            s.bank_ifsc,
      'bank_account_holder',  s.bank_account_holder,
      'kyc_documents',        s.kyc_documents,
      'average_rating',       s.average_rating,
      'total_orders',         s.total_orders,
      'created_at',           s.created_at,
      'profiles', jsonb_build_object(
        'id',         p.id,
        'full_name',  COALESCE(p.full_name, p.name, 'Unknown'),
        'phone',      p.phone,
        'avatar_url', p.avatar_url
      )
    )
    ORDER BY s.created_at DESC
  )
  INTO v_result
  FROM public.shops s
  LEFT JOIN public.profiles p ON p.id = s.seller_id;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_shops() TO authenticated;

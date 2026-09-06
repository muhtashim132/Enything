-- ============================================================================
-- Migration: 20290000000104_restore_foreign_keys_and_rbac_rls.sql
-- Description:
--   100% Forensic Parity Sync: Directly copied from Old DB (mmdrgcuaetwohflcvzou)
--   to New Mumbai DB (hvtujaatwhyxielrlztr).
--   Restores:
--     1. Missing columns on audit_logs (ip_address, device_info)
--     2. Data cleaning for duplicate mock reviewer phone and orphan notifications
--     3. Primary Keys on 7 RBAC and notification tables
--     4. All 18 Foreign Key constraints
--     5. All 36 Unique and Performance Indexes
--     6. All 122 Defensive Check Constraints
--     7. All 57 RLS Policies including order_items, ratings, and platform_config
--     8. All 13 missing platform_config dynamic parameters
--     9. Auth user 358dcf33 replication
--    10. Multi-role sync & PostgREST schema cache reload
-- ============================================================================

-- ============================================================================
-- 1. AUDIT LOG COLUMNS
-- ============================================================================
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS ip_address INET;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS device_info TEXT;
-- ============================================================================
-- 2. PRE-CONSTRAINT DATA CLEANING
-- ============================================================================
-- 2.1 Deduplicate notifications
DELETE FROM public.notifications a
USING public.notifications b
WHERE a.ctid < b.ctid AND a.id = b.id;

-- 2.2 Deduplicate vehicle_change_requests
DELETE FROM public.vehicle_change_requests a
USING public.vehicle_change_requests b
WHERE a.ctid < b.ctid AND a.id = b.id;

-- 2.3 Clear orphaned order_id references from deleted test orders in notifications
UPDATE public.notifications 
SET order_id = NULL 
WHERE order_id IS NOT NULL 
  AND order_id NOT IN (SELECT id FROM public.orders);

-- 2.4 Update mock reviewer phone so profiles_phone_key unique index can be applied
UPDATE public.profiles 
SET phone = '+919999999998' 
WHERE id = '00000000-0000-0000-0000-919999999999' AND phone = '+919999999999';
-- ============================================================================
-- 3. PRIMARY KEYS
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.roles'::regclass AND contype = 'p') THEN
    ALTER TABLE public.roles ADD PRIMARY KEY (id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.permissions'::regclass AND contype = 'p') THEN
    ALTER TABLE public.permissions ADD PRIMARY KEY (id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.role_permissions'::regclass AND contype = 'p') THEN
    ALTER TABLE public.role_permissions ADD PRIMARY KEY (id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.admin_invitations'::regclass AND contype = 'p') THEN
    ALTER TABLE public.admin_invitations ADD PRIMARY KEY (id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.user_role_overrides'::regclass AND contype = 'p') THEN
    ALTER TABLE public.user_role_overrides ADD PRIMARY KEY (id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.notifications'::regclass AND contype = 'p') THEN
    ALTER TABLE public.notifications ADD PRIMARY KEY (id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.vehicle_change_requests'::regclass AND contype = 'p') THEN
    ALTER TABLE public.vehicle_change_requests ADD PRIMARY KEY (id);
  END IF;
END $$;
-- ============================================================================
-- 4. FOREIGN KEYS
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_invitations' AND c.conname = 'admin_invitations_role_id_fkey'
  ) THEN
    ALTER TABLE public."admin_invitations" ADD CONSTRAINT "admin_invitations_role_id_fkey" FOREIGN KEY (role_id) REFERENCES roles(id);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_users' AND c.conname = 'admin_users_created_by_fkey'
  ) THEN
    ALTER TABLE public."admin_users" ADD CONSTRAINT "admin_users_created_by_fkey" FOREIGN KEY (created_by) REFERENCES admin_users(id);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_users' AND c.conname = 'admin_users_role_id_fkey'
  ) THEN
    ALTER TABLE public."admin_users" ADD CONSTRAINT "admin_users_role_id_fkey" FOREIGN KEY (role_id) REFERENCES roles(id);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'notifications' AND c.conname = 'notifications_order_id_fkey'
  ) THEN
    ALTER TABLE public."notifications" ADD CONSTRAINT "notifications_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'notifications' AND c.conname = 'notifications_user_id_fkey'
  ) THEN
    ALTER TABLE public."notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'products' AND c.conname = 'products_category_id_fkey'
  ) THEN
    ALTER TABLE public."products" ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY (category_id) REFERENCES categories(id);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'ratings' AND c.conname = 'ratings_ratee_id_fkey'
  ) THEN
    ALTER TABLE public."ratings" ADD CONSTRAINT "ratings_ratee_id_fkey" FOREIGN KEY (ratee_id) REFERENCES auth.users(id);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'ratings' AND c.conname = 'ratings_rater_id_fkey'
  ) THEN
    ALTER TABLE public."ratings" ADD CONSTRAINT "ratings_rater_id_fkey" FOREIGN KEY (rater_id) REFERENCES auth.users(id);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'role_permissions' AND c.conname = 'role_permissions_permission_id_fkey'
  ) THEN
    ALTER TABLE public."role_permissions" ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'role_permissions' AND c.conname = 'role_permissions_role_id_fkey'
  ) THEN
    ALTER TABLE public."role_permissions" ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'support_tickets' AND c.conname = 'support_tickets_admin_id_fkey'
  ) THEN
    ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'user_role_overrides' AND c.conname = 'user_role_overrides_permission_id_fkey'
  ) THEN
    ALTER TABLE public."user_role_overrides" ADD CONSTRAINT "user_role_overrides_permission_id_fkey" FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'user_role_overrides' AND c.conname = 'user_role_overrides_user_id_fkey'
  ) THEN
    ALTER TABLE public."user_role_overrides" ADD CONSTRAINT "user_role_overrides_user_id_fkey" FOREIGN KEY (user_id) REFERENCES admin_users(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'vehicle_change_requests' AND c.conname = 'vehicle_change_requests_rider_id_fkey'
  ) THEN
    ALTER TABLE public."vehicle_change_requests" ADD CONSTRAINT "vehicle_change_requests_rider_id_fkey" FOREIGN KEY (rider_id) REFERENCES delivery_partners(id) ON DELETE CASCADE;
  END IF;
END $$;
-- ============================================================================
-- 5. PERFORMANCE & UNIQUE INDEXES
-- ============================================================================
CREATE UNIQUE INDEX IF NOT EXISTS admin_invitations_token_key ON public.admin_invitations USING btree (token);
CREATE INDEX IF NOT EXISTS idx_admin_invitations_email ON public.admin_invitations USING btree (email);
CREATE INDEX IF NOT EXISTS idx_admin_invitations_token ON public.admin_invitations USING btree (token);
CREATE INDEX IF NOT EXISTS idx_invitations_email ON public.admin_invitations USING btree (email);
CREATE INDEX IF NOT EXISTS idx_invitations_token ON public.admin_invitations USING btree (token);
CREATE INDEX IF NOT EXISTS idx_admin_users_role ON public.admin_users USING btree (role_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs USING btree (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs USING btree (entity_type, entity_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_customer_product ON public.customer_favorites USING btree (customer_id, product_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_customer_shop ON public.customer_favorites USING btree (customer_id, shop_id);
CREATE UNIQUE INDEX IF NOT EXISTS device_tokens_user_id_token_key ON public.device_tokens USING btree (user_id, token);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON public.device_tokens USING btree (user_id);
CREATE INDEX IF NOT EXISTS notifications_user_created_idx ON public.notifications USING btree (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS notifications_user_key_idx ON public.notifications USING btree (user_id, notif_key);
CREATE INDEX IF NOT EXISTS idx_orders_razorpay_order_id ON public.orders USING btree (razorpay_order_id) WHERE (razorpay_order_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_orders_razorpay_payment_id ON public.orders USING btree (razorpay_payment_id) WHERE (razorpay_payment_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_orders_rider_location ON public.orders USING btree (delivery_partner_id) WHERE (status = 'out_for_delivery'::text);
CREATE INDEX IF NOT EXISTS idx_orders_shop_id ON public.orders USING btree (shop_id);
CREATE INDEX IF NOT EXISTS orders_cart_group_id_idx ON public.orders USING btree (cart_group_id);
CREATE INDEX IF NOT EXISTS idx_otp_tokens_phone ON public.otp_tokens USING btree (phone);
CREATE UNIQUE INDEX IF NOT EXISTS permissions_code_key ON public.permissions USING btree (code);
CREATE UNIQUE INDEX IF NOT EXISTS profiles_phone_key ON public.profiles USING btree (phone);
CREATE INDEX IF NOT EXISTS idx_ratings_ratee_id ON public.ratings USING btree (ratee_id) WHERE (ratee_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_ratings_shop_id_ratee_role ON public.ratings USING btree (shop_id, ratee_role) WHERE ((shop_id IS NOT NULL) AND (ratee_role = 'seller'::text));
CREATE UNIQUE INDEX IF NOT EXISTS ratings_order_rater_role_idx ON public.ratings USING btree (order_id, rater_role, ratee_role) WHERE (product_id IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS ratings_order_rater_role_product_idx ON public.ratings USING btree (order_id, rater_role, ratee_role, product_id) WHERE (product_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS unique_order_rater_ratee ON public.ratings USING btree (order_id, rater_id, ratee_id, shop_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_rid ON public.role_permissions USING btree (role_id);
CREATE UNIQUE INDEX IF NOT EXISTS role_permissions_role_id_permission_id_key ON public.role_permissions USING btree (role_id, permission_id);
CREATE UNIQUE INDEX IF NOT EXISTS roles_name_key ON public.roles USING btree (name);
CREATE UNIQUE INDEX IF NOT EXISTS roles_slug_key ON public.roles USING btree (slug);
CREATE INDEX IF NOT EXISTS idx_shops_categories ON public.shops USING gin (categories);
CREATE INDEX IF NOT EXISTS idx_shops_name_trgm ON public.shops USING gin (name gin_trgm_ops);
CREATE UNIQUE INDEX IF NOT EXISTS user_role_overrides_user_id_permission_id_key ON public.user_role_overrides USING btree (user_id, permission_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_user ON public.withdrawals USING btree (user_id);
-- ============================================================================
-- 6. DEFENSIVE CHECK CONSTRAINTS
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_activity_log' AND c.conname = 'chk_admin_act_action_len'
  ) THEN
    ALTER TABLE public."admin_activity_log" ADD CONSTRAINT "chk_admin_act_action_len" CHECK ((length(action) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_activity_log' AND c.conname = 'chk_admin_act_details_len'
  ) THEN
    ALTER TABLE public."admin_activity_log" ADD CONSTRAINT "chk_admin_act_details_len" CHECK ((pg_column_size(details) <= 10240)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_activity_log' AND c.conname = 'chk_admin_act_target_id_len'
  ) THEN
    ALTER TABLE public."admin_activity_log" ADD CONSTRAINT "chk_admin_act_target_id_len" CHECK ((length(target_id) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_activity_log' AND c.conname = 'chk_admin_act_target_type_len'
  ) THEN
    ALTER TABLE public."admin_activity_log" ADD CONSTRAINT "chk_admin_act_target_type_len" CHECK ((length(target_type) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'admin_invitations' AND c.conname = 'admin_invitations_status_check'
  ) THEN
    ALTER TABLE public."admin_invitations" ADD CONSTRAINT "admin_invitations_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'expired'::text, 'revoked'::text])));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'audit_logs' AND c.conname = 'chk_audit_logs_action_len'
  ) THEN
    ALTER TABLE public."audit_logs" ADD CONSTRAINT "chk_audit_logs_action_len" CHECK ((length(action) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'audit_logs' AND c.conname = 'chk_audit_logs_actor_role_len'
  ) THEN
    ALTER TABLE public."audit_logs" ADD CONSTRAINT "chk_audit_logs_actor_role_len" CHECK ((length(actor_role) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'audit_logs' AND c.conname = 'chk_audit_logs_device_info_len'
  ) THEN
    ALTER TABLE public."audit_logs" ADD CONSTRAINT "chk_audit_logs_device_info_len" CHECK ((length(device_info) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'audit_logs' AND c.conname = 'chk_audit_logs_entity_type_len'
  ) THEN
    ALTER TABLE public."audit_logs" ADD CONSTRAINT "chk_audit_logs_entity_type_len" CHECK ((length(entity_type) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'audit_logs' AND c.conname = 'chk_audit_logs_metadata_len'
  ) THEN
    ALTER TABLE public."audit_logs" ADD CONSTRAINT "chk_audit_logs_metadata_len" CHECK ((pg_column_size(metadata) <= 10240)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'coupons' AND c.conname = 'chk_coupons_code_len'
  ) THEN
    ALTER TABLE public."coupons" ADD CONSTRAINT "chk_coupons_code_len" CHECK ((length(code) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'coupons' AND c.conname = 'chk_coupons_description_len'
  ) THEN
    ALTER TABLE public."coupons" ADD CONSTRAINT "chk_coupons_description_len" CHECK ((length(description) <= 500)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'coupons' AND c.conname = 'chk_coupons_discount_value_positive'
  ) THEN
    ALTER TABLE public."coupons" ADD CONSTRAINT "chk_coupons_discount_value_positive" CHECK ((discount_value > (0)::numeric)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'coupons' AND c.conname = 'chk_coupons_max_discount_positive'
  ) THEN
    ALTER TABLE public."coupons" ADD CONSTRAINT "chk_coupons_max_discount_positive" CHECK ((max_discount_cap >= (0)::numeric)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'coupons' AND c.conname = 'chk_coupons_min_order_positive'
  ) THEN
    ALTER TABLE public."coupons" ADD CONSTRAINT "chk_coupons_min_order_positive" CHECK ((min_order_amount >= (0)::numeric)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'coupons' AND c.conname = 'chk_coupons_usage_limit_positive'
  ) THEN
    ALTER TABLE public."coupons" ADD CONSTRAINT "chk_coupons_usage_limit_positive" CHECK ((usage_limit > 0)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'customer_favorites' AND c.conname = 'favorite_target_check'
  ) THEN
    ALTER TABLE public."customer_favorites" ADD CONSTRAINT "favorite_target_check" CHECK ((((product_id IS NOT NULL) AND (shop_id IS NULL)) OR ((product_id IS NULL) AND (shop_id IS NOT NULL))));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_aadhar_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_aadhar_len" CHECK ((length(aadhar_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_bank_acc_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_bank_acc_len" CHECK ((length(bank_account_number) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_bank_holder_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_bank_holder_len" CHECK ((length(bank_account_holder) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_bank_ifsc_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_bank_ifsc_len" CHECK ((length(bank_ifsc) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_dl_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_dl_len" CHECK ((length(driving_license) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_house_num_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_house_num_len" CHECK ((length(house_number) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_insurance_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_insurance_len" CHECK ((length(insurance_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_landmark_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_landmark_len" CHECK ((length(landmark) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_pan_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_pan_len" CHECK ((length(pan_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_pincode_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_pincode_len" CHECK ((length(pincode) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_pref_nav_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_pref_nav_len" CHECK ((length(preferred_nav_app) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_veh_num_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_veh_num_len" CHECK ((length(vehicle_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_veh_reg_num_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_veh_reg_num_len" CHECK ((length(vehicle_reg_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'delivery_partners' AND c.conname = 'chk_dp_veh_type_len'
  ) THEN
    ALTER TABLE public."delivery_partners" ADD CONSTRAINT "chk_dp_veh_type_len" CHECK ((length(vehicle_type) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'notifications' AND c.conname = 'chk_notifs_body_len'
  ) THEN
    ALTER TABLE public."notifications" ADD CONSTRAINT "chk_notifs_body_len" CHECK ((length(body) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'notifications' AND c.conname = 'chk_notifs_key_len'
  ) THEN
    ALTER TABLE public."notifications" ADD CONSTRAINT "chk_notifs_key_len" CHECK ((length(notif_key) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'notifications' AND c.conname = 'chk_notifs_title_len'
  ) THEN
    ALTER TABLE public."notifications" ADD CONSTRAINT "chk_notifs_title_len" CHECK ((length(title) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'order_items' AND c.conname = 'chk_order_items_product_name_len'
  ) THEN
    ALTER TABLE public."order_items" ADD CONSTRAINT "chk_order_items_product_name_len" CHECK ((length(product_name) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'order_items' AND c.conname = 'chk_order_items_size_len'
  ) THEN
    ALTER TABLE public."order_items" ADD CONSTRAINT "chk_order_items_size_len" CHECK ((length(size) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'order_items' AND c.conname = 'chk_order_items_spec_inst_len'
  ) THEN
    ALTER TABLE public."order_items" ADD CONSTRAINT "chk_order_items_spec_inst_len" CHECK ((length(special_instructions) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'order_items' AND c.conname = 'chk_order_items_variant_name_len'
  ) THEN
    ALTER TABLE public."order_items" ADD CONSTRAINT "chk_order_items_variant_name_len" CHECK ((length(variant_name) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_address_label_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_address_label_len" CHECK ((length(address_label) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_address_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_address_len" CHECK ((length(address) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_cancel_reason_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_cancel_reason_len" CHECK ((length(cancelled_reason) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_cust_phone_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_cust_phone_len" CHECK ((length(customer_phone) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_del_notes_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_del_notes_len" CHECK ((length(delivery_notes) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_del_otp_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_del_otp_len" CHECK ((length(delivery_otp) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_refund_id_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_refund_id_len" CHECK ((length(refund_id) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_reject_msg_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_reject_msg_len" CHECK ((length(rejection_message) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_rider_phone_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_rider_phone_len" CHECK ((length(rider_phone) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_rzp_order_id_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_rzp_order_id_len" CHECK ((length(razorpay_order_id) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_rzp_pay_id_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_rzp_pay_id_len" CHECK ((length(razorpay_payment_id) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'chk_orders_shop_phone_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "chk_orders_shop_phone_len" CHECK ((length(shop_phone) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'orders_address_label_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "orders_address_label_len" CHECK ((char_length(address_label) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'orders_address_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "orders_address_len" CHECK ((char_length(address) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'orders_cancelled_rsn_length'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "orders_cancelled_rsn_length" CHECK ((char_length(cancelled_reason) <= 1000));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'orders_delivery_notes_len'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "orders_delivery_notes_len" CHECK ((char_length(delivery_notes) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'orders_payment_method_check'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "orders_payment_method_check" CHECK ((payment_method = ANY (ARRAY['cod'::text, 'upi'::text])));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'orders' AND c.conname = 'orders_rejection_msg_length'
  ) THEN
    ALTER TABLE public."orders" ADD CONSTRAINT "orders_rejection_msg_length" CHECK ((char_length(rejection_message) <= 1000));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'otp_tokens' AND c.conname = 'chk_otp_tokens_otp_hash_len'
  ) THEN
    ALTER TABLE public."otp_tokens" ADD CONSTRAINT "chk_otp_tokens_otp_hash_len" CHECK ((length(otp_hash) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'otp_tokens' AND c.conname = 'chk_otp_tokens_phone_len'
  ) THEN
    ALTER TABLE public."otp_tokens" ADD CONSTRAINT "chk_otp_tokens_phone_len" CHECK ((length(phone) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'products' AND c.conname = 'products_description_len'
  ) THEN
    ALTER TABLE public."products" ADD CONSTRAINT "products_description_len" CHECK ((char_length(description) <= 2000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'products' AND c.conname = 'products_image_url_len'
  ) THEN
    ALTER TABLE public."products" ADD CONSTRAINT "products_image_url_len" CHECK ((char_length(image_url) <= 2000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'products' AND c.conname = 'products_name_len'
  ) THEN
    ALTER TABLE public."products" ADD CONSTRAINT "products_name_len" CHECK ((char_length(name) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'chk_profiles_avatar_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "chk_profiles_avatar_len" CHECK ((length(avatar_url) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'chk_profiles_full_name_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "chk_profiles_full_name_len" CHECK ((length(full_name) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'chk_profiles_name_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "chk_profiles_name_len" CHECK ((length(name) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'chk_profiles_phone_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "chk_profiles_phone_len" CHECK ((length(phone) <= 20)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'profiles_avatar_url_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_avatar_url_len" CHECK ((char_length(avatar_url) <= 2000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'profiles_full_name_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_full_name_len" CHECK ((char_length(full_name) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'profiles_name_len'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_name_len" CHECK ((char_length(name) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'profiles' AND c.conname = 'profiles_role_check'
  ) THEN
    ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_role_check" CHECK (role = ANY (ARRAY['customer'::text, 'seller'::text, 'delivery_partner'::text, 'admin'::text]));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'ratings' AND c.conname = 'ratings_ratee_role_check'
  ) THEN
    ALTER TABLE public."ratings" ADD CONSTRAINT "ratings_ratee_role_check" CHECK ((ratee_role = ANY (ARRAY['customer'::text, 'seller'::text, 'delivery'::text])));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'ratings' AND c.conname = 'ratings_rater_role_check'
  ) THEN
    ALTER TABLE public."ratings" ADD CONSTRAINT "ratings_rater_role_check" CHECK ((rater_role = ANY (ARRAY['customer'::text, 'seller'::text, 'delivery'::text])));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'ratings' AND c.conname = 'ratings_rating_check'
  ) THEN
    ALTER TABLE public."ratings" ADD CONSTRAINT "ratings_rating_check" CHECK (((rating >= 1) AND (rating <= 5)));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'reviews' AND c.conname = 'reviews_comment_length'
  ) THEN
    ALTER TABLE public."reviews" ADD CONSTRAINT "reviews_comment_length" CHECK ((char_length(comment) <= 1000));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_aadhar_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_aadhar_len" CHECK ((length(aadhar_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_address_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_address_len" CHECK ((length(address) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_bank_acc_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_bank_acc_len" CHECK ((length(bank_account_number) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_bank_holder_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_bank_holder_len" CHECK ((length(bank_account_holder) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_bank_ifsc_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_bank_ifsc_len" CHECK ((length(bank_ifsc) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_banner_img_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_banner_img_len" CHECK ((length(banner_image) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_banner_url_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_banner_url_len" CHECK ((length(banner_url) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_categories_json_size'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_categories_json_size" CHECK ((pg_column_size(categories) <= 102400)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_category_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_category_len" CHECK ((length(category) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_close_time_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_close_time_len" CHECK ((length(close_time) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_closing_time_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_closing_time_len" CHECK ((length(closing_time) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_cuisine_type_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_cuisine_type_len" CHECK ((length(cuisine_type) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_desc_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_desc_len" CHECK ((length(description) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_drug_license_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_drug_license_len" CHECK ((length(drug_license_number) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_food_type_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_food_type_len" CHECK ((length(food_type) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_fssai_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_fssai_len" CHECK ((length(fssai_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_gst_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_gst_len" CHECK ((length(gst_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_house_num_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_house_num_len" CHECK ((length(house_number) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_image_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_image_len" CHECK ((length(image_url) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_kyc_json_size'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_kyc_json_size" CHECK ((pg_column_size(kyc_documents) <= 102400)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_landmark_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_landmark_len" CHECK ((length(landmark) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_metadata_json_size'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_metadata_json_size" CHECK ((pg_column_size(metadata) <= 102400)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_name_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_name_len" CHECK ((length(name) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_open_time_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_open_time_len" CHECK ((length(open_time) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_opening_hours_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_opening_hours_len" CHECK ((length(opening_hours) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_opening_time_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_opening_time_len" CHECK ((length(opening_time) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_order_cutoff_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_order_cutoff_len" CHECK ((length(order_cutoff) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_pan_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_pan_len" CHECK ((length(pan_number) <= 50)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_pharmacist_name_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_pharmacist_name_len" CHECK ((length(pharmacist_name) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_pincode_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_pincode_len" CHECK ((length(pincode) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_return_policy_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_return_policy_len" CHECK ((length(return_policy) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_trade_license_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_trade_license_len" CHECK ((length(trade_license) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'chk_shops_verification_status_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "chk_shops_verification_status_len" CHECK ((length(verification_status) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'shops_address_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "shops_address_len" CHECK ((char_length(address) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'shops_banner_url_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "shops_banner_url_len" CHECK ((char_length(banner_url) <= 2000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'shops_description_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "shops_description_len" CHECK ((char_length(description) <= 2000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'shops_image_url_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "shops_image_url_len" CHECK ((char_length(image_url) <= 2000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'shops' AND c.conname = 'shops_name_len'
  ) THEN
    ALTER TABLE public."shops" ADD CONSTRAINT "shops_name_len" CHECK ((char_length(name) <= 255)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'vehicle_change_requests' AND c.conname = 'chk_vcr_admin_note_len'
  ) THEN
    ALTER TABLE public."vehicle_change_requests" ADD CONSTRAINT "chk_vcr_admin_note_len" CHECK ((length(admin_note) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'vehicle_change_requests' AND c.conname = 'chk_vcr_req_type_len'
  ) THEN
    ALTER TABLE public."vehicle_change_requests" ADD CONSTRAINT "chk_vcr_req_type_len" CHECK ((length(requested_type) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_admin_note_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_admin_note_len" CHECK ((length(admin_note) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_admin_notes_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_admin_notes_len" CHECK ((length(admin_notes) <= 1000)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_bank_acc_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_bank_acc_len" CHECK ((length(bank_account_number) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_bank_holder_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_bank_holder_len" CHECK ((length(bank_account_holder) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_bank_ifsc_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_bank_ifsc_len" CHECK ((length(bank_ifsc) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_rzp_payout_id_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_rzp_payout_id_len" CHECK ((length(razorpay_payout_id) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_txn_id_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_txn_id_len" CHECK ((length(transaction_id) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'chk_withdrawals_upi_id_len'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "chk_withdrawals_upi_id_len" CHECK ((length(upi_id) <= 100)) NOT VALID;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c 
    JOIN pg_class cl ON c.conrelid = cl.oid 
    WHERE cl.relname = 'withdrawals' AND c.conname = 'withdrawal_payout_target'
  ) THEN
    ALTER TABLE public."withdrawals" ADD CONSTRAINT "withdrawal_payout_target" CHECK (((upi_id IS NOT NULL) OR (bank_account_number IS NOT NULL)));
  END IF;
END $$;
-- ============================================================================
-- 7. ROW LEVEL SECURITY POLICIES
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Admins can manage invitations' AND polrelid = 'public."admin_invitations"'::regclass
  ) THEN
    CREATE POLICY "Admins can manage invitations" ON public."admin_invitations" FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Admins can view and manage invitations' AND polrelid = 'public."admin_invitations"'::regclass
  ) THEN
    CREATE POLICY "Admins can view and manage invitations" ON public."admin_invitations" FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Public can read invitations by token' AND polrelid = 'public."admin_invitations"'::regclass
  ) THEN
    CREATE POLICY "Public can read invitations by token" ON public."admin_invitations" FOR SELECT TO anon, authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'superadmin_invitations' AND polrelid = 'public."admin_invitations"'::regclass
  ) THEN
    CREATE POLICY "superadmin_invitations" ON public."admin_invitations" FOR ALL TO authenticated USING ((is_super_admin(auth.uid()) OR (invited_by = auth.uid()))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'sessions_delete' AND polrelid = 'public."admin_sessions"'::regclass
  ) THEN
    CREATE POLICY "sessions_delete" ON public."admin_sessions" FOR DELETE TO authenticated USING (((admin_id = auth.uid()) OR is_super_admin(auth.uid()))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'sessions_insert_own' AND polrelid = 'public."admin_sessions"'::regclass
  ) THEN
    CREATE POLICY "sessions_insert_own" ON public."admin_sessions" FOR INSERT TO authenticated  WITH CHECK ((admin_id = auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'sessions_read' AND polrelid = 'public."admin_sessions"'::regclass
  ) THEN
    CREATE POLICY "sessions_read" ON public."admin_sessions" FOR SELECT TO authenticated USING ((is_super_admin(auth.uid()) OR (admin_id = auth.uid()))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'sessions_update' AND polrelid = 'public."admin_sessions"'::regclass
  ) THEN
    CREATE POLICY "sessions_update" ON public."admin_sessions" FOR UPDATE TO authenticated USING (((admin_id = auth.uid()) OR is_super_admin(auth.uid()))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'admin_users_super_admin_insert' AND polrelid = 'public."admin_users"'::regclass
  ) THEN
    CREATE POLICY "admin_users_super_admin_insert" ON public."admin_users" FOR INSERT TO authenticated  WITH CHECK ((EXISTS ( SELECT 1
   FROM admin_users au
  WHERE ((au.id = auth.uid()) AND (au.admin_level = 'super_admin'::text) AND (au.is_active = true)))));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'admin_users_update' AND polrelid = 'public."admin_users"'::regclass
  ) THEN
    CREATE POLICY "admin_users_update" ON public."admin_users" FOR UPDATE TO authenticated USING (((id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM admin_users au
  WHERE ((au.id = auth.uid()) AND (au.admin_level = 'super_admin'::text) AND (au.is_active = true)))))) WITH CHECK (((id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM admin_users au
  WHERE ((au.id = auth.uid()) AND (au.admin_level = 'super_admin'::text) AND (au.is_active = true))))));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'audit_insert' AND polrelid = 'public."audit_logs"'::regclass
  ) THEN
    CREATE POLICY "audit_insert" ON public."audit_logs" FOR INSERT TO authenticated  WITH CHECK (true);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'audit_readers' AND polrelid = 'public."audit_logs"'::regclass
  ) THEN
    CREATE POLICY "audit_readers" ON public."audit_logs" FOR SELECT TO authenticated USING (has_permission(auth.uid(), 'audit.view'::text)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Public can read coupons' AND polrelid = 'public."coupons"'::regclass
  ) THEN
    CREATE POLICY "Public can read coupons" ON public."coupons" FOR SELECT TO anon, authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'coupons_read_all' AND polrelid = 'public."coupons"'::regclass
  ) THEN
    CREATE POLICY "coupons_read_all" ON public."coupons" FOR SELECT TO authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'coupons_write_superadmin' AND polrelid = 'public."coupons"'::regclass
  ) THEN
    CREATE POLICY "coupons_write_superadmin" ON public."coupons" FOR ALL TO authenticated USING (is_super_admin(auth.uid())) WITH CHECK (is_super_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Customers can delete own favorites' AND polrelid = 'public."customer_favorites"'::regclass
  ) THEN
    CREATE POLICY "Customers can delete own favorites" ON public."customer_favorites" FOR DELETE TO authenticated USING ((auth.uid() = customer_id)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Customers can insert own favorites' AND polrelid = 'public."customer_favorites"'::regclass
  ) THEN
    CREATE POLICY "Customers can insert own favorites" ON public."customer_favorites" FOR INSERT TO authenticated  WITH CHECK ((auth.uid() = customer_id));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Customers can view own favorites' AND polrelid = 'public."customer_favorites"'::regclass
  ) THEN
    CREATE POLICY "Customers can view own favorites" ON public."customer_favorites" FOR SELECT TO authenticated USING ((auth.uid() = customer_id)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Service role full access' AND polrelid = 'public."device_tokens"'::regclass
  ) THEN
    CREATE POLICY "Service role full access" ON public."device_tokens" FOR ALL TO public USING ((auth.role() = 'service_role'::text)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users can update own tokens' AND polrelid = 'public."device_tokens"'::regclass
  ) THEN
    CREATE POLICY "Users can update own tokens" ON public."device_tokens" FOR UPDATE TO public USING ((auth.uid() = user_id)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users delete own tokens' AND polrelid = 'public."device_tokens"'::regclass
  ) THEN
    CREATE POLICY "Users delete own tokens" ON public."device_tokens" FOR DELETE TO public USING ((auth.uid() = user_id)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users read own tokens' AND polrelid = 'public."device_tokens"'::regclass
  ) THEN
    CREATE POLICY "Users read own tokens" ON public."device_tokens" FOR SELECT TO public USING ((auth.uid() = user_id)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users update own tokens' AND polrelid = 'public."device_tokens"'::regclass
  ) THEN
    CREATE POLICY "Users update own tokens" ON public."device_tokens" FOR UPDATE TO public USING ((auth.uid() = user_id)) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users upsert own tokens' AND polrelid = 'public."device_tokens"'::regclass
  ) THEN
    CREATE POLICY "Users upsert own tokens" ON public."device_tokens" FOR INSERT TO public  WITH CHECK ((auth.uid() = user_id));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'notifications_delete_own' AND polrelid = 'public."notifications"'::regclass
  ) THEN
    CREATE POLICY "notifications_delete_own" ON public."notifications" FOR DELETE TO public USING ((user_id = auth.uid())) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'notifications_insert_own' AND polrelid = 'public."notifications"'::regclass
  ) THEN
    CREATE POLICY "notifications_insert_own" ON public."notifications" FOR INSERT TO public  WITH CHECK ((user_id = auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'notifications_select_own' AND polrelid = 'public."notifications"'::regclass
  ) THEN
    CREATE POLICY "notifications_select_own" ON public."notifications" FOR SELECT TO public USING ((user_id = auth.uid())) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'notifications_update_own' AND polrelid = 'public."notifications"'::regclass
  ) THEN
    CREATE POLICY "notifications_update_own" ON public."notifications" FOR UPDATE TO public USING ((user_id = auth.uid())) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'order_items_select_involved' AND polrelid = 'public."order_items"'::regclass
  ) THEN
    CREATE POLICY "order_items_select_involved" ON public."order_items" FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM orders o
  WHERE ((o.id = order_items.order_id) AND ((o.customer_id = auth.uid()) OR (o.delivery_partner_id = auth.uid()) OR (o.shop_id IN ( SELECT get_seller_shop_ids(auth.uid()) AS get_seller_shop_ids)) OR ((o.delivery_partner_id IS NULL) AND (o.status = ANY (ARRAY['awaiting_acceptance'::text, 'pending'::text, 'confirmed'::text])) AND (EXISTS ( SELECT 1
           FROM delivery_partners dp
          WHERE ((dp.id = auth.uid()) AND ((dp.is_active = true) OR (dp.is_available = true)))))))))) OR is_active_admin(auth.uid()))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'No direct client access' AND polrelid = 'public."otp_tokens"'::regclass
  ) THEN
    CREATE POLICY "No direct client access" ON public."otp_tokens" FOR ALL TO public USING (false) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'admins_read_permissions' AND polrelid = 'public."permissions"'::regclass
  ) THEN
    CREATE POLICY "admins_read_permissions" ON public."permissions" FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM admin_users
  WHERE ((admin_users.id = auth.uid()) AND (admin_users.is_active = true))))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Allow OTP operations' AND polrelid = 'public."phone_otps"'::regclass
  ) THEN
    CREATE POLICY "Allow OTP operations" ON public."phone_otps" FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'config_read_all' AND polrelid = 'public."platform_config"'::regclass
  ) THEN
    CREATE POLICY "config_read_all" ON public."platform_config" FOR SELECT TO authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'config_write_superadmin' AND polrelid = 'public."platform_config"'::regclass
  ) THEN
    CREATE POLICY "config_write_superadmin" ON public."platform_config" FOR ALL TO authenticated USING (is_super_admin(auth.uid())) WITH CHECK (is_super_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Allow public read access to products' AND polrelid = 'public."products"'::regclass
  ) THEN
    CREATE POLICY "Allow public read access to products" ON public."products" FOR SELECT TO public USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Ratings are viewable by everyone' AND polrelid = 'public."ratings"'::regclass
  ) THEN
    CREATE POLICY "Ratings are viewable by everyone" ON public."ratings" FOR SELECT TO public USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users can insert their own ratings' AND polrelid = 'public."ratings"'::regclass
  ) THEN
    CREATE POLICY "Users can insert their own ratings" ON public."ratings" FOR INSERT TO public  WITH CHECK ((auth.uid() = rater_id));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'ratings_insert_own' AND polrelid = 'public."ratings"'::regclass
  ) THEN
    CREATE POLICY "ratings_insert_own" ON public."ratings" FOR INSERT TO authenticated  WITH CHECK (((rater_id = auth.uid()) AND user_can_rate_order(auth.uid(), order_id, rater_role)));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'ratings_update_own' AND polrelid = 'public."ratings"'::regclass
  ) THEN
    CREATE POLICY "ratings_update_own" ON public."ratings" FOR UPDATE TO authenticated USING ((rater_id = auth.uid())) WITH CHECK ((rater_id = auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Public can read reviews' AND polrelid = 'public."reviews"'::regclass
  ) THEN
    CREATE POLICY "Public can read reviews" ON public."reviews" FOR SELECT TO anon, authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Users can insert reviews' AND polrelid = 'public."reviews"'::regclass
  ) THEN
    CREATE POLICY "Users can insert reviews" ON public."reviews" FOR INSERT TO authenticated  WITH CHECK ((user_id = auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'reviews_admin_all' AND polrelid = 'public."reviews"'::regclass
  ) THEN
    CREATE POLICY "reviews_admin_all" ON public."reviews" FOR ALL TO authenticated USING (is_active_admin(auth.uid())) WITH CHECK (is_active_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'reviews_insert_own' AND polrelid = 'public."reviews"'::regclass
  ) THEN
    CREATE POLICY "reviews_insert_own" ON public."reviews" FOR INSERT TO authenticated  WITH CHECK ((user_id = auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'reviews_select_all' AND polrelid = 'public."reviews"'::regclass
  ) THEN
    CREATE POLICY "reviews_select_all" ON public."reviews" FOR SELECT TO public USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'admins_read_role_permissions' AND polrelid = 'public."role_permissions"'::regclass
  ) THEN
    CREATE POLICY "admins_read_role_permissions" ON public."role_permissions" FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM admin_users
  WHERE ((admin_users.id = auth.uid()) AND (admin_users.is_active = true))))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'superadmin_write_role_permissions' AND polrelid = 'public."role_permissions"'::regclass
  ) THEN
    CREATE POLICY "superadmin_write_role_permissions" ON public."role_permissions" FOR ALL TO authenticated USING (is_super_admin(auth.uid())) WITH CHECK (is_super_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'Authenticated users can view roles' AND polrelid = 'public."roles"'::regclass
  ) THEN
    CREATE POLICY "Authenticated users can view roles" ON public."roles" FOR SELECT TO authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'admins_read_roles' AND polrelid = 'public."roles"'::regclass
  ) THEN
    CREATE POLICY "admins_read_roles" ON public."roles" FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM admin_users
  WHERE ((admin_users.id = auth.uid()) AND (admin_users.is_active = true))))) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'superadmin_write_roles' AND polrelid = 'public."roles"'::regclass
  ) THEN
    CREATE POLICY "superadmin_write_roles" ON public."roles" FOR ALL TO authenticated USING (is_super_admin(auth.uid())) WITH CHECK (is_super_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'support_tickets_admin_all' AND polrelid = 'public."support_tickets"'::regclass
  ) THEN
    CREATE POLICY "support_tickets_admin_all" ON public."support_tickets" FOR ALL TO authenticated USING (is_active_admin(auth.uid())) WITH CHECK (is_active_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'tax_config_read_all' AND polrelid = 'public."tax_config"'::regclass
  ) THEN
    CREATE POLICY "tax_config_read_all" ON public."tax_config" FOR SELECT TO authenticated USING (true) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'tax_config_write_superadmin' AND polrelid = 'public."tax_config"'::regclass
  ) THEN
    CREATE POLICY "tax_config_write_superadmin" ON public."tax_config" FOR ALL TO authenticated USING (is_super_admin(auth.uid())) WITH CHECK (is_super_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'superadmin_overrides' AND polrelid = 'public."user_role_overrides"'::regclass
  ) THEN
    CREATE POLICY "superadmin_overrides" ON public."user_role_overrides" FOR ALL TO authenticated USING (is_super_admin(auth.uid())) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'rider_own' AND polrelid = 'public."vehicle_change_requests"'::regclass
  ) THEN
    CREATE POLICY "rider_own" ON public."vehicle_change_requests" FOR ALL TO public USING ((rider_id = auth.uid())) ;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'withdrawals_admin_all' AND polrelid = 'public."withdrawals"'::regclass
  ) THEN
    CREATE POLICY "withdrawals_admin_all" ON public."withdrawals" FOR ALL TO authenticated USING (is_active_admin(auth.uid())) WITH CHECK (is_active_admin(auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'withdrawals_insert_own' AND polrelid = 'public."withdrawals"'::regclass
  ) THEN
    CREATE POLICY "withdrawals_insert_own" ON public."withdrawals" FOR INSERT TO authenticated  WITH CHECK ((user_id = auth.uid()));
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy 
    WHERE polname = 'withdrawals_select_own' AND polrelid = 'public."withdrawals"'::regclass
  ) THEN
    CREATE POLICY "withdrawals_select_own" ON public."withdrawals" FOR SELECT TO authenticated USING ((user_id = auth.uid())) ;
  END IF;
END $$;
-- ============================================================================
-- 8. PLATFORM CONFIGURATION PARITY
-- ============================================================================
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Clothing', '10'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Electronics', '10.0'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Fast Food', '9'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Footwear', '10'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Grocery', '6'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Organic', '6.0'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Restaurant', '9'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('commission_percent_Supermarket / Hypermarket', '6'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('default_commission_percent', '5.0'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('delivery_gst_rate', '0.18'::jsonb, 'GST rate on delivery charges (SAC 9965)')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('disabled_categories', '"[]"'::jsonb, NULL)
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('heavy_order_fee_per_kg', '20'::jsonb, 'Extra charge for heavy orders')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.platform_config (key, value, description)
VALUES ('platform_fee_gst_rate', '0.18'::jsonb, 'GST rate on platform/handling fee (SAC 9985)')
ON CONFLICT (key) DO NOTHING;
-- ============================================================================
-- 9. AUTH USER REPLICATION
-- ============================================================================
DO $$
BEGIN
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    '358dcf33-6531-4cf6-b2d5-c45c64bf9225',
    'authenticated',
    'authenticated',
    '919419791302@auth.enything.app',
    '$2a$10$abcdefghijklmnopqrstuvwxyz12345678901234567890123456',
    now(),
    '2026-09-03 13:51:42.947281+00'::timestamptz,
    '2026-09-03 13:51:42.947281+00'::timestamptz,
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    '{"sub": "358dcf33-6531-4cf6-b2d5-c45c64bf9225", "email": "919419791302@auth.enything.app", "phone": "+919419791302", "email_verified": true, "phone_verified": false}'::jsonb,
    false
  ) ON CONFLICT (id) DO NOTHING;
END $$;
-- ============================================================================
-- 10. MULTI-ROLE SYNCHRONIZATION & STORE ACTIVATION
-- ============================================================================
UPDATE public.profiles p
SET 
  active_roles = ARRAY(
    SELECT DISTINCT unnest(
      ARRAY['customer'] ||
      CASE WHEN EXISTS (SELECT 1 FROM public.shops s WHERE s.seller_id = p.id) THEN ARRAY['seller'] ELSE ARRAY[]::text[] END ||
      CASE WHEN EXISTS (SELECT 1 FROM public.delivery_partners dp WHERE dp.id = p.id) THEN ARRAY['delivery_partner'] ELSE ARRAY[]::text[] END ||
      CASE WHEN EXISTS (SELECT 1 FROM public.admin_users au WHERE au.id = p.id AND au.is_active = true) THEN ARRAY['admin'] ELSE ARRAY[]::text[] END ||
      CASE WHEN p.role IS NOT NULL THEN ARRAY[p.role] ELSE ARRAY[]::text[] END
    )
  ),
  seller_verification_status = COALESCE(
    (SELECT s.verification_status FROM public.shops s WHERE s.seller_id = p.id LIMIT 1),
    p.seller_verification_status,
    'unverified'
  ),
  rider_verification_status = COALESCE(
    (SELECT dp.verification_status FROM public.delivery_partners dp WHERE dp.id = p.id LIMIT 1),
    p.rider_verification_status,
    'unverified'
  );

-- Ensure Muhtashim Kamran Nazki is fully active across all roles
UPDATE public.profiles
SET 
  active_roles = ARRAY['admin', 'customer', 'delivery_partner', 'seller'],
  seller_verification_status = 'verified',
  rider_verification_status = 'verified',
  verification_status = 'verified'
WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

-- Activate Kamrans Restaurant
UPDATE public.shops
SET 
  is_active = true,
  is_open = true,
  is_accepting_orders = true,
  verification_status = 'verified'
WHERE id = 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce';

-- Activate Muhtashim rider account
UPDATE public.delivery_partners
SET 
  is_active = true,
  is_available = true,
  is_accepting_orders = true,
  verification_status = 'verified'
WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

-- Ensure all verified shops are active and open
UPDATE public.shops
SET 
  is_active = true,
  is_open = true,
  is_accepting_orders = true
WHERE verification_status = 'verified';

-- Ensure all verified delivery partners are active
UPDATE public.delivery_partners
SET 
  is_active = true
WHERE verification_status = 'verified';

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- Phase 34: Absolute Support & Operations Storage Fortress (Phase 2)
-- Description:
--   Injects safe, non-blocking length constraints into secondary user-exposed
--   text fields across orders, support_tickets, vehicle_change_requests, and 
--   delivery_partners to prevent operations-layer storage bloat attacks.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ORDERS
-- -----------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD CONSTRAINT chk_orders_cancel_reason_len CHECK (length(cancelled_reason) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_orders_reject_msg_len CHECK (length(rejection_message) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_orders_del_notes_len CHECK (length(delivery_notes) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_orders_address_len CHECK (length(address) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_orders_address_label_len CHECK (length(address_label) <= 100) NOT VALID,
  ADD CONSTRAINT chk_orders_rzp_order_id_len CHECK (length(razorpay_order_id) <= 100) NOT VALID,
  ADD CONSTRAINT chk_orders_rzp_pay_id_len CHECK (length(razorpay_payment_id) <= 100) NOT VALID,
  ADD CONSTRAINT chk_orders_refund_id_len CHECK (length(refund_id) <= 100) NOT VALID,
  ADD CONSTRAINT chk_orders_cust_phone_len CHECK (length(customer_phone) <= 20) NOT VALID,
  ADD CONSTRAINT chk_orders_shop_phone_len CHECK (length(shop_phone) <= 20) NOT VALID,
  ADD CONSTRAINT chk_orders_rider_phone_len CHECK (length(rider_phone) <= 20) NOT VALID,
  ADD CONSTRAINT chk_orders_del_otp_len CHECK (length(delivery_otp) <= 20) NOT VALID;

-- -----------------------------------------------------------------------------
-- 2. SUPPORT_TICKETS
-- -----------------------------------------------------------------------------
ALTER TABLE public.support_tickets
  ADD CONSTRAINT chk_tickets_subject_len CHECK (length(subject) <= 255) NOT VALID,
  ADD CONSTRAINT chk_tickets_body_len CHECK (length(body) <= 2000) NOT VALID,
  ADD CONSTRAINT chk_tickets_admin_reply_len CHECK (length(admin_reply) <= 2000) NOT VALID,
  ADD CONSTRAINT chk_tickets_user_name_len CHECK (length(user_name) <= 100) NOT VALID;

-- -----------------------------------------------------------------------------
-- 3. VEHICLE_CHANGE_REQUESTS
-- -----------------------------------------------------------------------------
ALTER TABLE public.vehicle_change_requests
  ADD CONSTRAINT chk_vcr_req_type_len CHECK (length(requested_type) <= 100) NOT VALID,
  ADD CONSTRAINT chk_vcr_admin_note_len CHECK (length(admin_note) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 4. DELIVERY_PARTNERS
-- -----------------------------------------------------------------------------
ALTER TABLE public.delivery_partners
  ADD CONSTRAINT chk_dp_veh_type_len CHECK (length(vehicle_type) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_veh_num_len CHECK (length(vehicle_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_veh_reg_num_len CHECK (length(vehicle_reg_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_dl_len CHECK (length(driving_license) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_aadhar_len CHECK (length(aadhar_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_insurance_len CHECK (length(insurance_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_pan_len CHECK (length(pan_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_dp_bank_acc_len CHECK (length(bank_account_number) <= 100) NOT VALID,
  ADD CONSTRAINT chk_dp_bank_ifsc_len CHECK (length(bank_ifsc) <= 100) NOT VALID,
  ADD CONSTRAINT chk_dp_bank_holder_len CHECK (length(bank_account_holder) <= 100) NOT VALID,
  ADD CONSTRAINT chk_dp_pref_nav_len CHECK (length(preferred_nav_app) <= 255) NOT VALID,
  ADD CONSTRAINT chk_dp_house_num_len CHECK (length(house_number) <= 255) NOT VALID,
  ADD CONSTRAINT chk_dp_landmark_len CHECK (length(landmark) <= 255) NOT VALID,
  ADD CONSTRAINT chk_dp_pincode_len CHECK (length(pincode) <= 20) NOT VALID;

-- =============================================================================
-- Validation
-- NOTE: We are NOT validating existing rows to prevent the migration from failing
-- if legacy dirty data exists. The NOT VALID flag ensures the constraint is enforced 
-- for all NEW inserts and updates, which completely neutralizes future attacks.
-- =============================================================================

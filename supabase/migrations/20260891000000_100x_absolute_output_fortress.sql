-- =============================================================================
-- Phase 36: Absolute Traceability & Output Storage Fortress (Phase 4)
-- Description:
--   Injects safe, non-blocking length constraints into withdrawals, notifications,
--   app_logs, audit_logs, and admin_activity_log to prevent cascading logic 
--   failures and server disk exhaustion from out-of-bounds payloads.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. WITHDRAWALS
-- -----------------------------------------------------------------------------
ALTER TABLE public.withdrawals
  ADD CONSTRAINT chk_withdrawals_upi_id_len CHECK (length(upi_id) <= 100) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_bank_acc_len CHECK (length(bank_account_number) <= 100) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_bank_ifsc_len CHECK (length(bank_ifsc) <= 100) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_bank_holder_len CHECK (length(bank_account_holder) <= 100) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_rzp_payout_id_len CHECK (length(razorpay_payout_id) <= 100) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_txn_id_len CHECK (length(transaction_id) <= 100) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_admin_note_len CHECK (length(admin_note) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_withdrawals_admin_notes_len CHECK (length(admin_notes) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 2. NOTIFICATIONS
-- -----------------------------------------------------------------------------
ALTER TABLE public.notifications
  ADD CONSTRAINT chk_notifs_key_len CHECK (length(notif_key) <= 255) NOT VALID,
  ADD CONSTRAINT chk_notifs_title_len CHECK (length(title) <= 255) NOT VALID,
  ADD CONSTRAINT chk_notifs_body_len CHECK (length(body) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 3. APP_LOGS
-- -----------------------------------------------------------------------------
ALTER TABLE public.app_logs
  ADD CONSTRAINT chk_applogs_message_len CHECK (length(message) <= 5000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 4. AUDIT_LOGS
-- -----------------------------------------------------------------------------
ALTER TABLE public.audit_logs
  ADD CONSTRAINT chk_audit_logs_actor_role_len CHECK (length(actor_role) <= 100) NOT VALID,
  ADD CONSTRAINT chk_audit_logs_action_len CHECK (length(action) <= 255) NOT VALID,
  ADD CONSTRAINT chk_audit_logs_entity_type_len CHECK (length(entity_type) <= 255) NOT VALID,
  ADD CONSTRAINT chk_audit_logs_device_info_len CHECK (length(device_info) <= 255) NOT VALID,
  ADD CONSTRAINT chk_audit_logs_metadata_len CHECK (pg_column_size(metadata) <= 10240) NOT VALID;

-- -----------------------------------------------------------------------------
-- 5. ADMIN_ACTIVITY_LOG
-- -----------------------------------------------------------------------------
ALTER TABLE public.admin_activity_log
  ADD CONSTRAINT chk_admin_act_action_len CHECK (length(action) <= 255) NOT VALID,
  ADD CONSTRAINT chk_admin_act_target_type_len CHECK (length(target_type) <= 255) NOT VALID,
  ADD CONSTRAINT chk_admin_act_target_id_len CHECK (length(target_id) <= 255) NOT VALID,
  ADD CONSTRAINT chk_admin_act_details_len CHECK (pg_column_size(details) <= 10240) NOT VALID;

-- =============================================================================
-- Validation
-- NOTE: We are NOT validating existing rows to prevent the migration from failing
-- if legacy dirty data exists. The NOT VALID flag ensures the constraint is enforced 
-- for all NEW inserts and updates, which completely neutralizes future attacks.
-- =============================================================================

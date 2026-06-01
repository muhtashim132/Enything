// =============================================================================
// process-payout — Supabase Edge Function
// =============================================================================
// Called by Admin when approving a seller or rider withdrawal request.
// Uses Razorpay X (Payouts API) to transfer funds to the user's UPI / bank.
//
// Razorpay X must be activated separately in the Razorpay Dashboard.
// Required secrets:
//   RAZORPAY_X_KEY_ID       — Razorpay X account key
//   RAZORPAY_X_KEY_SECRET   — Razorpay X account secret
//   RAZORPAY_X_ACCOUNT_NUMBER — Your Razorpay X virtual account number
//
// Request body:
//   { "withdrawal_id": "<uuid>" }
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Authenticate and verify admin ──────────────────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } }
    );

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Verify admin status
    const { data: adminData } = await supabaseAdmin
      .from("admin_users")
      .select("id, is_active")
      .eq("id", user.id)
      .eq("is_active", true)
      .maybeSingle();

    if (!adminData) {
      return new Response(JSON.stringify({ error: "Admin access required" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // ── 2. Load withdrawal request ────────────────────────────────────────────
    const { withdrawal_id } = await req.json();

    const { data: withdrawal, error: fetchError } = await supabaseAdmin
      .from("withdrawals")
      .select("*")
      .eq("id", withdrawal_id)
      .maybeSingle();

    if (fetchError || !withdrawal) {
      return new Response(JSON.stringify({ error: "Withdrawal request not found" }), {
        status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    if (withdrawal.status !== "pending") {
      return new Response(JSON.stringify({ error: `Withdrawal already ${withdrawal.status}` }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // ── 3. Razorpay X Payout ─────────────────────────────────────────────────
    const keyId     = Deno.env.get("RAZORPAY_X_KEY_ID") ?? "";
    const keySecret = Deno.env.get("RAZORPAY_X_KEY_SECRET") ?? "";
    const accountNumber = Deno.env.get("RAZORPAY_X_ACCOUNT_NUMBER") ?? "";

    if (!keyId || !keySecret || !accountNumber) {
      console.error("Razorpay X credentials not configured.");
      return new Response(JSON.stringify({ error: "Payout gateway not configured. Contact super admin." }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const authHeader = "Basic " + btoa(`${keyId}:${keySecret}`);
    const amountInPaise = Math.round(Number(withdrawal.amount) * 100);

    // Build fund account based on payout destination
    const fundAccount = withdrawal.upi_id
      ? {
          account_type: "vpa",
          vpa: { address: withdrawal.upi_id },
        }
      : {
          account_type: "bank_account",
          bank_account: {
            name:           withdrawal.bank_account_holder,
            ifsc:           withdrawal.bank_ifsc,
            account_number: withdrawal.bank_account_number,
          },
        };

    // Create payout via Razorpay X
    const payoutRes = await fetch("https://api.razorpay.com/v1/payouts", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": authHeader,
        "X-Payout-Idempotency": withdrawal_id, // prevents duplicate payouts
      },
      body: JSON.stringify({
        account_number: accountNumber,
        amount: amountInPaise,
        currency: "INR",
        mode: withdrawal.upi_id ? "UPI" : "NEFT",
        purpose: "payout",
        fund_account: {
          ...fundAccount,
          contact: {
            name:         "Zappy Partner",
            type:         withdrawal.user_role === "seller" ? "vendor" : "employee",
            reference_id: withdrawal.user_id,
          },
        },
        notes: {
          withdrawal_id: withdrawal_id,
          user_id:       withdrawal.user_id,
          platform:      "zappy_mobile",
        },
      }),
    });

    const payoutData = await payoutRes.json();

    if (!payoutRes.ok) {
      console.error("Razorpay X payout failed:", payoutData);
      // Mark as rejected so admin is notified
      await supabaseAdmin.from("withdrawals").update({
        status:     "rejected",
        admin_note: `Payout failed: ${payoutData.error?.description ?? "Unknown error"}`,
      }).eq("id", withdrawal_id);

      return new Response(JSON.stringify({ error: payoutData.error?.description ?? "Payout failed" }), {
        status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // ── 4. Update withdrawal record ───────────────────────────────────────────
    await supabaseAdmin.from("withdrawals").update({
      status:              "processed",
      razorpay_payout_id:  payoutData.id,
      processed_at:        new Date().toISOString(),
    }).eq("id", withdrawal_id);

    console.log(`Payout ${payoutData.id} processed for withdrawal ${withdrawal_id}.`);
    return new Response(
      JSON.stringify({ success: true, payout_id: payoutData.id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error("process-payout exception:", err);
    return new Response(
      JSON.stringify({ error: err.message ?? "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

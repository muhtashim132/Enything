// =============================================================================
// verify-razorpay-payment — Supabase Edge Function
// =============================================================================
// Called by Flutter AFTER Razorpay payment success callback.
// MUST be called before any order is written to the database.
//
// Flow:
//  1. Receive razorpay_payment_id + razorpay_order_id + razorpay_signature.
//  2. Verify the HMAC-SHA256 signature using RAZORPAY_KEY_SECRET.
//  3. Capture the payment via Razorpay API (marks it as captured).
//  4. Return { verified: true } — Flutter then calls its create-order logic.
//
// Request body:
//   {
//     "razorpay_payment_id": "pay_XXXX",
//     "razorpay_order_id":   "order_XXXX",
//     "razorpay_signature":  "<hmac>",
//   }
//
// Response body (success):  { "verified": true, "payment_id": "pay_XXXX" }
// Response body (failure):  { "verified": false, "error": "Signature mismatch" }
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { createHmac } from "node:crypto";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Authenticate the calling user ──────────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ verified: false, error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Parse body ─────────────────────────────────────────────────────────
    const { razorpay_payment_id, razorpay_order_id, razorpay_signature } = await req.json();

    if (!razorpay_payment_id || !razorpay_order_id || !razorpay_signature) {
      return new Response(
        JSON.stringify({ verified: false, error: "Missing required payment fields." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 3. Load Key Secret ────────────────────────────────────────────────────
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
    if (!keySecret) {
      console.error("RAZORPAY_KEY_SECRET not configured.");
      return new Response(
        JSON.stringify({ verified: false, error: "Gateway not configured." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 4. Verify HMAC-SHA256 Signature ───────────────────────────────────────
    // Razorpay signs: razorpay_order_id + "|" + razorpay_payment_id
    const message = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expectedSignature = createHmac("sha256", keySecret).update(message).digest("hex");

    if (expectedSignature !== razorpay_signature) {
      console.warn(`Signature mismatch for payment ${razorpay_payment_id}. Possible fraud attempt.`);
      return new Response(
        JSON.stringify({ verified: false, error: "Payment signature verification failed." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 5. Capture the payment (optional but recommended for manual-capture accounts) ──
    const keyId     = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
    const authHeader = "Basic " + btoa(`${keyId}:${keySecret}`);

    // Check payment status first
    const paymentCheckRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: { "Authorization": authHeader },
    });
    const paymentData = await paymentCheckRes.json();

    // Only capture if in "authorized" state (for manual capture accounts)
    if (paymentData.status === "authorized") {
      await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}/capture`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": authHeader },
        body: JSON.stringify({ amount: paymentData.amount, currency: paymentData.currency }),
      });
    }

    // ── 6. Return success ─────────────────────────────────────────────────────
    console.log(`Payment ${razorpay_payment_id} verified successfully for user ${user.id}.`);
    return new Response(
      JSON.stringify({ verified: true, payment_id: razorpay_payment_id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error("verify-razorpay-payment exception:", err);
    return new Response(
      JSON.stringify({ verified: false, error: err.message ?? "Internal error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

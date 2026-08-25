// =============================================================================
// verify-razorpay-payment — Supabase Edge Function (100x Hardened)
// =============================================================================
// Called by Flutter AFTER Razorpay payment success callback.
// Verifies HMAC-SHA256 signature, validates payment status & amount with
// Razorpay API, captures authorized payments, and updates DB status atomically.
//
// Request body:
//   {
//     "razorpay_payment_id": "pay_XXXX",
//     "razorpay_order_id":   "order_XXXX",
//     "razorpay_signature":  "<hmac>",
//     "order_id":            "<uuid>",
//     "cart_group_id":       "<uuid>"
//   }
// =============================================================================
// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { createHmac, timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";

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
        JSON.stringify({ verified: false, error: "Unauthorized: Active user session required." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Parse body ─────────────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const { razorpay_payment_id, razorpay_order_id, razorpay_signature, order_id, cart_group_id } = body;

    if (!razorpay_payment_id || !razorpay_order_id || !razorpay_signature) {
      return new Response(
        JSON.stringify({ verified: false, error: "Missing required payment verification parameters." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!order_id && !cart_group_id) {
      return new Response(
        JSON.stringify({ verified: false, error: "Missing order_id or cart_group_id reference." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 3. Load Gateway Secrets ───────────────────────────────────────────────
    const keyId     = (Deno.env.get("RAZORPAY_KEY_ID") ?? "").trim();
    const keySecret = (Deno.env.get("RAZORPAY_KEY_SECRET") ?? "").trim();

    if (!keyId || !keySecret) {
      console.error("RAZORPAY_KEY_ID or RAZORPAY_KEY_SECRET not configured.");
      return new Response(
        JSON.stringify({ verified: false, error: "Payment gateway credentials not configured on server." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 4. Verify HMAC-SHA256 Signature (Timing-Safe) ─────────────────────────
    const message = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expectedSignature = createHmac("sha256", keySecret).update(message).digest("hex");

    const expectedBuf = Buffer.from(expectedSignature, "utf8");
    const receivedBuf = Buffer.from(String(razorpay_signature), "utf8");

    const isSignatureValid =
      expectedBuf.length === receivedBuf.length &&
      timingSafeEqual(expectedBuf, receivedBuf);

    if (!isSignatureValid) {
      console.warn(`Signature mismatch for payment ${razorpay_payment_id}. Fraud attempt blocked.`);
      return new Response(
        JSON.stringify({ verified: false, error: "Cryptographic payment signature verification failed." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 5. Setup Admin Client & Validate Expected Amount ───────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    let dbAmount = 0;
    if (cart_group_id) {
      const { data: orders, error } = await supabaseAdmin
        .from('orders')
        .select('id, grand_total_collected, status, customer_id')
        .eq('cart_group_id', cart_group_id)
        .eq('status', 'awaiting_payment');

      if (error) throw new Error("Database error: " + JSON.stringify(error));
      if (!orders || orders.length === 0) {
        throw new Error("No awaiting_payment orders found for cart_group_id: " + cart_group_id);
      }

      if (orders.some(o => o.customer_id !== user.id)) {
        return new Response(
          JSON.stringify({ verified: false, error: "Unauthorized order access." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      dbAmount = orders.reduce((sum, o) => sum + (Number(o.grand_total_collected) || 0), 0);
    } else {
      const { data: order, error } = await supabaseAdmin
        .from('orders')
        .select('id, grand_total_collected, status, customer_id')
        .eq('id', order_id)
        .maybeSingle();

      if (error || !order) throw new Error("Order not found");
      if (order.customer_id !== user.id) {
        return new Response(
          JSON.stringify({ verified: false, error: "Unauthorized order access." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      dbAmount = Number(order.grand_total_collected) || 0;
    }

    const expectedPaise = Math.round(dbAmount * 100);

    // ── 6. Query Razorpay API for Authoritative Status & Amount ───────────────
    const authHeader = "Basic " + btoa(`${keyId}:${keySecret}`);

    const paymentCheckRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: { "Authorization": authHeader },
    });

    const paymentData = await paymentCheckRes.json();

    if (!paymentCheckRes.ok || !paymentData?.status) {
      console.error("Failed to query Razorpay payment status:", paymentData);
      return new Response(
        JSON.stringify({ verified: false, error: "Could not verify payment status with payment gateway." }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Strict Status Validation: Reject failed / created / refunded
    if (paymentData.status !== "authorized" && paymentData.status !== "captured") {
      console.warn(`Payment ${razorpay_payment_id} is in invalid status '${paymentData.status}'. Rejecting confirmation.`);
      return new Response(
        JSON.stringify({ verified: false, error: `Payment is currently '${paymentData.status}'. Only captured or authorized payments can be confirmed.` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Amount validation with safe margin
    if (paymentData.amount < expectedPaise - 100) {
      console.warn(`Payment amount mismatch. Gateway Paid: ${paymentData.amount} paise, Expected: ${expectedPaise} paise.`);
      return new Response(
        JSON.stringify({ verified: false, error: "Payment amount does not match the required order total." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Capture payment if authorized
    if (paymentData.status === "authorized") {
      const captureRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}/capture`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": authHeader },
        body: JSON.stringify({ amount: paymentData.amount, currency: paymentData.currency || "INR" }),
      });
      const captureData = await captureRes.json();
      if (!captureRes.ok) {
        console.error("Failed to capture payment on Razorpay:", captureData);
        return new Response(
          JSON.stringify({ verified: false, error: "Payment authorization succeeded but capture failed." }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ── 7. Atomic DB Order Confirmation via RPC (service_role) ────────────────
    const { error: rpcError } = await supabaseAdmin.rpc('client_confirm_payment', {
      p_order_id: order_id || null,
      p_cart_group_id: cart_group_id || null,
      p_razorpay_payment_id: razorpay_payment_id,
      p_razorpay_order_id: razorpay_order_id,
    });

    if (rpcError) {
      console.error("RPC client_confirm_payment error:", rpcError);
      throw new Error("Failed to confirm order in database.");
    }

    console.log(`Payment ${razorpay_payment_id} successfully verified & captured for user ${user.id}.`);
    return new Response(
      JSON.stringify({ verified: true, payment_id: razorpay_payment_id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error("verify-razorpay-payment exception:", err);
    return new Response(
      JSON.stringify({ verified: false, error: err.message ?? "Internal error verifying payment." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

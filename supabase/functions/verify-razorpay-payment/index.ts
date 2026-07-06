// =============================================================================
// verify-razorpay-payment — Supabase Edge Function
// =============================================================================
// Called by Flutter AFTER Razorpay payment success callback.
// MUST be called before any order is written to the database.
//
// Flow:
//  1. Receive razorpay_payment_id + razorpay_order_id + razorpay_signature + order_id/cart_group_id.
//  2. Verify the HMAC-SHA256 signature using RAZORPAY_KEY_SECRET.
//  3. Fetch expected amount from DB (grand_total_collected).
//  4. Capture the payment via Razorpay API (marks it as captured).
//  5. Confirm the order via RPC using service_role key to prevent client spoofing.
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
    const { razorpay_payment_id, razorpay_order_id, razorpay_signature, order_id, cart_group_id } = await req.json();

    if (!razorpay_payment_id || !razorpay_order_id || !razorpay_signature) {
      return new Response(
        JSON.stringify({ verified: false, error: "Missing required payment fields." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!order_id && !cart_group_id) {
      return new Response(
        JSON.stringify({ verified: false, error: "Missing order or cart group reference." }),
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
    const message = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expectedSignature = createHmac("sha256", keySecret).update(message).digest("hex");

    if (expectedSignature !== razorpay_signature) {
      console.warn(`Signature mismatch for payment ${razorpay_payment_id}. Possible fraud attempt.`);
      return new Response(
        JSON.stringify({ verified: false, error: "Payment signature verification failed." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 5. Setup Admin Client & Validate Amount ───────────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    let dbAmount = 0;
    if (cart_group_id) {
      const { data: orders, error } = await supabaseAdmin
        .from('orders')
        .select('grand_total_collected, status, customer_id')
        .eq('cart_group_id', cart_group_id);
      
      if (error || !orders || orders.length === 0) throw new Error("Orders not found");
      if (orders[0].customer_id !== user.id) throw new Error("Unauthorized order access");
      
      dbAmount = orders.reduce((sum, o) => sum + (o.grand_total_collected || 0), 0);
    } else {
      const { data: order, error } = await supabaseAdmin
        .from('orders')
        .select('grand_total_collected, status, customer_id')
        .eq('id', order_id)
        .maybeSingle();

      if (error || !order) throw new Error("Order not found");
      if (order.customer_id !== user.id) throw new Error("Unauthorized order access");

      dbAmount = order.grand_total_collected || 0;
    }

    const expectedPaise = Math.round(dbAmount * 100);

    // ── 6. Capture the payment ────────────────────────────────────────────────
    const keyId     = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
    const authHeader = "Basic " + btoa(`${keyId}:${keySecret}`);

    const paymentCheckRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: { "Authorization": authHeader },
    });
    const paymentData = await paymentCheckRes.json();

    if (paymentData.amount < expectedPaise - 100) { // allow 1 INR rounding diff just in case
      console.warn(`Payment amount mismatch. Paid: ${paymentData.amount}, Expected: ${expectedPaise}`);
      return new Response(
        JSON.stringify({ verified: false, error: "Payment amount does not match order total." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (paymentData.status === "authorized") {
      await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}/capture`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": authHeader },
        body: JSON.stringify({ amount: paymentData.amount, currency: paymentData.currency }),
      });
    }

    // ── 7. Confirm Order in DB via RPC using Admin ────────────────────────────
    const { error: rpcError } = await supabaseAdmin.rpc('client_confirm_payment', {
      p_order_id: order_id || null,
      p_cart_group_id: cart_group_id || null,
      p_razorpay_payment_id: razorpay_payment_id,
      p_razorpay_order_id: razorpay_order_id
    });

    if (rpcError) {
      console.error("RPC confirm payment error:", rpcError);
      throw new Error("Failed to confirm order in database.");
    }

    console.log(`Payment ${razorpay_payment_id} verified and order confirmed successfully for user ${user.id}.`);
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

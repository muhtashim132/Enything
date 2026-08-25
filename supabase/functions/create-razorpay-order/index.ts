// =============================================================================
// create-razorpay-order — Supabase Edge Function (100x Hardened)
// =============================================================================
// Called by the Flutter app BEFORE opening the Razorpay payment sheet.
// Creates a Razorpay Order server-side so that:
//  • The Key Secret never leaves the server.
//  • Payments without a server-issued order_id cannot be spoofed.
//  • All calculations are verified against the authoritative database state.
//
// Request body:
//   { "order_id": "<uuid>", "cart_group_id": "<uuid>", "currency": "INR", "receipt": "..." }
//
// Response body:
//   { "id": "order_XXXXXX", "amount": 24900, "currency": "INR" }
// =============================================================================
// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Handle CORS preflight
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
        JSON.stringify({ error: "Unauthorized: Active session required." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Parse request body ─────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const { order_id, cart_group_id, currency = "INR", receipt } = body;

    if (!order_id && !cart_group_id) {
      return new Response(
        JSON.stringify({ error: "Missing order_id or cart_group_id." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 3. Setup Admin Client & Authoritative Amount Resolution ───────────────
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    let dbAmount = 0;
    if (cart_group_id) {
      // 100x FIX: Strictly select orders awaiting payment for this cart group
      const { data: orders, error } = await supabaseAdmin
        .from('orders')
        .select('id, grand_total_collected, customer_id, status')
        .eq('cart_group_id', cart_group_id)
        .eq('status', 'awaiting_payment');

      if (error) {
        console.error("Database query error:", error);
        throw new Error("Database error retrieving orders.");
      }

      if (!orders || orders.length === 0) {
        return new Response(
          JSON.stringify({ error: "No active orders awaiting payment found in this cart." }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 100x Fortress: Customer ID check across ALL orders in cart
      if (orders.some(o => o.customer_id !== user.id)) {
        console.warn(`Unauthorized cart access attempt by user ${user.id} on cart ${cart_group_id}`);
        return new Response(
          JSON.stringify({ error: "Unauthorized order access." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      dbAmount = orders.reduce((sum, o) => sum + (Number(o.grand_total_collected) || 0), 0);
    } else {
      const { data: order, error } = await supabaseAdmin
        .from('orders')
        .select('id, grand_total_collected, customer_id, status')
        .eq('id', order_id)
        .maybeSingle();

      if (error || !order) {
        return new Response(
          JSON.stringify({ error: "Order not found." }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (order.customer_id !== user.id) {
        return new Response(
          JSON.stringify({ error: "Unauthorized order access." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (order.status !== 'awaiting_payment') {
        return new Response(
          JSON.stringify({ error: `Order is in status '${order.status}', not 'awaiting_payment'.` }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      dbAmount = Number(order.grand_total_collected) || 0;
    }

    // 100x Precision: Convert decimal rupees to exact integer paise
    const amount = Math.round(dbAmount * 100);

    if (amount < 100) {
      return new Response(
        JSON.stringify({ error: "Invalid payment amount. Minimum order value is ₹1.00 (100 paise)." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 4. Razorpay Credentials ───────────────────────────────────────────────
    const keyId     = (Deno.env.get("RAZORPAY_KEY_ID") ?? "").trim();
    const keySecret = (Deno.env.get("RAZORPAY_KEY_SECRET") ?? "").trim();

    if (!keyId || !keySecret) {
      console.error("RAZORPAY_KEY_ID or RAZORPAY_KEY_SECRET not configured in Supabase secrets.");
      return new Response(
        JSON.stringify({ error: "Payment gateway credentials not configured." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const authHeader = "Basic " + btoa(`${keyId}:${keySecret}`);

    // Razorpay receipt length limit is 40 characters
    const safeReceipt = (receipt ? String(receipt) : `eny_${user.id.slice(0, 8)}_${Date.now()}`).slice(0, 40);

    // ── 5. Create Razorpay Order via API ──────────────────────────────────────
    const razorpayPayload = {
      amount,
      currency: currency.toUpperCase(),
      receipt: safeReceipt,
      notes: {
        user_id: user.id,
        order_id: String(order_id || "").slice(0, 50),
        cart_group_id: String(cart_group_id || "").slice(0, 50),
        platform: "enything_mobile",
      },
    };

    const razorpayResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": authHeader,
      },
      body: JSON.stringify(razorpayPayload),
    });

    const orderData = await razorpayResponse.json();

    if (!razorpayResponse.ok) {
      console.error("Razorpay order creation failed:", orderData);
      return new Response(
        JSON.stringify({ error: orderData?.error?.description ?? "Failed to create payment order on gateway." }),
        { status: razorpayResponse.status >= 500 ? 502 : 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 6. Persist razorpay_order_id in DB for Correlation ────────────────────
    if (cart_group_id) {
      await supabaseAdmin
        .from('orders')
        .update({ razorpay_order_id: orderData.id })
        .eq('cart_group_id', cart_group_id)
        .eq('status', 'awaiting_payment');
    } else if (order_id) {
      await supabaseAdmin
        .from('orders')
        .update({ razorpay_order_id: orderData.id })
        .eq('id', order_id)
        .eq('status', 'awaiting_payment');
    }

    // ── 7. Return Order details to Flutter ────────────────────────────────────
    return new Response(
      JSON.stringify({
        id: orderData.id,
        amount: orderData.amount,
        currency: orderData.currency,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error("create-razorpay-order unhandled exception:", err);
    return new Response(
      JSON.stringify({ error: err.message ?? "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

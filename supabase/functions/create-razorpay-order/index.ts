// =============================================================================
// create-razorpay-order — Supabase Edge Function
// =============================================================================
// Called by the Flutter app BEFORE opening the Razorpay payment sheet.
// Creates a Razorpay Order server-side so that:
//  • The Key Secret never leaves the server.
//  • Payments without a server-issued order_id are auto-refunded by Razorpay.
//
// Request body:
//   { "amount": 24900, "currency": "INR", "receipt": "zappy_<uuid>" }
//
// Response body:
//   { "id": "order_XXXXXX", "amount": 24900, "currency": "INR" }
// =============================================================================

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
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Parse request body ─────────────────────────────────────────────────
    const { amount, currency = "INR", receipt } = await req.json();

    if (!amount || typeof amount !== "number" || amount < 100) {
      return new Response(
        JSON.stringify({ error: "Invalid amount. Must be in paise (minimum 100 = ₹1)." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 3. Razorpay credentials ───────────────────────────────────────────────
    const keyId     = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

    if (!keyId || !keySecret) {
      console.error("RAZORPAY_KEY_ID or RAZORPAY_KEY_SECRET not set in Supabase secrets.");
      return new Response(
        JSON.stringify({ error: "Payment gateway not configured." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const authHeader = "Basic " + btoa(`${keyId}:${keySecret}`);

    // ── 4. Create Razorpay Order ──────────────────────────────────────────────
    const razorpayResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": authHeader,
      },
      body: JSON.stringify({
        amount,           // in paise
        currency,
        receipt: receipt ?? `zappy_${user.id}_${Date.now()}`,
        notes: {
          user_id: user.id,
          platform: "zappy_mobile",
        },
      }),
    });

    const order = await razorpayResponse.json();

    if (!razorpayResponse.ok) {
      console.error("Razorpay order creation failed:", order);
      return new Response(
        JSON.stringify({ error: order?.error?.description ?? "Failed to create payment order." }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 5. Return Razorpay order to Flutter ───────────────────────────────────
    return new Response(
      JSON.stringify({ id: order.id, amount: order.amount, currency: order.currency }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error("create-razorpay-order exception:", err);
    return new Response(
      JSON.stringify({ error: err.message ?? "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

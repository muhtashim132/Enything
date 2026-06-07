// =============================================================================
// razorpay-webhook — Supabase Edge Function
// =============================================================================
// Registered as a webhook endpoint in the Razorpay Dashboard.
// Acts as an async backup for payment confirmation — critical for cases where:
//   • The user closed the app before the success callback fired.
//   • Network issues prevented the Flutter app from calling verify-payment.
//
// Register this URL in Razorpay Dashboard → Settings → Webhooks:
//   https://<project-ref>.supabase.co/functions/v1/razorpay-webhook
//
// Enable events:
//   ✅ payment.captured   → Confirm order
//   ✅ payment.failed     → Mark order as payment_failed
//   ✅ order.paid         → Redundant backup
//   ✅ refund.created     → Log refund
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { createHmac } from "node:crypto";

Deno.serve(async (req) => {
  try {
    const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";
    const rawBody = await req.text();

    // ── 1. Validate webhook signature ─────────────────────────────────────────
    const receivedSignature = req.headers.get("X-Razorpay-Signature") ?? "";
    const expectedSignature  = createHmac("sha256", webhookSecret).update(rawBody).digest("hex");

    if (webhookSecret && receivedSignature !== expectedSignature) {
      console.warn("Webhook signature mismatch — possible spoofing attempt.");
      return new Response("Forbidden", { status: 403 });
    }

    const event = JSON.parse(rawBody);
    const eventId   = event.id ?? "";
    const eventType = event.event ?? "";
    const payload   = event.payload;

    console.log(`Webhook received: ${eventType} (id: ${eventId})`);

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ── 2. Handle payment.captured ────────────────────────────────────────────
    if (eventType === "payment.captured") {
      const payment   = payload?.payment?.entity;
      const paymentId = payment?.id;
      const orderId   = payment?.order_id;
      const notes     = payment?.notes ?? {};

      if (!paymentId || !orderId) {
        return new Response("Missing payment data", { status: 200 });
      }

      // Idempotency: check if this payment_id is already recorded
      const { data: existing } = await supabaseAdmin
        .from("orders")
        .select("id, status")
        .eq("razorpay_payment_id", paymentId)
        .maybeSingle();

      if (existing) {
        console.log(`Payment ${paymentId} already processed. Skipping.`);
        return new Response("Already processed", { status: 200 });
      }

      // If order exists with razorpay_order_id but no payment_id yet, confirm it
      const { data: pendingOrder } = await supabaseAdmin
        .from("orders")
        .select("id, status")
        .eq("razorpay_order_id", orderId)
        .maybeSingle();

      if (pendingOrder && pendingOrder.status === "pending_payment") {
        await supabaseAdmin
          .from("orders")
          .update({
            razorpay_payment_id: paymentId,
            status: "placed",
            payment_status: "captured",
          })
          .eq("id", pendingOrder.id);

        console.log(`Order ${pendingOrder.id} confirmed via webhook payment ${paymentId}.`);
      }
    }

    // ── 3. Handle payment.failed ─────────────────────────────────────────────
    if (eventType === "payment.failed") {
      const payment = payload?.payment?.entity;
      const orderId = payment?.order_id;

      if (orderId) {
        const { data: pendingOrder } = await supabaseAdmin
          .from("orders")
          .select("id, status")
          .eq("razorpay_order_id", orderId)
          .maybeSingle();

        if (pendingOrder && pendingOrder.status === "pending_payment") {
          await supabaseAdmin
            .from("orders")
            .update({ status: "payment_failed", payment_status: "failed" })
            .eq("id", pendingOrder.id);

          console.log(`Order ${pendingOrder.id} marked as payment_failed via webhook.`);
        }
      }
    }

    // ── 4. Handle refund.created ─────────────────────────────────────────────
    if (eventType === "refund.created") {
      const refund    = payload?.refund?.entity;
      const paymentId = refund?.payment_id;
      const refundId  = refund?.id;

      if (paymentId && refundId) {
        // Only update if not already processed
        const { data: order } = await supabaseAdmin
          .from("orders")
          .select("id, refund_id")
          .eq("razorpay_payment_id", paymentId)
          .maybeSingle();

        if (order && !order.refund_id) {
          await supabaseAdmin
            .from("orders")
            .update({ refund_id: refundId, refund_status: "processed" })
            .eq("id", order.id);

          console.log(`Refund ${refundId} logged for order ${order.id} via webhook.`);
        }
      }
    }

    // ── 5. Acknowledge Razorpay (must be within 5 seconds) ───────────────────
    return new Response("OK", { status: 200 });

  } catch (err: any) {
    console.error("razorpay-webhook exception:", err);
    // Still return 200 to prevent Razorpay from retrying endlessly
    return new Response("Internal error (logged)", { status: 200 });
  }
});

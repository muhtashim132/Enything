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
        .limit(1)
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
        .limit(1)
        .maybeSingle();

      if (pendingOrder && pendingOrder.status === "awaiting_payment") {
        await supabaseAdmin
          .from("orders")
          .update({
            razorpay_payment_id: paymentId,
            status: "confirmed",
            payment_status: "captured",
          })
          .eq("razorpay_order_id", orderId); // S1: Using razorpay_order_id handles multi-shop cart group!

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
          .limit(1)
          .maybeSingle();

        if (pendingOrder && pendingOrder.status === "awaiting_payment") {
          await supabaseAdmin
            .from("orders")
            .update({ status: "cancelled", cancelled_reason: "payment_failed", payment_status: "failed" })
            .eq("razorpay_order_id", orderId);

          console.log(`Order ${pendingOrder.id} marked as cancelled (payment_failed) via webhook.`);
        }
      }
    }

    // ── 4. Handle refund.created ─────────────────────────────────────────────
    if (eventType === "refund.created") {
      const refund    = payload?.refund?.entity;
      const paymentId = refund?.payment_id;
      const refundId  = refund?.id;

      if (paymentId && refundId) {
        // Fetch all orders associated with this payment (multi-shop support)
        const { data: orders } = await supabaseAdmin
          .from("orders")
          .select("id, refund_id, refund_status, status")
          .eq("razorpay_payment_id", paymentId);

        if (orders && orders.length > 0) {
          // Update all orders that haven't been marked as refunded yet
          // 100x FIX: Only target orders that are explicitly marked for refunding or are completely cancelled
          const terminalStates = ['cancelled', 'seller_rejected', 'payment_failed', 'timeout', 'shop_dispute_cancel', 'verification_failed'];
          const idsToUpdate = orders
            .filter((o: any) => !o.refund_id && (o.refund_status === 'processing' || terminalStates.includes(o.status)))
            .map((o: any) => o.id);
          
          if (idsToUpdate.length > 0) {
            await supabaseAdmin
              .from("orders")
              .update({ refund_id: refundId, refund_status: "processed" })
              .in("id", idsToUpdate);

            console.log(`Refund ${refundId} logged for ${idsToUpdate.length} orders via webhook.`);
          } else {
            console.log(`Refund ${refundId} already logged for all orders associated with payment ${paymentId}.`);
          }
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

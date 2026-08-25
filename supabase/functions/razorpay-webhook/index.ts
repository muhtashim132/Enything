// =============================================================================
// razorpay-webhook — Supabase Edge Function (100x Hardened)
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
//   ✅ order.paid         → Redundant backup
//   ✅ payment.failed     → Mark order as payment_failed
//   ✅ refund.created     → Log refund
//   ✅ refund.processed   → Log refund
//   ✅ refund.failed      → Mark refund as failed
// =============================================================================

// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { createHmac, timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-razorpay-signature",
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const webhookSecret = (Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "").trim();
    const rawBody = await req.text();

    // ── 1. Validate webhook signature ─────────────────────────────────────────
    const receivedSignature = req.headers.get("X-Razorpay-Signature") ?? "";
    if (webhookSecret) {
      const expectedSignature = createHmac("sha256", webhookSecret).update(rawBody).digest("hex");
      const expBuf = Buffer.from(expectedSignature, "utf8");
      const recBuf = Buffer.from(receivedSignature, "utf8");

      if (expBuf.length !== recBuf.length || !timingSafeEqual(expBuf, recBuf)) {
        console.warn("Webhook signature mismatch — possible spoofing attempt.");
        return new Response("Forbidden", { status: 403, headers: corsHeaders });
      }
    }

    if (!rawBody || rawBody.trim() === "") {
      return new Response("Empty body", { status: 200, headers: corsHeaders });
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

    // ── 2. Handle payment.captured & order.paid ───────────────────────────────
    if (eventType === "payment.captured" || eventType === "order.paid") {
      const payment   = payload?.payment?.entity;
      const order     = payload?.order?.entity;
      const paymentId = payment?.id;
      const orderId   = payment?.order_id ?? order?.id;
      const notes     = payment?.notes ?? order?.notes ?? {};
      const noteOrderId     = notes?.order_id;
      const noteCartGroupId = notes?.cart_group_id;

      if (!orderId && !paymentId && !noteOrderId && !noteCartGroupId) {
        return new Response("Missing payment data", { status: 200, headers: corsHeaders });
      }

      // Idempotency: check if this payment_id is already recorded
      if (paymentId) {
        const { data: existing } = await supabaseAdmin
          .from("orders")
          .select("id, status")
          .eq("razorpay_payment_id", paymentId)
          .limit(1)
          .maybeSingle();

        if (existing) {
          console.log(`Payment ${paymentId} already processed. Skipping.`);
          return new Response("Already processed", { status: 200, headers: corsHeaders });
        }
      }

      // Find pending order using multiple correlation paths
      let pendingOrder: any = null;

      if (orderId) {
        const { data } = await supabaseAdmin
          .from("orders")
          .select("id, status, cart_group_id, payment_status")
          .eq("razorpay_order_id", orderId)
          .limit(1)
          .maybeSingle();
        pendingOrder = data;
      }

      if (!pendingOrder && noteCartGroupId) {
        const { data } = await supabaseAdmin
          .from("orders")
          .select("id, status, cart_group_id, payment_status")
          .eq("cart_group_id", noteCartGroupId)
          .limit(1)
          .maybeSingle();
        pendingOrder = data;
      }

      if (!pendingOrder && noteOrderId) {
        const { data } = await supabaseAdmin
          .from("orders")
          .select("id, status, cart_group_id, payment_status")
          .eq("id", noteOrderId)
          .limit(1)
          .maybeSingle();
        pendingOrder = data;
      }

      if (pendingOrder && (pendingOrder.status === "awaiting_payment" || pendingOrder.status === "confirmed") && pendingOrder.payment_status !== "captured") {
        const { error: rpcError } = await supabaseAdmin.rpc('client_confirm_payment', {
          p_order_id: pendingOrder.id,
          p_cart_group_id: pendingOrder.cart_group_id || null,
          p_razorpay_payment_id: paymentId ?? `pay_auto_${orderId}`,
          p_razorpay_order_id: orderId ?? pendingOrder.id,
        });

        if (rpcError) {
          console.error(`Error confirming order via client_confirm_payment:`, rpcError);
          // Fallback direct update
          const updatePayload = {
            status: "confirmed",
            payment_status: "captured",
            ...(paymentId ? { razorpay_payment_id: paymentId } : {}),
            ...(orderId ? { razorpay_order_id: orderId } : {}),
          };

          if (pendingOrder.cart_group_id) {
            await supabaseAdmin
              .from("orders")
              .update(updatePayload)
              .eq("cart_group_id", pendingOrder.cart_group_id);
          } else {
            await supabaseAdmin
              .from("orders")
              .update(updatePayload)
              .eq("id", pendingOrder.id);
          }
        }

        console.log(`Order ${pendingOrder.id} confirmed via webhook (${eventType}).`);
      }
    }

    // ── 3. Handle payment.failed ─────────────────────────────────────────────
    if (eventType === "payment.failed") {
      const payment   = payload?.payment?.entity;
      const orderId   = payment?.order_id;
      const notes     = payment?.notes ?? {};
      const noteOrderId     = notes?.order_id;
      const noteCartGroupId = notes?.cart_group_id;

      let pendingOrder: any = null;

      if (orderId) {
        const { data } = await supabaseAdmin
          .from("orders")
          .select("id, status, cart_group_id")
          .eq("razorpay_order_id", orderId)
          .limit(1)
          .maybeSingle();
        pendingOrder = data;
      }

      if (!pendingOrder && noteCartGroupId) {
        const { data } = await supabaseAdmin
          .from("orders")
          .select("id, status, cart_group_id")
          .eq("cart_group_id", noteCartGroupId)
          .limit(1)
          .maybeSingle();
        pendingOrder = data;
      }

      if (!pendingOrder && noteOrderId) {
        const { data } = await supabaseAdmin
          .from("orders")
          .select("id, status, cart_group_id")
          .eq("id", noteOrderId)
          .limit(1)
          .maybeSingle();
        pendingOrder = data;
      }

      if (pendingOrder && pendingOrder.status === "awaiting_payment") {
        const cancelPayload = {
          status: "cancelled",
          cancelled_reason: "payment_failed",
          payment_status: "failed",
        };

        if (pendingOrder.cart_group_id) {
          await supabaseAdmin
            .from("orders")
            .update(cancelPayload)
            .eq("cart_group_id", pendingOrder.cart_group_id);
        } else {
          await supabaseAdmin
            .from("orders")
            .update(cancelPayload)
            .eq("id", pendingOrder.id);
        }

        console.log(`Order ${pendingOrder.id} marked as cancelled (payment_failed) via webhook.`);
      }
    }

    // ── 4. Handle refund.created / refund.processed ───────────────────────────
    if (eventType === "refund.created" || eventType === "refund.processed") {
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

    // ── 5. Handle refund.failed ──────────────────────────────────────────────
    if (eventType === "refund.failed") {
      const refund    = payload?.refund?.entity;
      const paymentId = refund?.payment_id;
      const errorDesc = refund?.error_description ?? "Refund processing failed on payment gateway.";

      if (paymentId) {
        await supabaseAdmin
          .from("orders")
          .update({
            refund_status: "failed",
            rejection_message: `Refund Failed: ${errorDesc}`,
          })
          .eq("razorpay_payment_id", paymentId);

        console.log(`Refund marked as failed for payment ${paymentId}.`);
      }
    }

    // ── 6. Acknowledge Razorpay (must be within 5 seconds) ───────────────────
    return new Response("OK", { status: 200, headers: corsHeaders });

  } catch (err: any) {
    console.error("razorpay-webhook exception:", err);
    // Still return 200 to prevent Razorpay from retrying endlessly
    return new Response("Internal error (logged)", { status: 200, headers: corsHeaders });
  }
});

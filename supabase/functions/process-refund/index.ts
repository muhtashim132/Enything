// @ts-nocheck
// =============================================================================
// process-refund — Supabase Edge Function (100x Hardened)
// =============================================================================
// Runs on the Deno runtime.
// Triggered by Database Webhook on `orders` table (UPDATE events) or direct RPC.
// =============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  try {
    const payload = await req.json().catch(() => ({}));
    let { type, old_record, record } = payload;

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Support direct invocation with order_id
    if (!record && payload.order_id) {
      const { data: fetchedOrder } = await supabaseAdmin
        .from("orders")
        .select("*")
        .eq("id", payload.order_id)
        .maybeSingle();

      if (!fetchedOrder) {
        return new Response(JSON.stringify({ error: "Order not found" }), {
          status: 404,
          headers: { "Content-Type": "application/json" }
        });
      }
      record = fetchedOrder;
      old_record = { ...fetchedOrder, refund_status: "none" };
      type = "UPDATE";
    }

    // We only care about UPDATE events (status changes) or direct invocations
    if (type !== "UPDATE" || !record) {
      return new Response("Ignored: Not an update event", { status: 200 });
    }

    const oldStatus = old_record?.status;
    const newStatus = record?.status;
    const oldRefundStatus = old_record?.refund_status;
    const newRefundStatus = record?.refund_status;

    // Detect if order transitioned into a cancelled/rejected state
    const isRefundableState =
      newStatus === "verification_failed" ||
      newStatus === "seller_rejected" ||
      newStatus === "partner_rejected" ||
      newStatus === "rider_rejected" ||
      newStatus === "cancelled" ||
      newStatus === "shop_dispute_cancel" ||
      newStatus === "timeout" ||
      newStatus === "payment_failed";

    const statusChanged = oldStatus !== newStatus;
    const manualRefundTriggered = oldRefundStatus !== "processing" && newRefundStatus === "processing";

    // 100x FIX: If an Admin explicitly triggers a manual refund, ALWAYS honor it regardless of current order status
    const shouldRefund = (isRefundableState && statusChanged) || manualRefundTriggered || Boolean(payload.order_id);

    if (shouldRefund) {
      console.log(`Order ${record.id} changed to ${newStatus}. Initiating refund check...`);

      // 1. Skip if it was Cash on Delivery
      if (record.payment_method === "cod") {
        console.log("Skipping refund: Order was Cash on Delivery.");
        return new Response("No refund needed: COD order.", { status: 200 });
      }

      // 2. Fetch fresh order from DB to get the latest reallocated grand_total_collected & pending_refund_amount
      const { data: freshOrder } = await supabaseAdmin
        .from("orders")
        .select("status, grand_total, grand_total_collected, pending_refund_amount, total_refunded, razorpay_payment_id, refund_status, refund_id, payment_method")
        .eq("id", record.id)
        .maybeSingle();

      // Defer refund if customer is currently deciding on item swaps/alternatives
      if (freshOrder?.refund_status === "pending_customer_decision") {
        console.log(`Order ${record.id} is pending customer decision. Skipping refund for now.`);
        return new Response("Refund deferred: Waiting for customer decision.", { status: 200 });
      }

      const paymentId = freshOrder?.razorpay_payment_id || record.razorpay_payment_id;
      if (!paymentId) {
        console.warn(`No razorpay_payment_id found for prepaid order ${record.id}`);
        return new Response("Refund skipped: No Razorpay payment ID.", { status: 200 });
      }

      const hasPendingItemRefund = freshOrder?.pending_refund_amount != null && Number(freshOrder.pending_refund_amount) > 0;

      // 3. Skip if already fully refunded (unless there is a new pending item refund or the order status newly changed to terminal)
      const isAlreadyFullyProcessed = freshOrder?.refund_status === "processed" && !hasPendingItemRefund && !statusChanged;
      if (isAlreadyFullyProcessed) {
        return new Response("Refund skipped: Already fully processed.", { status: 200 });
      }

      // 4. Call Razorpay API to issue the refund
      const keyId = (Deno.env.get("RAZORPAY_KEY_ID") || "").trim();
      const keySecret = (Deno.env.get("RAZORPAY_KEY_SECRET") || "").trim();
      if (!keyId || !keySecret) {
        console.error("Razorpay credentials missing in Supabase Edge Secrets for process-refund.");
        return new Response("Payment credentials missing.", { status: 500 });
      }
      const razorpayAuth = btoa(`${keyId}:${keySecret}`);

      // 100x ARCHITECTURAL FIX:
      // Prevent 200% over-refund bug.
      // grand_total_collected is the total money collected for this order.
      // Already refunded amount is tracked in freshOrder?.total_refunded.
      const totalCollected = Number(freshOrder?.grand_total_collected ?? record.grand_total_collected ?? freshOrder?.grand_total ?? record.grand_total ?? 0);
      const totalRefunded = Number(freshOrder?.total_refunded ?? record.total_refunded ?? 0);
      const remainingUnrefunded = Math.max(0, totalCollected - totalRefunded);

      // If the entire order is terminal/cancelled, refund the remaining unrefunded collected amount.
      // If the order is active and only item-level partial decline refund is processing, refund pending_refund_amount (capped by remaining unrefunded).
      const collectedAmount = isRefundableState
        ? remainingUnrefunded
        : (hasPendingItemRefund
          ? Math.min(Number(freshOrder?.pending_refund_amount ?? record.pending_refund_amount ?? 0), remainingUnrefunded)
          : remainingUnrefunded);
      let amountInPaise = Math.round(collectedAmount * 100);

      if (amountInPaise <= 0) {
        console.log(`Order ${record.id} has 0 collected amount. Marking refund as processed internally.`);
        const existingRefId = freshOrder?.refund_id || record.refund_id;
        await supabaseAdmin.from("orders").update({
          refund_status: "processed",
          refund_id: existingRefId || "internal_zero_amount"
        }).eq("id", record.id);

        return new Response("Refund processed internally (zero amount).", { status: 200 });
      }

      // ── 100x Multi-Shop Double Refund Guard ───────────────────────────────
      // Multi-shop cart groups share a single Razorpay payment_id. If 2+ orders
      // in the same cart cancel near-simultaneously, each could issue a full
      // refund totaling 2x+ the payment. Query Razorpay for already-refunded
      // amount and cap this refund to prevent overshoot.
      try {
        const paymentCheckRes = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
          headers: { "Authorization": `Basic ${razorpayAuth}` },
        });
        if (paymentCheckRes.ok) {
          const paymentData = await paymentCheckRes.json();
          const totalPaidPaise = Number(paymentData.amount) || 0;
          const alreadyRefundedPaise = Number(paymentData.amount_refunded) || 0;
          const maxRefundablePaise = totalPaidPaise - alreadyRefundedPaise;

          if (maxRefundablePaise <= 0) {
            console.log(`Payment ${paymentId} already fully refunded (${alreadyRefundedPaise} paise). Marking order ${record.id} as refunded internally.`);
            const existingRefId = freshOrder?.refund_id || record.refund_id;
            await supabaseAdmin.from("orders").update({
              refund_status: "processed",
              refund_id: existingRefId ? `${existingRefId},already_refunded_via_sibling` : `already_refunded_via_sibling`,
              pending_refund_amount: 0.00
            }).eq("id", record.id);
            return new Response("Refund skipped: Payment already fully refunded.", { status: 200 });
          }

          if (amountInPaise > maxRefundablePaise) {
            console.warn(`Capping refund for order ${record.id}: requested ${amountInPaise} paise but only ${maxRefundablePaise} paise available (already refunded ${alreadyRefundedPaise}).`);
            amountInPaise = maxRefundablePaise;
          }
        }
      } catch (capErr) {
        console.warn(`Could not query Razorpay payment status for double-refund guard: ${capErr}. Proceeding with original amount.`);
      }

      const refundResponse = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/refund`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Basic ${razorpayAuth}`
        },
        body: JSON.stringify({
          amount: amountInPaise,
          notes: {
            reason: newStatus || "cancelled",
            order_id: record.id
          }
        })
      });

      const refundData = await refundResponse.json();

      if (!refundResponse.ok) {
        console.error("Razorpay refund failed:", refundData);

        // 100x FIX: Prevent webhook 500 error loops by marking as failed in DB
        await supabaseAdmin.from("orders").update({
          refund_status: "failed",
          rejection_message: `Refund Failed: ${refundData.error?.description || "Unknown Error"}`
        }).eq("id", record.id);

        return new Response(`Razorpay Error: ${refundData.error?.description}`, { status: 200 });
      }

      // 5. Update the Database with the Refund ID & reset pending_refund_amount
      const existingRefundId = freshOrder?.refund_id || record.refund_id;
      const combinedRefundId = existingRefundId && !existingRefundId.includes(refundData.id)
        ? `${existingRefundId},${refundData.id}`
        : refundData.id;

      await supabaseAdmin.from("orders").update({
        refund_id: combinedRefundId,
        refund_status: "processed",
        total_refunded: (Number(freshOrder?.total_refunded) || 0) + (amountInPaise / 100.0),
        pending_refund_amount: 0.00
      }).eq("id", record.id);

      console.log(`Refund ${refundData.id} successfully processed for order ${record.id}.`);
      return new Response(`Refund processed successfully: ${refundData.id}`, { status: 200 });
    }

    return new Response("No refund action required for this status change.", { status: 200 });

  } catch (err: any) {
    console.error("process-refund exception:", err);
    return new Response("Internal error (logged)", { status: 200 });
  }
});

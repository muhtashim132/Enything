// @ts-nocheck
// This file runs on the Deno runtime (Supabase Edge Functions).
// Triggered by a Database Webhook on the `orders` table (UPDATE events).
import { createClient } from "npm:@supabase/supabase-js@2";

// Razorpay API Credentials (ensure these are set in Supabase Edge Secrets)
const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID") || "";
const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET") || "";
const razorpayAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const { type, old_record, record } = payload;

    // We only care about UPDATE events (status changes)
    if (type !== "UPDATE") {
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
      newStatus === "cancelled" ||
      newStatus === "shop_dispute_cancel";

    const statusChanged = oldStatus !== newStatus;
    const manualRefundTriggered = oldRefundStatus !== "processing" && newRefundStatus === "processing";

    // 100x FIX: If an Admin explicitly triggers a manual refund, ALWAYS honor it regardless of current order status (e.g. refunding a 'delivered' order).
    const shouldRefund = (isRefundableState && statusChanged) || manualRefundTriggered;

    if (shouldRefund) {
      console.log(`Order ${record.id} changed to ${newStatus}. Initiating refund check...`);

      // 1. Skip if it was Cash on Delivery
      if (record.payment_method === "cod") {
        console.log("Skipping refund: Order was Cash on Delivery.");
        return new Response("No refund needed: COD order.", { status: 200 });
      }

      // 2. Extract Razorpay Payment ID
      const paymentId = record.razorpay_payment_id;
      if (!paymentId) {
        console.warn(`No razorpay_payment_id found for prepaid order ${record.id}`);
        return new Response("Refund skipped: No Razorpay payment ID.", { status: 200 });
      }

      // 3. Skip if already refunded
      if (record.refund_status === "processed" || record.refund_id) {
        return new Response("Refund skipped: Already processed.", { status: 200 });
      }

      // 4. Call Razorpay API to issue the refund
      const collectedAmount = record.grand_total_collected != null ? Number(record.grand_total_collected) : 0;
      const amountInPaise = Math.round(collectedAmount * 100);

      const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
      );
      
      if (amountInPaise <= 0) {
        console.log(`Order ${record.id} has 0 collected amount. Marking refund as processed internally.`);

        await supabaseAdmin.from("orders").update({
          refund_status: "processed",
          refund_id: "internal_zero_amount"
        }).eq("id", record.id);

        return new Response("Refund processed internally (zero amount).", { status: 200 });
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
            reason: newStatus,
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

        return new Response(`Razorpay Error: ${refundData.error?.description}`, { status: 200 }); // Return 200 to satisfy webhook
      }

      // 5. Update the Database with the Refund ID
      await supabaseAdmin.from("orders").update({
        refund_id: refundData.id,
        refund_status: "processed"
      }).eq("id", record.id);

      console.log(`Refund ${refundData.id} successfully processed for order ${record.id}.`);
      return new Response(`Refund processed successfully: ${refundData.id}`, { status: 200 });
    }

    return new Response("No refund action required for this status change.", { status: 200 });

  } catch (err: any) {
    console.error("Webhook exception:", err);
    // Still return 200 to prevent Supabase from retrying endlessly
    return new Response("Internal error (logged)", { status: 200 });
  }
});

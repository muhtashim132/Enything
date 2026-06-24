// Supabase Edge Function: send-otp
// Generates a 6-digit OTP, stores it in otp_tokens table, sends via Fast2SMS.
// Called directly from the Flutter app.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Generate a cryptographically random 6-digit OTP
function generateOtp(): string {
  const array = new Uint32Array(1);
  crypto.getRandomValues(array);
  return String(array[0] % 1000000).padStart(6, "0");
}

// SHA-256 hash for storing OTP securely
async function hashOtp(otp: string, phone: string): Promise<string> {
  const data = new TextEncoder().encode(`${otp}:${phone}`);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { phone } = await req.json();

    if (!phone) {
      return new Response(
        JSON.stringify({ error: "phone is required" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Normalize: strip non-digits for Fast2SMS (needs 10-digit Indian number)
    const digits = phone.replace(/\D/g, "");
    const number =
      digits.length === 12 && digits.startsWith("91")
        ? digits.slice(2)
        : digits.length === 10
        ? digits
        : null;

    if (!number) {
      return new Response(
        JSON.stringify({ error: "Invalid Indian phone number. Use format +91XXXXXXXXXX." }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    const fast2smsKey = Deno.env.get("FAST2SMS_API_KEY");
    if (!fast2smsKey) {
      return new Response(
        JSON.stringify({ error: "SMS service not configured." }),
        { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Create Supabase service-role client to write to otp_tokens
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Generate OTP and hash it
    const otp = generateOtp();
    const otpHash = await hashOtp(otp, phone);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString(); // 5 min

    // Delete any existing tokens for this phone (prevent accumulation)
    await supabase.from("otp_tokens").delete().eq("phone", phone);

    // Insert new token
    const { error: insertError } = await supabase.from("otp_tokens").insert({
      phone,
      otp_hash: otpHash,
      expires_at: expiresAt,
    });

    if (insertError) {
      console.error("DB insert error:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to generate OTP. Please try again." }),
        { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Send OTP via Fast2SMS
    const smsResponse = await fetch("https://www.fast2sms.com/dev/otp/send", {
      method: "POST",
      headers: {
        authorization: fast2smsKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        mobile: number,
        otp_id: Deno.env.get("FAST2SMS_TEMPLATE_ID") ?? "218561",
        otp: otp,
        variables_values: otp,
      }),
    });

    const smsResult = await smsResponse.json();

    if (!smsResponse.ok || smsResult.return === false) {
      console.error("Fast2SMS error:", smsResult);
      // Clean up the token we just inserted
      await supabase.from("otp_tokens").delete().eq("phone", phone);
      return new Response(
        JSON.stringify({
          error: smsResult.message?.[0] ?? "Failed to send OTP. Please try again.",
        }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("send-otp error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error." }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
});

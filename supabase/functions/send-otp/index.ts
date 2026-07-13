// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

// Utility for JSON responses
function jsonResponse(data: any, status: number = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  // Handle CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  // Enforce POST method
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json();
    const { phone } = body;

    if (!phone || typeof phone !== "string") {
      return jsonResponse({ error: "Phone number is required." }, 400);
    }

    // Strict Normalization: Extract exactly 10 digits for Indian mobile numbers
    const digits = phone.replace(/\D/g, "");
    const number =
      digits.length === 12 && digits.startsWith("91")
        ? digits.slice(2)
        : digits.length === 10
        ? digits
        : null;

    if (!number) {
      return jsonResponse(
        { error: "Invalid phone number format. Please provide a 10-digit Indian mobile number." },
        400
      );
    }

    // Environment Variables Validation (Fail Fast)
    const fast2smsKey = Deno.env.get("FAST2SMS_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    
    // Fallback to currently known DLT credentials if not set in env
    const senderId = Deno.env.get("FAST2SMS_SENDER_ID") || "ENYTHG"; 
    const templateId = Deno.env.get("FAST2SMS_TEMPLATE_ID") || "218561";

    if (!fast2smsKey || !supabaseUrl || !supabaseServiceKey) {
      console.error("CRITICAL: Missing essential environment variables.");
      return jsonResponse({ error: "Server configuration error. Service unavailable." }, 500);
    }

    // 1. Initialize Supabase Admin Client
    // We use the service role key to securely bypass RLS and insert into otp_tokens
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false },
    });

    // 2. Generate and Hash OTP
    const otp = generateOtp();
    const otpHash = await hashOtp(otp, phone);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString(); // 5 minutes expiry

    // 3. Database Operations: Atomic Replace
    // Delete any existing tokens for this number to prevent bloat
    await supabaseAdmin.from("otp_tokens").delete().eq("phone", phone);

    const { error: insertError } = await supabaseAdmin.from("otp_tokens").insert({
      phone,
      otp_hash: otpHash,
      expires_at: expiresAt,
    });

    if (insertError) {
      console.error("Database Insert Error (otp_tokens):", insertError);
      return jsonResponse({ error: "Failed to generate OTP. Database error." }, 500);
    }

    // 4. Send OTP via Fast2SMS DLT Route with Timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000); // 8 seconds timeout

    try {
      const smsResponse = await fetch("https://www.fast2sms.com/dev/bulkV2", {
        method: "POST",
        headers: {
          "authorization": fast2smsKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          route: "dlt",
          sender_id: senderId,
          message: templateId,
          variables_values: otp,
          flash: 0,
          numbers: number,
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      const smsResult = await smsResponse.json();

      // Fast2SMS sets 'return: false' for logical errors even with 200 OK
      if (!smsResponse.ok || smsResult.return === false) {
        console.error("Fast2SMS API Error:", smsResult);
        
        // Rollback: Delete the token since SMS failed to send securely
        await supabaseAdmin.from("otp_tokens").delete().eq("phone", phone);

        // Fast2SMS returns message as a string on error, or an array on success
        const errorMessage = typeof smsResult.message === "string"
          ? smsResult.message
          : (Array.isArray(smsResult.message) ? smsResult.message[0] : "Failed to send SMS through provider.");
        
        return jsonResponse({ error: errorMessage }, 502);
      }

      // Success
      return jsonResponse({ success: true, message: "OTP sent successfully." }, 200);

    } catch (fetchError) {
      const isAbortError = fetchError && typeof fetchError === 'object' && 'name' in fetchError && fetchError.name === "AbortError";
      clearTimeout(timeoutId);
      console.error("Fast2SMS Network/Timeout Error:", fetchError);
      
      // Rollback on network failure/timeout
      await supabaseAdmin.from("otp_tokens").delete().eq("phone", phone);

      if (isAbortError) {
        return jsonResponse({ error: "SMS provider timeout. Please try again." }, 504);
      }
      return jsonResponse({ error: "Failed to connect to SMS provider." }, 502);
    }

  } catch (err) {
    console.error("send-otp Unhandled Exception:", err);
    return jsonResponse({ error: "Internal server error during OTP generation." }, 500);
  }
});

// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MAX_ATTEMPTS = 5;

async function hashOtp(otp: string, phone: string): Promise<string> {
  const data = new TextEncoder().encode(`${otp}:${phone}`);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { phone, otp } = await req.json();

    if (!phone || !otp) {
      return new Response(
        JSON.stringify({ error: "phone and otp are required" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Look up OTP token for this phone
    const { data: tokenRow, error: fetchError } = await supabase
      .from("otp_tokens")
      .select("id, otp_hash, expires_at, attempts")
      .eq("phone", phone)
      .maybeSingle();

    if (fetchError || !tokenRow) {
      return new Response(
        JSON.stringify({ error: "OTP not found. Please request a new one." }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Check expiry
    if (new Date(tokenRow.expires_at) < new Date()) {
      await supabase.from("otp_tokens").delete().eq("id", tokenRow.id);
      return new Response(
        JSON.stringify({ error: "OTP has expired. Please request a new one." }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Check max attempts
    if (tokenRow.attempts >= MAX_ATTEMPTS) {
      await supabase.from("otp_tokens").delete().eq("id", tokenRow.id);
      return new Response(
        JSON.stringify({ error: "Too many attempts. Please request a new OTP." }),
        { status: 429, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Verify hash
    const submittedHash = await hashOtp(otp.trim(), phone);
    if (submittedHash !== tokenRow.otp_hash) {
      // Increment attempt count
      await supabase
        .from("otp_tokens")
        .update({ attempts: tokenRow.attempts + 1 })
        .eq("id", tokenRow.id);

      const remaining = MAX_ATTEMPTS - tokenRow.attempts - 1;
      return new Response(
        JSON.stringify({
          error: `Invalid OTP. ${remaining} attempt${remaining !== 1 ? "s" : ""} remaining.`,
        }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // ✅ OTP is valid — delete it (one-time use)
    await supabase.from("otp_tokens").delete().eq("id", tokenRow.id);

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("verify-otp error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error." }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
});

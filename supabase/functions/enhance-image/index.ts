// Supabase Edge Function: enhance-image
// Triggered by a DB trigger on storage.objects INSERT for 'raw-product-images' bucket.
// Downloads the raw JPEG, applies a vivid auto-enhancement preset (brightness boost,
// contrast pop, saturation lift, warm tone), saves to 'enhanced-product-images' bucket,
// and updates products.enhanced_url for the matching product.
//
// Enhancement is done 100% server-side via pure JavaScript pixel manipulation —
// no external API, no AI cost, no rate limits. Always free.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TARGET_BUCKET = "enhanced-product-images";
const MAX_POLL_ATTEMPTS = 6;
const POLL_DELAY_MS = 2500;

// ── Pure-JS pixel-level enhancement ─────────────────────────────────────────

function clamp(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : Math.round(v);
}

/**
 * Vivid auto-enhancement preset applied to each pixel (RGBA flat array).
 * - Brightness: +8 (slight lift so shadows are visible)
 * - Contrast:   ×1.12 (punchy midtones)
 * - Saturation: ×1.22 (vivid, product-catalog look)
 * - Warmth:     +10R / -5B (natural warm tone, removes cold camera cast)
 */
function enhanceRgbaBuffer(
  data: Uint8ClampedArray,
  width: number,
  height: number
): void {
  const BRIGHTNESS = 8;
  const CONTRAST = 1.12;
  const SAT = 1.22;
  const WARM_R = 10;
  const WARM_B = -5;

  for (let i = 0; i < data.length; i += 4) {
    let r = data[i];
    let g = data[i + 1];
    let b = data[i + 2];
    // Alpha (data[i+3]) is left unchanged

    // 1. Brightness
    r += BRIGHTNESS;
    g += BRIGHTNESS;
    b += BRIGHTNESS;

    // 2. Contrast (scale around 128 midpoint)
    r = (r - 128) * CONTRAST + 128;
    g = (g - 128) * CONTRAST + 128;
    b = (b - 128) * CONTRAST + 128;

    // 3. Saturation via YUV-style luminance
    const lum = 0.299 * r + 0.587 * g + 0.114 * b;
    r = lum + (r - lum) * SAT;
    g = lum + (g - lum) * SAT;
    b = lum + (b - lum) * SAT;

    // 4. Warmth
    r += WARM_R;
    b += WARM_B;

    data[i] = clamp(r);
    data[i + 1] = clamp(g);
    data[i + 2] = clamp(b);
  }
}

// ── JPEG decode / encode via jpeg-js (pure JS, no native deps, Deno-safe) ───

async function loadJpegJs() {
  // @ts-ignore – dynamic import via esm.sh
  const m = await import("https://esm.sh/jpeg-js@0.4.4?target=deno");
  return m.default ?? m;
}

// ── Main handler ─────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  try {
    // ── Parse trigger payload ─────────────────────────────────────────────
    let filePath: string | undefined;
    let bucketId: string | undefined;

    try {
      const body = await req.json();
      if (body?.record) {
        filePath = body.record.name;
        bucketId = body.record.bucket_id;
      } else {
        filePath = body?.name;
        bucketId = body?.bucket_id;
      }
    } catch {
      return new Response("Bad request: expected JSON body", { status: 400 });
    }

    if (!filePath || !bucketId || bucketId !== "raw-product-images") {
      console.log(`Ignored: bucket=${bucketId ?? "unknown"}, file=${filePath ?? "unknown"}`);
      return new Response("Ignored", { status: 200 });
    }

    console.log(`✨ enhance-image: processing ${bucketId}/${filePath}`);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ── Step 1: Download raw image ────────────────────────────────────────
    const { data: rawBlob, error: downloadError } = await supabase.storage
      .from(bucketId)
      .download(filePath);

    if (downloadError || !rawBlob) {
      throw new Error(`Download failed: ${downloadError?.message ?? "empty response"}`);
    }

    const rawBuffer = new Uint8Array(await rawBlob.arrayBuffer());
    console.log(`Downloaded ${rawBuffer.byteLength} bytes`);

    // ── Step 2: Decode JPEG → RGBA pixel buffer ────────────────────────────
    const jpeg = await loadJpegJs();
    let imageData: { data: Uint8ClampedArray; width: number; height: number };

    try {
      imageData = jpeg.decode(rawBuffer, { useTArray: true });
    } catch (decodeErr) {
      // If JPEG decode fails (e.g. PNG input), skip enhancement — just copy as-is
      console.warn(`JPEG decode failed (${decodeErr}). Storing original as enhanced.`);
      const { error: uploadErr } = await supabase.storage
        .from(TARGET_BUCKET)
        .upload(filePath, rawBlob, { contentType: "image/jpeg", upsert: true });
      if (uploadErr) throw new Error(`Upload (fallback) failed: ${uploadErr.message}`);
      const { data: u } = supabase.storage.from(TARGET_BUCKET).getPublicUrl(filePath);
      return new Response(
        JSON.stringify({ success: true, enhanced_url: u.publicUrl, note: "fallback_no_decode" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Step 3: Apply pixel-level enhancement ─────────────────────────────
    enhanceRgbaBuffer(imageData.data, imageData.width, imageData.height);
    console.log(`Enhanced ${imageData.width}×${imageData.height} image`);

    // ── Step 4: Re-encode as JPEG quality 92 ─────────────────────────────
    const encoded = jpeg.encode(
      { data: imageData.data, width: imageData.width, height: imageData.height },
      92
    );
    const enhancedBytes = encoded.data as Uint8Array;
    console.log(`Re-encoded: ${enhancedBytes.byteLength} bytes`);

    // ── Step 5: Upload to enhanced-product-images bucket ──────────────────
    const outputPath = filePath.replace(/\.(jpe?g|webp|png|gif|bmp|tiff?)$/i, ".jpg");
    const { error: uploadError } = await supabase.storage
      .from(TARGET_BUCKET)
      .upload(outputPath, enhancedBytes, {
        contentType: "image/jpeg",
        upsert: true,
      });

    if (uploadError) {
      throw new Error(`Upload to ${TARGET_BUCKET} failed: ${uploadError.message}`);
    }

    // ── Step 6: Get public URL ─────────────────────────────────────────────
    const { data: urlData } = supabase.storage.from(TARGET_BUCKET).getPublicUrl(outputPath);
    const enhancedUrl = urlData.publicUrl;
    console.log(`Enhanced URL: ${enhancedUrl}`);

    // ── Step 7: Update products.enhanced_url with race-condition polling ───
    const { data: rawUrlData } = supabase.storage.from(bucketId).getPublicUrl(filePath);
    const rawUrl = rawUrlData.publicUrl;

    let rowsUpdated = 0;
    let updateError: unknown = null;

    for (let attempt = 1; attempt <= MAX_POLL_ATTEMPTS; attempt++) {
      const { data, error } = await supabase
        .from("products")
        .update({ enhanced_url: enhancedUrl })
        .contains("images", JSON.stringify([rawUrl]))
        .select("id");

      updateError = error;
      if (!error && data && data.length > 0) {
        rowsUpdated = data.length;
        console.log(`✅ products.enhanced_url set on attempt ${attempt}`);
        break;
      }
      console.log(`Product not found on attempt ${attempt}, retrying in ${POLL_DELAY_MS}ms…`);
      await new Promise((r) => setTimeout(r, POLL_DELAY_MS));
    }

    if (rowsUpdated === 0) {
      const errMsg = updateError instanceof Error ? updateError.message : String(updateError);
      console.error(`❌ Could not link enhanced_url after ${MAX_POLL_ATTEMPTS} attempts: ${errMsg}`);
      // Still return 200 — the file IS saved, seller can re-trigger if needed
      return new Response(
        JSON.stringify({ success: false, enhanced_url: enhancedUrl, error: errMsg }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`✅ enhance-image complete: ${filePath} → ${outputPath}`);
    return new Response(
      JSON.stringify({ success: true, enhanced_url: enhancedUrl }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`❌ enhance-image error: ${message}`);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

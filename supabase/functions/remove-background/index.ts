// Supabase Edge Function: remove-background
// Triggered by a Supabase Database Webhook on storage.objects INSERT.
// Downloads the raw image from 'raw-product-images', strips the background
// via Hugging Face BRIA-RMBG 2.0, and saves the transparent PNG to 'clean-cutouts'.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SOURCE_BUCKET = "raw-product-images";
const TARGET_BUCKET = "clean-cutouts";
const HF_API_URL = "https://api-inference.huggingface.co/models/briaai/RMBG-2.0";
const MAX_RETRIES = 5;
const BASE_DELAY_MS = 3000; // 3 seconds initial backoff

serve(async (req: Request) => {
  try {
    // Parse the Supabase webhook payload
    const payload = await req.json();

    // Supabase Storage webhook wraps data under 'record'
    const record = payload?.record;

    // Guard: only process inserts into our source bucket
    if (!record || record.bucket_id !== SOURCE_BUCKET) {
      console.log(`Ignored: bucket=${record?.bucket_id ?? "unknown"}`);
      return new Response("Ignored", { status: 200 });
    }

    const filePath: string = record.name;
    console.log(`Processing: ${filePath}`);

    // Validate required secrets (never expose values in responses)
    const hfToken = Deno.env.get("HUGGING_FACE_TOKEN");
    if (!hfToken) {
      throw new Error("HUGGING_FACE_TOKEN secret is not configured in Edge Function settings.");
    }

    // Create Supabase service-role client (bypasses RLS for storage access)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ── Step 1: Download raw image from source bucket ─────────────────────
    const { data: rawBlob, error: downloadError } = await supabase.storage
      .from(SOURCE_BUCKET)
      .download(filePath);

    if (downloadError || !rawBlob) {
      throw new Error(`Image download failed: ${downloadError?.message ?? "empty response"}`);
    }

    const imageBuffer = await rawBlob.arrayBuffer();
    console.log(`Downloaded ${imageBuffer.byteLength} bytes from ${SOURCE_BUCKET}/${filePath}`);

    // ── Step 2: Call Hugging Face API with exponential backoff ─────────────
    let hfResponse: Response | null = null;
    let lastStatus = 0;

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      hfResponse = await fetch(HF_API_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${hfToken}`,
          "Content-Type": "application/octet-stream",
        },
        body: imageBuffer,
      });

      lastStatus = hfResponse.status;

      if (lastStatus === 503) {
        // Model is still loading — use exponential backoff
        const waitMs = BASE_DELAY_MS * Math.pow(2, attempt);
        console.log(`HF model loading (503). Attempt ${attempt + 1}/${MAX_RETRIES}. Retrying in ${waitMs}ms...`);
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        continue;
      }

      // Any other status (200 success or non-retryable error) — break
      break;
    }

    if (!hfResponse || !hfResponse.ok) {
      // Read error body for logging only — never forward to client
      const errText = await hfResponse?.text().catch(() => "unreadable");
      throw new Error(`Hugging Face API error [${lastStatus}]: ${errText}`);
    }

    console.log(`Hugging Face responded with status ${lastStatus}`);

    // ── Step 3: Extract the transparent PNG from the response ──────────────
    const pngBlob = await hfResponse.blob();
    console.log(`Received PNG blob: ${pngBlob.size} bytes`);

    // ── Step 4: Build output path — enforce .png extension ─────────────────
    // Strips .jpg, .jpeg, .webp, .JPG, etc. and replaces with .png
    const outputPath = filePath.replace(/\.(jpe?g|webp|png|gif|bmp|tiff?)$/i, ".png");
    console.log(`Output path: ${TARGET_BUCKET}/${outputPath}`);

    // ── Step 5: Upload transparent PNG to the target bucket ────────────────
    const { error: uploadError } = await supabase.storage
      .from(TARGET_BUCKET)
      .upload(outputPath, pngBlob, {
        contentType: "image/png",
        upsert: true, // Overwrite if seller re-uploads the same image
      });

    if (uploadError) {
      throw new Error(`Upload to clean-cutouts failed: ${uploadError.message}`);
    }

    // ── Step 6: Get the public URL of the saved cutout ────────────────────
    const { data: urlData } = supabase.storage
      .from(TARGET_BUCKET)
      .getPublicUrl(outputPath);

    const cutoutUrl = urlData.publicUrl;
    console.log(`Cutout public URL: ${cutoutUrl}`);

    // ── Step 7: Update matching product record with cutout_url ────────────
    // Match by checking if image_url contains the file path (works for both
    // full URL and path-only storage patterns)
    const { error: updateError } = await supabase
      .from("products")
      .update({ cutout_url: cutoutUrl })
      .or(`image_url.like.%${filePath}%,images.cs.{"${filePath}"}`);

    if (updateError) {
      // Non-fatal: log and continue — the cutout is saved even if product link fails
      console.warn(`Product update warning: ${updateError.message}`);
    }

    console.log(`✅ Background removal complete: ${filePath} → ${outputPath}`);

    return new Response(
      JSON.stringify({ success: true, output: outputPath, cutout_url: cutoutUrl }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );

  } catch (err) {
    // Log full error server-side only — never expose secrets or internals to client
    const message = err instanceof Error ? err.message : String(err);
    console.error(`❌ remove-background error: ${message}`);

    return new Response(
      JSON.stringify({ error: "Background removal failed. Check function logs." }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

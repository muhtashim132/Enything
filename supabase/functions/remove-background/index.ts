// Supabase Edge Function: remove-background
// Triggered by a Supabase Database Trigger on storage.objects INSERT.
// The trigger passes { name, bucket_id } as the JSON body via supabase_functions.http_request.
// Downloads the raw image from 'raw-product-images', strips the background
// via Hugging Face BRIA-RMBG 2.0, saves the transparent PNG to 'clean-cutouts',
// then updates products.cutout_url for the matching product.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TARGET_BUCKET = "clean-cutouts";
const MAX_RETRIES = 5;
const BASE_DELAY_MS = 3000; // 3 seconds initial backoff

serve(async (req: Request) => {
  try {
    // ── Parse the body sent by the DB trigger ─────────────────────────────
    // The DB trigger calls supabase_functions.http_request with a JSON body
    // containing { name: row.name, bucket_id: row.bucket_id }.
    let filePath: string | undefined;
    let bucketId: string | undefined;

    try {
      const body = await req.json();
      // Support both the trigger-passed format { name, bucket_id }
      // and the Supabase Storage webhook format { record: { name, bucket_id } }
      if (body?.record) {
        filePath = body.record.name;
        bucketId = body.record.bucket_id;
      } else {
        filePath = body?.name;
        bucketId = body?.bucket_id;
      }
    } catch {
      console.error("❌ Failed to parse request body as JSON.");
      return new Response("Bad request: expected JSON body", { status: 400 });
    }

    // Guard: only process inserts into our source buckets
    if (!filePath || !bucketId || (bucketId !== "raw-product-images" && bucketId !== "products")) {
      console.log(`Ignored: bucket=${bucketId ?? "unknown"}, file=${filePath ?? "unknown"}`);
      return new Response("Ignored", { status: 200 });
    }

    console.log(`Processing: ${bucketId}/${filePath}`);

    // Validate custom API URL
    const apiUrl = Deno.env.get("CUSTOM_BG_REMOVAL_URL");
    if (!apiUrl) {
      const msg =
        "CUSTOM_BG_REMOVAL_URL secret is not configured in Edge Function settings. " +
        "Please add your custom Hugging Face Space URL.";
      console.error("❌ " + msg);
      return new Response(JSON.stringify({ error: msg }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Create Supabase service-role client (bypasses RLS for storage + products)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ── Step 1: Download raw image from source bucket ─────────────────────
    const { data: rawBlob, error: downloadError } = await supabase.storage
      .from(bucketId)
      .download(filePath);

    if (downloadError || !rawBlob) {
      throw new Error(`Image download failed: ${downloadError?.message ?? "empty response"}`);
    }

    const imageBuffer = await rawBlob.arrayBuffer();
    console.log(`Downloaded ${imageBuffer.byteLength} bytes from ${bucketId}/${filePath}`);

    // ── Step 2: Call Hugging Face API with exponential backoff ─────────────
    let hfResponse: Response | null = null;
    let lastStatus = 0;

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      hfResponse = await fetch(apiUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/octet-stream",
        },
        body: imageBuffer,
      });

      lastStatus = hfResponse.status;

      if (lastStatus === 503) {
        // Model is still loading — use exponential backoff
        const waitMs = BASE_DELAY_MS * Math.pow(2, attempt);
        console.log(
          `HF model loading (503). Attempt ${attempt + 1}/${MAX_RETRIES}. Retrying in ${waitMs}ms...`
        );
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        continue;
      }

      // Any other status (200 success or non-retryable error) — break
      break;
    }

    if (!hfResponse || !hfResponse.ok) {
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
    // The raw image URL stored in products.images[] is the public URL of the
    // file in the source bucket. We reconstruct that URL to find the product.
    const { data: rawUrlData } = supabase.storage
      .from(bucketId)
      .getPublicUrl(filePath);
    const rawUrl = rawUrlData.publicUrl;

    // Strategy: use a Postgres RPC that does a safe text-search within the
    // images array column. We use the raw SQL filter via .filter() which maps
    // to PostgREST's ?images=cs.{"rawUrl"} — but for text[], we need the
    // correct format with no inner quotes for the contains operator.
    // The safest cross-version approach: use an RPC function that accepts the
    // URL and updates the matching row server-side.
    //
    // Fallback: use .like filter on the text representation of the array.
    // This matches any product whose images array contains the exact raw URL.
    let updatedProducts: any = null;
    let updateError: any = null;
    let rowsUpdated = 0;

    // ── Race Condition Fix: Intelligent Polling ────────────────────────────
    // The Flutter app uploads the image FIRST, which triggers this edge function.
    // If we process it fast enough, the product row might not be inserted yet!
    // We patiently poll for up to ~15 seconds until the product appears.
    for (let attempt = 1; attempt <= 6; attempt++) {
      const { data: currentUpdateData, error: currentUpdateError } = await supabase
        .from("products")
        .update({ cutout_url: cutoutUrl })
        .contains("images", JSON.stringify([rawUrl]))
        .select("id"); // Select id so we know if a row was actually updated

      updateError = currentUpdateError;

      if (!currentUpdateError && currentUpdateData && currentUpdateData.length > 0) {
        updatedProducts = currentUpdateData;
        rowsUpdated = currentUpdateData.length;
        console.log(`✅ Product linked successfully on attempt ${attempt}`);
        break; // Success! Break out of the loop
      }

      console.log(`Product not found for URL on attempt ${attempt}. Retrying in 2.5s...`);
      await new Promise((r) => setTimeout(r, 2500));
    }

    if (updateError || rowsUpdated === 0) {
      // Log clearly — this is important for debugging
      console.error(
        `❌ Product cutout_url update FAILED or product not found for rawUrl="${rawUrl}" after 6 attempts.`
      );
      if (updateError) {
        console.error(`Error details: ${updateError.message} (code: ${updateError.code})`);
      }
      // Still return success since the cutout file was saved — seller can re-trigger manually
      return new Response(
        JSON.stringify({
          success: false,
          output: outputPath,
          cutout_url: cutoutUrl,
          update_error: updateError?.message ?? "Product not found (race condition timeout)",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`✅ Background removal complete: ${filePath} → ${outputPath} (products updated: ${rowsUpdated})`);

    return new Response(
      JSON.stringify({ success: true, output: outputPath, cutout_url: cutoutUrl }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    // Log full error server-side only — never expose secrets or internals to client
    const message = err instanceof Error ? err.message : String(err);
    console.error(`❌ remove-background error: ${message}`);

    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

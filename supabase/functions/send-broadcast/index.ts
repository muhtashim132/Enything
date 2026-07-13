// @ts-nocheck
// This file runs on the Deno runtime (Supabase Edge Functions).
// VS Code may show errors for Deno globals (Deno.*) and URL imports — these are safe to ignore.
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── JWT / OAuth2 helpers ───────────────────────────────────────────────────

/** Decode a PEM private key string into an ArrayBuffer for Web Crypto. */
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const buf = new ArrayBuffer(binary.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i);
  return buf;
}

/** Base64URL-encode a Uint8Array (no padding). */
function b64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

/**
 * Exchange a Firebase Service Account for a short-lived OAuth2 access token
 * that authorises calls to the FCM HTTP v1 API.
 */
async function getFcmAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();

  const header  = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = b64url(enc.encode(JSON.stringify({
    iss:   sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud:   'https://oauth2.googleapis.com/token',
    iat:   now,
    exp:   now + 3600,
  })));

  const signingInput = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(signingInput));
  const jwt = `${signingInput}.${b64url(new Uint8Array(sig))}`;

  const res  = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    }),
  });

  const json = await res.json();
  if (!json.access_token) {
    throw new Error(`OAuth2 token exchange failed: ${JSON.stringify(json)}`);
  }
  return json.access_token as string;
}

// ── Chunk helper ───────────────────────────────────────────────────────────
function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

// ── Edge Function entry point ──────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const rawData = await req.json() as {
      audience: string; // 'All Users', 'Customers', 'Sellers', 'Riders'
      title:   string;
      body:    string;
      data?:   Record<string, string>;
    };
    
    let { audience, title, body, data } = rawData;

    if (!audience || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'audience, title, and body are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // STRESS-TEST FIX: Type Coercion to prevent TypeError on .substring
    title = String(title ?? '').substring(0, 100);
    body = String(body ?? '').substring(0, 512);

    // Ensure data payload only contains strings to prevent FCM crashing
    const safeData: Record<string, string> = {
      title,
      body,
    };
    if (data && typeof data === 'object') {
      for (const [k, v] of Object.entries(data)) {
        safeData[k] = String(v ?? '').substring(0, 512);
      }
    }

    // Admin Supabase client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')             ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // Prepare Firebase access
    const sa         = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');
    const projectId  = sa.project_id ?? Deno.env.get('FIREBASE_PROJECT_ID') ?? '';
    let accessToken;
    let tokenExp = Date.now() + 3500 * 1000;
    try {
      accessToken = await getFcmAccessToken(sa);
    } catch (e) {
      throw new Error(`Failed to get FCM token: ${e}`);
    }
    const fcmUrl      = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let totalSent = 0;
    let totalProcessed = 0;
    const errors: string[] = [];
    
    // STRESS-TEST FIX: API Gateway Protection (cap payload to prevent 413)
    const pushError = (err: string) => {
      if (errors.length < 100) errors.push(err);
      else if (errors.length === 100) errors.push('Too many errors, truncating log...');
    };

    // Stream state
    let fetchMore = true;
    let lastId = '00000000-0000-0000-0000-000000000000';
    const pageSize = 1000;
    const roleMap: Record<string, string> = {
      'Customers': 'customer',
      'Sellers': 'seller',
      'Riders': 'delivery',
    };

    const notifKeyBase = `broadcast_${Date.now()}`;
    const seenUserIds = new Set<string>(); // Phase 11 Fix: Global deduplication

    // STRESS-TEST FIX: Stream Processing Loop (OOM Protection)
    while (fetchMore) {
      // Phase 10 Fix: Deterministic Keyset Pagination immune to concurrent deletes
      let query = supabase.from('device_tokens')
          .select('id, token, user_id')
          .order('id', { ascending: true })
          .gt('id', lastId)
          .limit(pageSize);
      
      if (roleMap[audience]) {
        query = query.eq('role', roleMap[audience]);
      }

      const res = await query;
      if (res.error) {
        pushError(`DB Fetch Error (lastId ${lastId}): ${JSON.stringify(res.error)}`);
        break; // Stop fetching on DB error, but we return 200 with what we have
      }

      const rows = res.data ?? [];
      
      if (rows.length === 0) {
        fetchMore = false;
        break;
      }
      
      totalProcessed += rows.length;

      // STRESS-TEST FIX: Infinite Stream Token Renewal
      if (Date.now() > tokenExp) {
        accessToken = await getFcmAccessToken(sa);
        tokenExp = Date.now() + 3500 * 1000;
      }

      // 1. Dispatch Push Notifications for this page concurrently
      const tokenChunks = chunkArray(rows, 50);
      for (const batch of tokenChunks) {
        await Promise.all(batch.map(async ({ token }) => {
          try {
            const message = {
              message: {
                token,
                notification: { title, body },
                data: safeData,
                android: {
                  priority: 'high',
                  notification: {
                    channel_id: 'enything_push_channel',
                    icon: 'ic_notification',
                    default_sound: true,
                    default_vibrate_timings: true,
                    notification_priority: 'PRIORITY_MAX',
                    visibility: 'PUBLIC',
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                  },
                },
                apns: {
                  payload: {
                    aps: {
                      sound: 'default',
                      badge: 1,
                    },
                  },
                },
              },
            };

            // STRESS-TEST FIX: TCP Deadlock Protection (15s abort)
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 15000);

            const fcmRes = await fetch(fcmUrl, {
              method:  'POST',
              headers: {
                Authorization:  `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(message),
              signal: controller.signal,
            });
            clearTimeout(timeoutId);

            if (fcmRes.ok) {
              totalSent++;
            } else {
              const errText = await fcmRes.text();
              pushError(`token[...${token.slice(-6)}]: ${errText}`);
              // Remove expired / unregistered tokens automatically
              if (fcmRes.status === 404 || fcmRes.status === 410) {
                await supabase.from('device_tokens').delete().eq('token', token);
              }
            }
          } catch (e) {
            pushError(String(e));
          }
        }));
      }

      // 2. Build Insert Payload (Deduplicated globally to prevent OOM and Pixel Overloading)
      const notifPayload = [];
      for (const r of rows) {
        const uid = r.user_id;
        if (uid && !seenUserIds.has(uid)) {
          seenUserIds.add(uid);
          notifPayload.push({
            user_id: uid,
            title: title,
            body: body,
            // STRESS-TEST FIX: Prevent Postgres cross-chunk unique constraint failures without global memory state
            notif_key: `${notifKeyBase}_${crypto.randomUUID().substring(0, 8)}`,
          });
        }
      }

      // 3. Insert Database History for this page
      if (notifPayload.length > 0) {
        const notifChunks = chunkArray(notifPayload, 1000); // theoretically already <= 1000
        for (const chunk of notifChunks) {
          const { error: insertErr } = await supabase.from('notifications').insert(chunk);
          if (insertErr) {
            pushError(`DB Insert Error: ${JSON.stringify(insertErr)}`);
            // Continue; history insert failure shouldn't crash the next page's dispatch
          }
        }
      }

      // 4. Advance Cursor or Stop
      if (rows.length < pageSize) {
        fetchMore = false;
      } else {
        lastId = rows[rows.length - 1].id;
      }
    }

    return new Response(
      JSON.stringify({ sent: totalSent, total: totalProcessed, errors }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

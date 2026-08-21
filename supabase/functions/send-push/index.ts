// @ts-nocheck
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

let cachedAccessToken: string | null = null;
let tokenExpirationTime: number = 0;

let tokenRefreshPromise: Promise<string> | null = null;

// ── Server-Side Deduplication Cache (15s TTL) ─────────────────────────────
const recentPushes = new Map<string, number>();

function isDuplicatePush(key: string): boolean {
  const now = Date.now();
  for (const [k, timestamp] of recentPushes.entries()) {
    if (now - timestamp > 30000) {
      recentPushes.delete(k);
    }
  }
  const lastTime = recentPushes.get(key);
  if (lastTime && now - lastTime < 15000) {
    return true;
  }
  recentPushes.set(key, now);
  return false;
}

/**
 * Exchange a Firebase Service Account for a short-lived OAuth2 access token
 * that authorises calls to the FCM HTTP v1 API.
 * EF2 FIX: Invalidate cache on any FCM 401 to force token refresh.
 */
async function getFcmAccessToken(sa: Record<string, string>, forceRefresh = false): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (!forceRefresh && cachedAccessToken && now < tokenExpirationTime) {
    return cachedAccessToken;
  }

  // STRESS-TEST FIX: Mutex Promise-Lock to prevent Google OAuth 429 Rate Limiting
  if (tokenRefreshPromise) {
    return tokenRefreshPromise;
  }

  tokenRefreshPromise = (async () => {
    try {
      const enc = new TextEncoder();

      const header = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
      const payload = b64url(enc.encode(JSON.stringify({
        iss: sa.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
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

      const res = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion: jwt,
        }),
      });

      const json = await res.json();
      if (!json.access_token) {
        throw new Error(`OAuth2 token exchange failed: ${JSON.stringify(json)}`);
      }

      cachedAccessToken = json.access_token;
      tokenExpirationTime = now + 3500; // Cache for slightly less than 1 hour
      return cachedAccessToken as string;
    } finally {
      tokenRefreshPromise = null;
    }
  })();

  return tokenRefreshPromise;
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
    const rawBody = await req.json();

    // Support BOTH direct HTTP calls and Supabase Database Webhooks
    let user_id: any, title: any, body: any, data: any;

    if (rawBody.type === 'INSERT' && rawBody.record) {
      // It's a Supabase Webhook payload from the `notifications` table
      user_id = rawBody.record.user_id;
      title = rawBody.record.title;
      body = rawBody.record.body;
      data = {};
      if (rawBody.record.order_id) {
        data.order_id = String(rawBody.record.order_id);
      }
      if (rawBody.record.role) {
        data.role = String(rawBody.record.role);
      }
      if (rawBody.record.notif_key && typeof rawBody.record.notif_key === 'string') {
        const key = rawBody.record.notif_key;
        if (key.includes('_new_available') || key.includes('_reassigned_') || key.includes('_distance_')) {
          data.role = 'delivery';
          data.action = 'new_order';
        }
      }
    } else {
      // EF1 FIX: Authenticate the calling user for direct API calls.
      // Without this check, any internet user could spam push notifications
      // to any other user by calling this Edge Function directly.
      const supabaseAnon = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } },
      );
      const { data: { user }, error: authErr } = await supabaseAnon.auth.getUser();
      if (authErr || !user) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      user_id = rawBody.user_id;
      title = rawBody.title;
      body = rawBody.body;
      data = rawBody.data;
    }

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'user_id, title, and body are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Server-side deduplication check to prevent duplicate push cards (15s TTL)
    const orderId = (data && data.order_id) || (rawBody && rawBody.record && rawBody.record.order_id);
    const dedupKey = orderId ? `${user_id}_${orderId}` : `${user_id}_${title}`;
    if (isDuplicatePush(dedupKey)) {
      console.log(`[send-push] Deduplicated push skipped for key: ${dedupKey}`);
      return new Response(
        JSON.stringify({ message: 'Duplicate push skipped by server dedup cache', sent: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Admin Supabase client to read device tokens
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: rows, error: dbErr } = await supabase
      .from('device_tokens')
      .select('token, role, updated_at')
      .eq('user_id', user_id)
      .order('updated_at', { ascending: false });

    if (dbErr) throw dbErr;
    if (!rows || rows.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No device tokens for user', sent: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Deduplicate tokens by token string so multiple rows for same device don't cause duplicate pushes
    const uniqueMap = new Map<string, any>();
    for (const r of rows) {
      if (!uniqueMap.has(r.token)) {
        uniqueMap.set(r.token, r);
      }
    }
    const uniqueRows = Array.from(uniqueMap.values());

    // Parse service account & get OAuth2 token
    const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');
    const projectId = sa.project_id ?? Deno.env.get('FIREBASE_PROJECT_ID') ?? '';
    let accessToken = await getFcmAccessToken(sa);
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let sent = 0;
    const errors: string[] = [];

    // STRESS-TEST FIX: Chunking & Promise.all to prevent Edge Function timeout cascade
    const tokenChunks = chunkArray(uniqueRows, 50);
    for (const batch of tokenChunks) {
      await Promise.all(batch.map(async ({ token, role }) => {
        try {
          const effectiveRole = role || (data && data.role) || 'customer';
          const isUrgent = (effectiveRole === 'seller' || effectiveRole === 'delivery' || effectiveRole === 'delivery_partner') ||
                           String(title).toLowerCase().includes('new order') ||
                           String(title).toLowerCase().includes('payment done');
                                       
          const channelId = 'enything_urgent_alerts_v5';
          const soundFile = 'enything_bell';

          // DATA-ONLY MESSAGE: No top-level `notification` field.
          // This ensures Android ALWAYS routes through _fcmBackgroundHandler
          // which controls the channel, sound, FSI, and screen wake.
          // With a `notification` field, Android auto-displays on the default
          // channel (stale v4) bypassing our background handler — causing
          // silent/missing notifications for riders and double notifications
          // for sellers.
          const message = {
            message: {
              token,
              data: {
                title: String(title),
                body: String(body),
                role: String(effectiveRole),
                action: String((data && data.action) || (isUrgent ? 'new_order' : 'status_update')),
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                ...(data ? Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) : {}),
              },
              android: {
                priority: 'high',
              },
              apns: {
                headers: {
                  'apns-priority': '10',
                  'apns-push-type': 'alert',
                },
                payload: {
                  aps: {
                    alert: {
                      title: String(title),
                      body: String(body),
                    },
                    sound: soundFile ? `${soundFile}.wav` : 'default',
                    badge: 1,
                    'mutable-content': 1,
                    'content-available': 1,
                  },
                },
              },
            },
          };

          // STRESS-TEST FIX: AbortController to prevent TCP deadlocks
          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), 15000);

          let fcmRes = await fetch(fcmUrl, {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(message),
            signal: controller.signal,
          });
          clearTimeout(timeoutId);

          // EF2 FIX: On 401 (stale token), force-refresh once and retry.
          if (fcmRes.status === 401) {
            console.warn('FCM returned 401 — refreshing access token and retrying...');
            cachedAccessToken = null; // Invalidate cache
            accessToken = await getFcmAccessToken(sa, true);
            
            const controllerRetry = new AbortController();
            const timeoutIdRetry = setTimeout(() => controllerRetry.abort(), 15000);

            fcmRes = await fetch(fcmUrl, {
              method: 'POST',
              headers: {
                Authorization: `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(message),
              signal: controllerRetry.signal,
            });
            clearTimeout(timeoutIdRetry);
          }

          if (fcmRes.ok) {
            sent++;
          } else {
            const errText = await fcmRes.text();
            errors.push(`token[...${token.slice(-6)}]: ${errText}`);
            // Remove expired / unregistered tokens automatically
            if (fcmRes.status === 404 || fcmRes.status === 410) {
              await supabase.from('device_tokens').delete().eq('token', token);
            }
          }
        } catch (e) {
          errors.push(String(e));
        }
      }));
    }

    return new Response(
      JSON.stringify({ sent, total: rows.length, errors }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

/**
 * Exchange a Firebase Service Account for a short-lived OAuth2 access token
 * that authorises calls to the FCM HTTP v1 API.
 */
async function getFcmAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  
  if (cachedAccessToken && now < tokenExpirationTime) {
    return cachedAccessToken;
  }

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
  return cachedAccessToken;
}

// ── Edge Function entry point ──────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const rawBody = await req.json();

    // Support BOTH direct HTTP calls and Supabase Database Webhooks
    let user_id, title, body, data;

    if (rawBody.type === 'INSERT' && rawBody.record) {
      // It's a Supabase Webhook payload from the `notifications` table!
      user_id = rawBody.record.user_id;
      title = rawBody.record.title;
      body = rawBody.record.body;
      if (rawBody.record.order_id) {
        data = { order_id: String(rawBody.record.order_id) };
      }
    } else {
      // It's a direct API call (from Dart)
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

    // Admin Supabase client to read device tokens
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: rows, error: dbErr } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('user_id', user_id);

    if (dbErr) throw dbErr;
    if (!rows || rows.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No device tokens for user', sent: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Parse service account & get OAuth2 token
    const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');
    const projectId = sa.project_id ?? Deno.env.get('FIREBASE_PROJECT_ID') ?? '';
    const accessToken = await getFcmAccessToken(sa);
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let sent = 0;
    const errors: string[] = [];

    for (const { token } of rows) {
      try {
        const message = {
          message: {
            token,
            // CRITICAL FOR SAMSUNG/ANDROID 12: Swiping the app away force-stops it.
            // If the app is force-stopped, data-only messages are blocked by the OS.
            // Including 'notification' forces Google Play Services to draw it 
            // on the system tray regardless of the app's background state.
            notification: { title, body },
            data: {
              title,
              body,
              ...(data ?? {}),
            },
            android: {
              priority: 'high',
              notification: {
                channel_id: 'enything_push_channel',
                icon: 'ic_notification',
                default_sound: true,
                default_vibrate_timings: true,
                notification_priority: 'PRIORITY_MAX',
                visibility: 'PUBLIC',
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

        const fcmRes = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(message),
        });

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

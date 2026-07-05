// @ts-nocheck
// This file runs on the Deno runtime (Supabase Edge Functions).
// VS Code may show errors for Deno globals (Deno.*) and URL imports — these are safe to ignore.
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

// ── Edge Function entry point ──────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { audience, title, body, data } = await req.json() as {
      audience: string; // 'All Users', 'Customers', 'Sellers', 'Riders'
      title:   string;
      body:    string;
      data?:   Record<string, string>;
    };

    if (!audience || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'audience, title, and body are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Admin Supabase client to read device tokens
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')             ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    let rows: any[] | null = null;
    let dbErr: any = null;

    // Map UI audience to role column in device_tokens
    if (audience === 'Customers') {
      const res = await supabase.from('device_tokens').select('token, user_id').eq('role', 'customer');
      rows = res.data;
      dbErr = res.error;
    } else if (audience === 'Sellers') {
      const res = await supabase.from('device_tokens').select('token, user_id').eq('role', 'seller');
      rows = res.data;
      dbErr = res.error;
    } else if (audience === 'Riders') {
      const res = await supabase.from('device_tokens').select('token, user_id').eq('role', 'delivery');
      rows = res.data;
      dbErr = res.error;
    } else {
      const res = await supabase.from('device_tokens').select('token, user_id');
      rows = res.data;
      dbErr = res.error;
    }

    if (dbErr) throw dbErr;
    if (!rows || rows.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No device tokens for audience', sent: 0, total: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Insert into notifications table for all targeted users
    const userIds = [...new Set(rows.map((r: any) => r.user_id).filter(Boolean))];
    if (userIds.length > 0) {
      const notifKey = `broadcast_${Date.now()}`;
      const notifPayload = userIds.map((uid) => ({
        user_id: uid,
        title: title,
        body: body,
        notif_key: `${notifKey}_${uid.substring(0, 8)}`,
      }));
      // Batch insert in chunks of 1000
      for (let i = 0; i < notifPayload.length; i += 1000) {
        const chunk = notifPayload.slice(i, i + 1000);
        await supabase.from('notifications').insert(chunk);
      }
    }

    // Parse service account & get OAuth2 token
    const sa         = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');
    const projectId  = sa.project_id ?? Deno.env.get('FIREBASE_PROJECT_ID') ?? '';
    const accessToken = await getFcmAccessToken(sa);
    const fcmUrl      = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let sent = 0;
    const errors: string[] = [];

    // Send sequentially for now (can be optimized with batch sending or Promise.all chunks later)
    for (const { token } of rows) {
      try {
        const message = {
          message: {
            token,
            notification: { title, body },
            ...(data ? { data } : {}),
            android: {
              notification: {
                channel_id:   'enything_push_channel',
                sound:        'default',
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

        const fcmRes = await fetch(fcmUrl, {
          method:  'POST',
          headers: {
            Authorization:  `Bearer ${accessToken}`,
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

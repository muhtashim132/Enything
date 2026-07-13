// supabase/functions/_shared/rbac.ts
// Deploy: supabase functions deploy rbac-helpers
// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ── Get all permission codes for a user ──────────────────────
export async function getUserPermissions(userId: string): Promise<string[]> {
  const { data, error } = await supabaseAdmin
    .rpc('get_user_permissions', { p_user_id: userId });
  if (error) throw new Error(error.message);
  return (data as { code: string }[]).map((r) => r.code);
}

// ── Check a single permission ─────────────────────────────────
export async function hasPermission(
  userId: string,
  permissionCode: string,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .rpc('has_permission', { p_user_id: userId, p_code: permissionCode });
  if (error) return false;
  return data as boolean;
}

// ── Require permission — throws 403 if denied ─────────────────
export async function requirePermission(
  userId: string,
  permissionCode: string,
): Promise<void> {
  const allowed = await hasPermission(userId, permissionCode);
  if (!allowed) {
    throw new Response(
      JSON.stringify({
        error: 'Access Denied',
        required: permissionCode,
      }),
      { status: 403, headers: { 'Content-Type': 'application/json' } },
    );
  }
}

// ── Check if user is Super Admin ──────────────────────────────
export async function isSuperAdmin(userId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .rpc('is_super_admin', { p_user_id: userId });
  if (error) return false;
  return data as boolean;
}

// ── Extract userId from JWT in request ───────────────────────
export function getUserIdFromRequest(req: Request): string | null {
  const auth = req.headers.get('Authorization');
  if (!auth) return null;
  const token = auth.replace('Bearer ', '');
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.sub as string;
  } catch {
    return null;
  }
}

// ── Log an audit event ────────────────────────────────────────
export async function logAudit(params: {
  actorId: string;
  actorRole: string;
  action: string;
  entityType?: string;
  entityId?: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string;
}): Promise<void> {
  await supabaseAdmin.from('audit_logs').insert({
    actor_id: params.actorId,
    actor_role: params.actorRole,
    action: params.action,
    entity_type: params.entityType ?? null,
    entity_id: params.entityId ?? null,
    metadata: params.metadata ?? {},
    ip_address: params.ipAddress ?? null,
  });
}

// ── Example: full Edge Function handler pattern ───────────────
// Usage in any edge function:
//
// import { getUserIdFromRequest, requirePermission, logAudit } from './_shared/rbac.ts';
//
// Deno.serve(async (req) => {
//   const userId = getUserIdFromRequest(req);
//   if (!userId) return new Response('Unauthorized', { status: 401 });
//
//   await requirePermission(userId, 'payments.refund'); // throws 403 if denied
//
//   // ... do the operation ...
//
//   await logAudit({
//     actorId: userId,
//     actorRole: 'finance_manager',
//     action: 'payment_refunded',
//     entityType: 'payment',
//     entityId: paymentId,
//     metadata: { amount, reason },
//   });
//
//   return new Response(JSON.stringify({ success: true }), { status: 200 });
// });

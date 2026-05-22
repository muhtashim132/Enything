import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    if (!supabaseUrl || !supabaseServiceRoleKey) {
      throw new Error('Missing environment variables.');
    }

    // Initialize Supabase Client with service role to delete the user
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey);

    // Initialize a second client using the auth header to verify who is making the request
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAuthClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY') ?? supabaseServiceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await supabaseAuthClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Verify caller is an admin
    const { data: adminUser, error: adminError } = await supabaseAdmin
      .from('admin_users')
      .select('admin_level')
      .eq('id', user.id)
      .maybeSingle();

    if (adminError || !adminUser || (adminUser.admin_level !== 'superadmin' && adminUser.admin_level !== 'admin')) {
      return new Response(JSON.stringify({ error: 'Forbidden. Only admins can perform this action.' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Extract target user ID
    const { target_user_id } = await req.json();

    if (!target_user_id) {
      return new Response(JSON.stringify({ error: 'target_user_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Delete the user from auth.users
    const { data, error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(target_user_id);

    if (deleteError) {
      // If the auth user is already gone, ignore the error and proceed to clean up tables manually.
      if (deleteError.message?.includes('User not found') || deleteError.status === 404) {
        console.log(`Auth user ${target_user_id} not found. Proceeding with manual database cleanup.`);
      } else {
        throw deleteError;
      }
    }

    // Manually delete related records to ensure cleanup even if ON DELETE CASCADE is missing
    await supabaseAdmin.from('shops').delete().eq('seller_id', target_user_id);
    await supabaseAdmin.from('delivery_partners').delete().eq('id', target_user_id);
    await supabaseAdmin.from('admin_users').delete().eq('id', target_user_id);
    await supabaseAdmin.from('profiles').delete().eq('id', target_user_id);

    return new Response(JSON.stringify({ message: 'User successfully deleted', data }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error: any) {
    console.error("Delete user error:", error);
    return new Response(JSON.stringify({ error: error.message || 'Internal Server Error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

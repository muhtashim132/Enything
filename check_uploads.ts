import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = "https://mmdrgcuaetwohflcvzou.supabase.co";
const SUPABASE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY!);

async function run() {
  console.log("--- Recent Storage Objects (raw-product-images & products) ---");
  const { data: storageObjects, error: storageErr } = await supabase
    .from('objects')
    .select('id, bucket_id, name, created_at')
    .in('bucket_id', ['raw-product-images', 'products'])
    .order('created_at', { ascending: false })
    .limit(5)
    // Supabase internal storage tables are usually in the `storage` schema
    // But since we are using the auto-generated SDK we can't easily query `storage.objects` like a normal table 
    // unless we use REST or SQL. Let's just use SQL.
    
}
run();

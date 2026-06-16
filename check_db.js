const { createClient } = require('@supabase/supabase-js');
const SUPABASE_URL = "https://mmdrgcuaetwohflcvzou.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function run() {
  console.log("=== Checking Storage ===");
  const { data: storage } = await supabase.storage.from('products').list('', { limit: 2, sortBy: { column: 'created_at', order: 'desc' } });
  console.log("products bucket:", storage);
  
  const { data: rawStorage } = await supabase.storage.from('raw-product-images').list('', { limit: 2, sortBy: { column: 'created_at', order: 'desc' } });
  console.log("raw-product-images bucket:", rawStorage);
  
  const { data: cleanStorage } = await supabase.storage.from('clean-cutouts').list('', { limit: 2, sortBy: { column: 'created_at', order: 'desc' } });
  console.log("clean-cutouts bucket:", cleanStorage);

  console.log("\n=== Checking Products ===");
  const { data: products } = await supabase.from('products').select('id, name, cutout_url, created_at').order('created_at', { ascending: false }).limit(2);
  console.log("products:", products);
}
run();

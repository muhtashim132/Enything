require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

async function check() {
  const { data, error } = await supabase.from('platform_config').select('*').eq('key', 'platform_fee');
  console.log('PLATFORM FEE DB VALUE:', data);
}
check();

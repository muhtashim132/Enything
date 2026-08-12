const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const envFile = fs.readFileSync('.env', 'utf8');
let url, key;
for (const line of envFile.split('\n')) {
  if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1].trim();
  if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
}

const supabase = createClient(url, key);

async function test() {
  const email = '919999999996@auth.enything.app';
  const password = 'Dummy123';
  
  const { data, error } = await supabase.auth.signInWithPassword({
    email, password
  });
  console.log("Error:", error?.message);
  console.log("User:", data?.user?.id);
  console.log("Session:", !!data?.session);
}
test();

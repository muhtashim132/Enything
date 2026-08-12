const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const config = fs.readFileSync('js/config.js', 'utf8');
const urlMatch = config.match(/supabaseUrl\s*=\s*['"]([^'"]+)['"]/);
const keyMatch = config.match(/supabaseAnonKey\s*=\s*['"]([^'"]+)['"]/);

if (urlMatch && keyMatch) {
    const supabase = createClient(urlMatch[1], keyMatch[1]);
    async function test() {
        const { data, error } = await supabase.from('saved_addresses').select('*').limit(1);
        console.log(data ? data[0] : error);
    }
    test();
} else {
    console.log("Could not parse config");
}

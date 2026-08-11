let supabaseClient;
try {
    if (!window.supabase) {
        throw new Error("window.supabase is not defined. The Supabase CDN script may be blocked or failed to load.");
    }
    supabaseClient = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
} catch (err) {
    console.error("Failed to initialize Supabase client:", err);
    window.supabaseInitError = err;
}

async function getActiveShops() {
    try {
        // Fetch all active shops, then filter out unwanted ones on the client
        // since Supabase JS doesn't support complex OR / ILIKE combinations as easily in a single .neq chain
        const { data, error } = await supabaseClient
            .from('shops')
            .select('id, name, category, banner_image, banner_url, average_rating, is_accepting_orders')
            .eq('is_active', true);
            
        if (error) throw error;
        
        // Filter out Test Shops and Medical/Pharmacy
        const filteredData = data.filter(shop => {
            const name = (shop.name || '').toLowerCase();
            const category = (shop.category || '').toLowerCase();
            
            if (name.includes('test shop') || name.includes('test')) return false;
            if (name.includes('medical') || name.includes('pharmacy')) return false;
            if (category.includes('medical') || category.includes('pharmacy')) return false;
            
            return true;
        });
        
        return filteredData;
    } catch (err) {
        console.error('Error fetching shops:', err);
        return [];
    }
}

async function getShopProducts(shopId) {
    try {
        const { data, error } = await supabaseClient
            .from('products')
            .select('id, name, description, price, original_price, is_available, is_veg, images, shop_id, category, gst_rate_override')
            .eq('shop_id', shopId)
            .eq('is_available', true)
            .eq('is_deleted', false);
            
        if (error) throw error;
        
        // Filter out Test Products
        return data.filter(product => {
            const name = (product.name || '').toLowerCase();
            if (name.includes('test') || name.includes('refund')) return false;
            return true;
        });
    } catch (err) {
        console.error('Error fetching products:', err);
        return [];
    }
}

async function getShopDetails(shopId) {
    try {
        const { data, error } = await supabaseClient
            .from('shops')
            .select('id, name, category, banner_image, banner_url, average_rating, is_accepting_orders')
            .eq('id', shopId)
            .single();
            
        if (error) throw error;
        return data;
    } catch (err) {
        console.error('Error fetching shop details:', err);
        return null;
    }
}

async function getAllActiveProducts(shopIds) {
    if (!shopIds || shopIds.length === 0) return [];
    
    try {
        let allFetchedProducts = [];
        const chunkSize = 10; // Batch into groups of 10 to avoid URL length limits on GET requests
        
        for (let i = 0; i < shopIds.length; i += chunkSize) {
            const chunk = shopIds.slice(i, i + chunkSize);
            const { data, error } = await supabaseClient
                .from('products')
                .select('id, name, description, price, original_price, is_available, is_veg, images, shop_id, category, gst_rate_override')
                .in('shop_id', chunk)
                .eq('is_deleted', false);
                
            if (error) throw error;
            if (data) allFetchedProducts = allFetchedProducts.concat(data);
        }
        
        // Filter out Test Products
        return allFetchedProducts.filter(product => {
            const name = (product.name || '').toLowerCase();
            if (name.includes('test') || name.includes('refund')) return false;
            return true;
        });
    } catch (err) {
        console.error('Error fetching all products:', err);
        throw err; // Actually throw the error so the UI catches it!
    }
}

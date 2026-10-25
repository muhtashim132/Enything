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

// ============================================================================
// ADMIN PORTAL & CATALOG MANAGEMENT HELPER FUNCTIONS
// ============================================================================

async function adminGetAllShops() {
    try {
        const { data, error } = await supabaseClient
            .from('shops')
            .select('id, name, category, address, phone, is_active, is_accepting_orders, is_open, is_manually_closed, banner_image, banner_url, open_time, close_time')
            .order('name', { ascending: true });
        if (error) throw error;
        return data || [];
    } catch (err) {
        console.error('adminGetAllShops error:', err);
        return [];
    }
}

async function adminGetProducts({ shopId = null, category = null, search = '', stockFilter = 'all', vegFilter = 'all', page = 0, limit = 100 } = {}) {
    try {
        let query = supabaseClient
            .from('products')
            .select('id, shop_id, name, description, price, original_price, category, menu_category, is_veg, is_available, weight_per_unit, unit_type, total_quantity, images, is_deleted, created_at, shops(id, name, category)')
            .eq('is_deleted', false);

        if (shopId && shopId !== 'all') {
            query = query.eq('shop_id', shopId);
        }

        if (category && category !== 'all') {
            query = query.eq('category', category);
        }

        if (stockFilter === 'in_stock') {
            query = query.eq('is_available', true);
        } else if (stockFilter === 'out_of_stock') {
            query = query.eq('is_available', false);
        }

        if (vegFilter === 'veg') {
            query = query.eq('is_veg', true);
        } else if (vegFilter === 'non_veg') {
            query = query.eq('is_veg', false);
        }

        if (search && search.trim()) {
            const terms = search.trim().split(/\s+/).filter(Boolean);
            for (const t of terms) {
                query = query.or(`name.ilike.%${t}%,description.ilike.%${t}%,brand.ilike.%${t}%,category.ilike.%${t}%,menu_category.ilike.%${t}%`);
            }
        }

        query = query.order('created_at', { ascending: false }).range(page * limit, (page + 1) * limit - 1);

        const { data, error } = await query;
        if (error) throw error;
        return data || [];
    } catch (err) {
        console.error('adminGetProducts error:', err);
        throw err;
    }
}

async function compressImageFile(file, maxWidth = 1200, quality = 0.82) {
    if (!file || !file.type || !file.type.startsWith('image/') || file.type.includes('svg')) {
        return file;
    }
    return new Promise((resolve) => {
        try {
            const reader = new FileReader();
            reader.onload = (e) => {
                const img = new Image();
                img.onload = () => {
                    let width = img.width;
                    let height = img.height;

                    if (width > maxWidth) {
                        height = Math.round((height * maxWidth) / width);
                        width = maxWidth;
                    }

                    const canvas = document.createElement('canvas');
                    canvas.width = width;
                    canvas.height = height;
                    const ctx = canvas.getContext('2d');
                    ctx.drawImage(img, 0, 0, width, height);

                    canvas.toBlob((blob) => {
                        if (!blob) {
                            resolve(file);
                            return;
                        }
                        const cleanName = (file.name || 'product.jpg').replace(/\.[^/.]+$/, ".jpg");
                        const compressedFile = new File([blob], cleanName, {
                            type: 'image/jpeg',
                            lastModified: Date.now()
                        });
                        console.log(`[ImageCompression] Original: ${(file.size / 1024).toFixed(1)} KB -> Compressed: ${(compressedFile.size / 1024).toFixed(1)} KB`);
                        resolve(compressedFile);
                    }, 'image/jpeg', quality);
                };
                img.onerror = () => resolve(file);
                img.src = e.target.result;
            };
            reader.onerror = () => resolve(file);
            reader.readAsDataURL(file);
        } catch (err) {
            console.warn("Client compression failed, using original file:", err);
            resolve(file);
        }
    });
}

async function adminUploadProductImage(file, shopId) {
    if (!file || !shopId) throw new Error("Image file and shopId are required.");
    if (file.size === 0) throw new Error("Uploaded image is empty or corrupted (0 bytes).");
    if (file.size > 25 * 1024 * 1024) throw new Error("Image file size exceeds maximum limit of 25MB.");
    if (file.type && !file.type.startsWith('image/')) throw new Error("Only valid image formats (JPEG, PNG, WebP) are allowed.");

    try {
        const fileToUpload = await compressImageFile(file);
        const ext = (fileToUpload.name || 'img.jpg').split('.').pop() || 'jpg';
        const cleanExt = ext.toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
        const cleanShopId = String(shopId).replace(/[^a-zA-Z0-9_-]/g, '');
        const filename = `${cleanShopId}/prod_${Date.now()}_${Math.random().toString(36).substring(2, 8)}.${cleanExt}`;

        const { data, error } = await supabaseClient.storage
            .from('products')
            .upload(filename, fileToUpload, {
                cacheControl: '3600',
                upsert: false
            });

        if (error) throw error;

        const { data: publicData } = supabaseClient.storage
            .from('products')
            .getPublicUrl(filename);

        return publicData.publicUrl;
    } catch (err) {
        console.error('adminUploadProductImage error:', err);
        throw err;
    }
}

async function adminCheckShopInFlightOrders(shopId) {
    if (!shopId) return 0;
    try {
        const { data, error } = await supabaseClient
            .from('orders')
            .select('id, status')
            .eq('shop_id', shopId)
            .in('status', ['confirmed', 'preparing', 'ready_for_pickup', 'out_for_delivery']);
        if (error) return 0;
        return (data || []).length;
    } catch (e) {
        return 0;
    }
}

async function adminSaveProduct(productPayload, existingId = null) {
    try {
        if (existingId) {
            const { data, error } = await supabaseClient
                .from('products')
                .update(productPayload)
                .eq('id', existingId)
                .eq('is_deleted', false)
                .select()
                .single();
            if (error) throw error;
            return data;
        } else {
            const { data, error } = await supabaseClient
                .from('products')
                .insert({ ...productPayload, is_deleted: false })
                .select()
                .single();
            if (error) throw error;
            return data;
    }
} catch (err) {
    console.error('adminSaveProduct error:', err);
    throw err;
}
}

async function adminToggleProductAvailability(productId, isAvailable) {
    try {
        const { data, error } = await supabaseClient
            .from('products')
            .update({ is_available: isAvailable })
            .eq('id', productId)
            .select('id, is_available')
            .single();
        if (error) throw error;
        return data;
    } catch (err) {
        console.error('adminToggleProductAvailability error:', err);
        throw err;
    }
}

async function adminSoftDeleteProduct(productId) {
    try {
        const { data, error } = await supabaseClient
            .from('products')
            .update({ is_deleted: true, is_available: false })
            .eq('id', productId)
            .select('id, is_deleted')
            .single();
        if (error) throw error;
        return data;
    } catch (err) {
        console.error('adminSoftDeleteProduct error:', err);
        throw err;
    }
}

async function adminGetShopMenuCategories(shopId) {
    if (!shopId) return [];
    try {
        const { data, error } = await supabaseClient
            .from('products')
            .select('menu_category')
            .eq('shop_id', shopId)
            .eq('is_deleted', false)
            .not('menu_category', 'is', null);

        if (error) throw error;
        const set = new Set();
        (data || []).forEach(row => {
            const mc = (row.menu_category || '').trim();
            if (mc) set.add(mc);
        });
        return Array.from(set).sort();
    } catch (err) {
        console.error('adminGetShopMenuCategories error:', err);
        return [];
    }
}

async function adminToggleShopOpen(shopId, isOpen) {
    try {
        const { data, error } = await supabaseClient
            .from('shops')
            .update({
                is_accepting_orders: isOpen,
                is_open: isOpen,
                is_manually_closed: !isOpen,
                is_active: true
            })
            .eq('id', shopId)
            .select('id, is_accepting_orders, is_open')
            .single();
        if (error) throw error;
        return data;
    } catch (err) {
        console.error('adminToggleShopOpen error:', err);
        throw err;
    }
}

async function adminGetRecentOrders(limit = 30) {
    try {
        const { data, error } = await supabaseClient
            .from('orders')
            .select('id, created_at, status, payment_status, total_amount, shop_id, customer_id, items, shops(name)')
            .order('created_at', { ascending: false })
            .limit(limit);
        if (error) throw error;
        return data || [];
    } catch (err) {
        console.error('adminGetRecentOrders error:', err);
        return [];
    }
}

async function adminGetPlatformStats() {
    try {
        const [shopsRes, prodsRes, ordersRes] = await Promise.all([
            supabaseClient.from('shops').select('id, is_active, is_accepting_orders'),
            supabaseClient.from('products').select('id', { count: 'exact', head: true }).eq('is_deleted', false),
            supabaseClient.from('orders').select('id, total_amount, status, created_at').order('created_at', { ascending: false }).limit(100)
        ]);

        const shops = shopsRes.data || [];
        const activeShops = shops.filter(s => s.is_active && s.is_accepting_orders).length;
        const totalProducts = prodsRes.count || 0;
        const orders = ordersRes.data || [];
        const pendingOrders = orders.filter(o => ['pending', 'awaiting_acceptance', 'preparing', 'ready_for_pickup', 'out_for_delivery'].includes(o.status)).length;
        
        return {
            totalShops: shops.length,
            activeShops,
            totalProducts,
            recentOrdersCount: orders.length,
            pendingOrders
        };
    } catch (err) {
        console.error('adminGetPlatformStats error:', err);
        return {
            totalShops: 0,
            activeShops: 0,
            totalProducts: 0,
            recentOrdersCount: 0,
            pendingOrders: 0
        };
    }
}


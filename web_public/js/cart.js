class Cart {
    constructor() {
        this.items = JSON.parse(localStorage.getItem('cart')) || [];
        this.shopId = localStorage.getItem('cartShopId') || null;
        this.initMobileCartBar();
        this.render();
    }

    initMobileCartBar() {
        if (!document.getElementById('mobile-cart-bar')) {
            const bar = document.createElement('div');
            bar.id = 'mobile-cart-bar';
            bar.className = 'mobile-cart-bar';
            bar.innerHTML = `
                <div class="mobile-cart-info">
                    <span id="mobile-cart-count-text">0 Items</span> | <span id="mobile-cart-total-text">₹0.00</span>
                </div>
                <div class="mobile-cart-action">View Cart <i class="fas fa-arrow-right" style="margin-left: 5px;"></i></div>
            `;
            bar.onclick = () => window.location.href = 'cart.html';
            document.body.appendChild(bar);

            const style = document.createElement('style');
            style.textContent = `
                .mobile-cart-bar {
                    display: none;
                    position: fixed;
                    bottom: 20px;
                    left: 20px;
                    right: 20px;
                    background: var(--accent-color);
                    color: white;
                    padding: 15px 20px;
                    border-radius: 12px;
                    z-index: 9999;
                    box-shadow: 0 10px 25px rgba(59, 130, 246, 0.4);
                    justify-content: space-between;
                    align-items: center;
                    cursor: pointer;
                    font-weight: 600;
                    transition: transform 0.3s ease;
                }
                .mobile-cart-bar:hover {
                    transform: translateY(-2px);
                }
                @media (max-width: 900px) {
                    .mobile-cart-bar.active {
                        display: flex;
                    }
                }
            `;
            document.head.appendChild(style);
        }
    }

    save() {
        localStorage.setItem('cart', JSON.stringify(this.items));
        localStorage.setItem('cartShopId', this.shopId);
        this.render();
    }

    addItem(product, shopId) {
        
        this.shopId = shopId;
        const existingItem = this.items.find(item => item.id === product.id);
        
        if (existingItem) {
            existingItem.quantity += 1;
        } else {
            this.items.push({ ...product, quantity: 1 });
        }
        this.save();
    }

    removeItem(productId) {
        const index = this.items.findIndex(item => item.id === productId);
        if (index !== -1) {
            if (this.items[index].quantity > 1) {
                this.items[index].quantity -= 1;
            } else {
                this.items.splice(index, 1);
            }
            if (this.items.length === 0) {
                this.shopId = null;
            }
            this.save();
        }
    }

    updateQuantity(productId, newQuantity) {
        if (newQuantity < 1) {
            // Remove item completely
            const index = this.items.findIndex(item => item.id === productId);
            if (index !== -1) {
                this.items.splice(index, 1);
                if (this.items.length === 0) {
                    this.shopId = null;
                }
                this.save();
            }
        } else {
            const item = this.items.find(item => item.id === productId);
            if (item) {
                item.quantity = newQuantity;
                this.save();
            }
        }
    }

    clear() {
        this.items = [];
        this.shopId = null;
        this.save();
    }

    getTotal() {
        return this.items.reduce((total, item) => {
            const price = item.price;
            return total + (price * item.quantity);
        }, 0);
    }

    getGSTTotal() {
        return this.items.reduce((total, item) => {
            const price = item.price;
            let rate = 0.05; // Fallback
            if (typeof window.getGstRateForProduct === 'function') {
                rate = window.getGstRateForProduct(
                    item.category,
                    item.shop_category,
                    item.gst_rate_override,
                    price
                );
            }
            const itemGst = price * rate;
            return total + (itemGst * item.quantity);
        }, 0);
    }

    async calculateDeliveryFee() {
        if (!this.shopId || this.items.length === 0) return 30.00; // fallback if no shop

        // Get user location
        let userLocation = localStorage.getItem('user_location');
        if (!userLocation) {
            try {
                userLocation = await new Promise((resolve, reject) => {
                    if (!navigator.geolocation) {
                        reject(new Error("Geolocation not supported"));
                    }
                    navigator.geolocation.getCurrentPosition(
                        pos => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
                        err => reject(err),
                        { timeout: 5000 }
                    );
                });
                localStorage.setItem('user_location', JSON.stringify(userLocation));
            } catch (err) {
                console.warn("Could not get user location. Using default delivery fee.", err);
                return 30.00;
            }
        } else {
            userLocation = JSON.parse(userLocation);
        }

        // Get shop location from Supabase
        if (!window.supabaseClient) return 30.00;
        
        try {
            const { data: shop, error } = await supabaseClient
                .from('shops')
                .select('location')
                .eq('id', this.shopId)
                .single();
                
            if (error || !shop || !shop.location) return 30.00;
            
            // Extract POINT(lon lat) from PostGIS geometry string
            const match = shop.location.match(/POINT\(([-\d.]+) ([-\d.]+)\)/);
            if (!match) return 30.00;
            
            const shopLng = parseFloat(match[1]);
            const shopLat = parseFloat(match[2]);
            
            // Haversine distance
            const R = 6371; // km
            const dLat = (shopLat - userLocation.lat) * Math.PI / 180;
            const dLng = (shopLng - userLocation.lng) * Math.PI / 180;
            const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                    Math.cos(userLocation.lat * Math.PI / 180) * Math.cos(shopLat * Math.PI / 180) *
                    Math.sin(dLng/2) * Math.sin(dLng/2);
            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
            const distanceKm = R * c;
            
            const maxRadiusKm = 15;
            if (distanceKm > maxRadiusKm) return -1; // Out of range
            
            const ratePerKm = 10.0;
            const km = Math.max(1, Math.ceil(distanceKm));
            return km * ratePerKm;
        } catch (err) {
            console.error("Error calculating delivery fee:", err);
            return 30.00;
        }
    }

    async calculateDeliveryTime() {
        if (this.items.length === 0) return 0;
        
        // Base preparation time
        let basePrepTime = 20; 

        // If items are from multiple shops, add extra time for multi-pickup
        const uniqueShops = new Set(this.items.map(item => item.shop_id));
        if (uniqueShops.size > 1) {
            basePrepTime += (uniqueShops.size - 1) * 15;
        }

        // Get user location for distance calculation (approximate delivery time)
        let distanceKm = 3; // Default 3km
        let userLocation = localStorage.getItem('user_location');
        if (userLocation) userLocation = JSON.parse(userLocation);

        if (userLocation && window.supabaseClient && uniqueShops.size > 0) {
            try {
                // Get the first shop's location just for a rough distance estimate
                const shopId = Array.from(uniqueShops)[0];
                const { data: shop } = await supabaseClient
                    .from('shops')
                    .select('location')
                    .eq('id', shopId)
                    .single();

                if (shop && shop.location) {
                    const match = shop.location.match(/POINT\(([-\d.]+) ([-\d.]+)\)/);
                    if (match) {
                        const shopLng = parseFloat(match[1]);
                        const shopLat = parseFloat(match[2]);
                        
                        const R = 6371;
                        const dLat = (shopLat - userLocation.lat) * Math.PI / 180;
                        const dLng = (shopLng - userLocation.lng) * Math.PI / 180;
                        const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                                Math.cos(userLocation.lat * Math.PI / 180) * Math.cos(shopLat * Math.PI / 180) *
                                Math.sin(dLng/2) * Math.sin(dLng/2);
                        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
                        distanceKm = R * c;
                    }
                }
            } catch (e) {
                console.warn("Could not calculate precise time", e);
            }
        }

        // 5 mins per km of driving
        const driveTime = Math.ceil(distanceKm * 5); 
        return basePrepTime + driveTime;
    }

    async render() {
        const cartCount = document.getElementById('cart-count');
        if (cartCount) {
            const totalItems = this.items.reduce((sum, item) => sum + item.quantity, 0);
            cartCount.textContent = totalItems;
            cartCount.style.display = totalItems > 0 ? 'flex' : 'none';
        }

        const cartItemsContainer = document.getElementById('cart-items');
        if (cartItemsContainer) {
            cartItemsContainer.innerHTML = '';
            if (this.items.length === 0) {
                cartItemsContainer.innerHTML = '<p style="text-align:center; color: var(--text-muted); padding: 20px;">Your cart is empty.</p>';
            } else {
                this.items.forEach(item => {
                    const price = item.price;
                    
                    let imageUrl = 'https://via.placeholder.com/50?text=No+Img';
                    if (item.images && item.images.length > 0) {
                        imageUrl = item.images[0];
                    } else if (item.image_url) {
                        imageUrl = item.image_url;
                    }

                    cartItemsContainer.innerHTML += `
                        <div class="cart-item" style="display: flex; align-items: center; justify-content: space-between;">
                            <a href="product.html?id=${item.id}" style="display: flex; align-items: center; gap: 10px; flex: 1; text-decoration: none; color: inherit; overflow: hidden; margin-right: 10px; min-width: 0;">
                                <img src="${imageUrl}" alt="${item.name}" style="width: 50px; height: 50px; object-fit: cover; border-radius: 8px; flex-shrink: 0;">
                                <div class="cart-item-details" style="overflow: hidden; min-width: 0; flex: 1;">
                                    <div style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${item.name}</div>
                                    <div style="font-size: 0.9rem; color: var(--text-muted); margin-top: 4px;">₹${price.toFixed(2)}</div>
                                </div>
                            </a>
                            <div class="cart-item-controls" style="display: flex; align-items: center; gap: 10px; background: rgba(255,255,255,0.05); padding: 5px 10px; border-radius: 8px; flex-shrink: 0;">
                                <button onclick="cart.updateQuantity('${item.id}', ${item.quantity - 1})" style="background:none; border:none; color:white; cursor:pointer; font-size: 1.1rem; padding: 0 5px;">-</button>
                                <span style="font-weight: bold;">${item.quantity}</span>
                                <button onclick="cart.updateQuantity('${item.id}', ${item.quantity + 1})" style="background:none; border:none; color:white; cursor:pointer; font-size: 1.1rem; padding: 0 5px;">+</button>
                            </div>
                        </div>
                    `;
                });
            }
            
            const cartTotal = document.getElementById('cart-total');
            if (cartTotal) {
                const itemTotal = this.getTotal();
                if (itemTotal > 0) {
                    cartTotal.innerHTML = `<div style="text-align: center; color: var(--text-muted); padding: 10px;"><i class="fas fa-spinner fa-spin"></i> Calculating fee...</div>`;
                    
                    const gst = this.getGSTTotal();
                    const deliveryFee = await this.calculateDeliveryFee();
                    const handlingFee = 20.00;
                    
                    let grandTotal = 0;
                    let deliveryHtml = '';
                    if (deliveryFee === -1) {
                        deliveryHtml = `<span style="color: #ef4444; font-weight: 600;">Out of Range</span>`;
                    } else {
                        deliveryHtml = `<span>₹${deliveryFee.toFixed(2)}</span>`;
                        grandTotal = itemTotal + gst + deliveryFee + handlingFee;
                    }
                    
                    const deliveryTime = await this.calculateDeliveryTime();
                    const deliveryTimeHtml = deliveryTime > 0 
                        ? `<div style="font-size: 0.95rem; color: #10b981; display: flex; justify-content: space-between; margin-bottom: 10px; font-weight: 600;">
                               <span><i class="fas fa-clock"></i> Est. Delivery Time</span><span>${deliveryTime} mins</span>
                           </div>`
                        : '';

                    // Inject detailed bill summary
                    cartTotal.innerHTML = `
                        ${deliveryTimeHtml}
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 5px;">
                            <span>Item Total</span><span>₹${itemTotal.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 5px;">
                            <span>Delivery Fee</span>${deliveryHtml}
                        </div>
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 5px;">
                            <span>Handling Fee</span><span>₹${handlingFee.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 10px; border-bottom: 1px dashed var(--glass-border); padding-bottom: 10px;">
                            <span>Taxes (GST)</span><span>₹${gst.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 1.1rem; color: var(--text-main); display: flex; justify-content: space-between; font-weight: 800;">
                            <span>Grand Total</span><span>₹${grandTotal > 0 ? grandTotal.toFixed(2) : '-'}</span>
                        </div>
                    `;
                } else {
                    cartTotal.innerHTML = `₹0.00`;
                }
            }

            const checkoutBtn = document.getElementById('checkout-btn');
            if (checkoutBtn) {
                const deliveryFee = await this.calculateDeliveryFee();
                checkoutBtn.disabled = this.items.length === 0 || deliveryFee === -1;
            }

            // Update mobile cart bar
            const mobileBar = document.getElementById('mobile-cart-bar');
            if (mobileBar) {
                if (this.items.length > 0) {
                    mobileBar.classList.add('active');
                    const totalQty = this.items.reduce((sum, item) => sum + item.quantity, 0);
                    const countText = totalQty === 1 ? '1 Item' : `${totalQty} Items`;
                    const countEl = document.getElementById('mobile-cart-count-text');
                    if (countEl) countEl.textContent = countText;
                    
                    const itemTotal = this.getTotal();
                    const gst = this.getGSTTotal();
                    const deliveryFee = await this.calculateDeliveryFee();
                    const handlingFee = 20.00;
                    
                    if (deliveryFee === -1) {
                         document.getElementById('mobile-cart-total-text').textContent = `Out of range`;
                    } else {
                         const grandTotal = itemTotal + gst + deliveryFee + handlingFee;
                         document.getElementById('mobile-cart-total-text').textContent = `₹${grandTotal.toFixed(2)}`;
                    }
                } else {
                    mobileBar.classList.remove('active');
                }
            }
            
            // Dispatch event for UI components to sync (like product card buttons)
            window.dispatchEvent(new Event('cartUpdated'));
        }
    }
}

const cart = new Cart();
window.addEventListener('DOMContentLoaded', () => {
    cart.render();
});

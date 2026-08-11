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
            bar.onclick = () => window.location.href = 'checkout.html';
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
        if (this.shopId && this.shopId !== shopId) {
            if (confirm("Your cart contains items from another restaurant. Clear cart and add this item?")) {
                this.clear();
            } else {
                return;
            }
        }
        
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

    render() {
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
                        <div class="cart-item" style="display: flex; align-items: center; gap: 10px;">
                            <img src="${imageUrl}" alt="${item.name}" style="width: 50px; height: 50px; object-fit: cover; border-radius: 8px;">
                            <div class="cart-item-details" style="flex: 1;">
                                <div style="font-weight: 600;">${item.name}</div>
                                <div style="font-size: 0.9rem; color: var(--text-muted); margin-top: 4px;">₹${price.toFixed(2)}</div>
                            </div>
                            <div class="cart-item-controls" style="display: flex; align-items: center; gap: 10px; background: rgba(255,255,255,0.05); padding: 5px 10px; border-radius: 8px;">
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
                    const gst = this.getGSTTotal();
                    const deliveryFee = 30.00;
                    const handlingFee = 20.00;
                    const grandTotal = itemTotal + gst + deliveryFee + handlingFee;
                    
                    // Inject detailed bill summary
                    cartTotal.innerHTML = `
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 5px;">
                            <span>Item Total</span><span>₹${itemTotal.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 5px;">
                            <span>Delivery Fee</span><span>₹${deliveryFee.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 5px;">
                            <span>Handling Fee</span><span>₹${handlingFee.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 0.9rem; color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 10px; border-bottom: 1px dashed var(--glass-border); padding-bottom: 10px;">
                            <span>Taxes (GST)</span><span>₹${gst.toFixed(2)}</span>
                        </div>
                        <div style="font-size: 1.1rem; color: var(--text-main); display: flex; justify-content: space-between; font-weight: 800;">
                            <span>Grand Total</span><span>₹${grandTotal.toFixed(2)}</span>
                        </div>
                    `;
                } else {
                    cartTotal.innerHTML = `₹0.00`;
                }
            }

            const checkoutBtn = document.getElementById('checkout-btn');
            if (checkoutBtn) {
                checkoutBtn.disabled = this.items.length === 0;
            }

            // Update mobile cart bar
            const mobileBar = document.getElementById('mobile-cart-bar');
            if (mobileBar) {
                if (this.items.length > 0) {
                    mobileBar.classList.add('active');
                    const countText = this.items.length === 1 ? '1 Item' : `${this.items.length} Items`;
                    
                    const itemTotal = this.getTotal();
                    const gst = this.getGSTTotal();
                    const deliveryFee = 30.00;
                    const handlingFee = 20.00;
                    const grandTotal = itemTotal + gst + deliveryFee + handlingFee;

                    document.getElementById('mobile-cart-count-text').textContent = countText;
                    document.getElementById('mobile-cart-total-text').textContent = `₹${grandTotal.toFixed(2)}`;
                } else {
                    mobileBar.classList.remove('active');
                }
            }
        }
    }
}

const cart = new Cart();
window.addEventListener('DOMContentLoaded', () => {
    cart.render();
});

/**
 * Enything Web - Tax Engine
 * Mimics the logic found in lib/config/tax_config.dart
 */

const CategoryGstRate = {
    // Food
    'Restaurant': 0.05,
    'Fast Food': 0.05,
    'Bakery': 0.05,
    'Sweets & Mithai': 0.05,
    'Tea & Coffee': 0.05,
    'Ice Cream': 0.05,
    'Paan Shop': 0.05,
    
    // Perishables / Raw
    'Fruits & Vegs': 0.00,
    'Butcher': 0.00,
    'Fish & Seafood': 0.00,
    'Dairy & Eggs': 0.05,
    
    // Grocery
    'Grocery': 0.05,
    'Organic': 0.05,
    'Supermarket / Hypermarket': 0.05,
    
    // Beverages
    'Beverages': 0.18,
    
    // Pharmacy
    'Pharmacy': 0.05,
    'Medical Store': 0.05,
    
    // Clothing & Footwear
    'Clothing': 0.05,
    'Footwear': 0.05,
    
    // Electronics
    'Electronics': 0.18,
    'Mobile & Repair': 0.18,
    
    // Jewellery
    'Jewellery': 0.03,
    
    // General Retail
    'Stationery': 0.18,
    'Toys & Games': 0.18,
    'Sports': 0.18,
    'Pet Supplies': 0.18,
    'Salon & Beauty': 0.18,
    'Cosmetics & Beauty': 0.18,
    'Flowers': 0.05,
    'Home Decor': 0.18,
    'Furniture': 0.18,
    'Hardware Store': 0.18,
    'Auto Parts': 0.18,
    'Other': 0.18
};

const DEFAULT_SLAB_THRESHOLD = 2500.0;
const DEFAULT_SLAB_HIGH_RATE = 0.18;

function gstRateForCategory(category, itemPrice) {
    if ((category === 'Clothing' || category === 'Footwear') && itemPrice != null) {
        return itemPrice > DEFAULT_SLAB_THRESHOLD ? DEFAULT_SLAB_HIGH_RATE : 0.05;
    }
    return CategoryGstRate[category] !== undefined ? CategoryGstRate[category] : 0.18;
}

/**
 * Calculates the exact GST rate for a product based on its category and overrides.
 * 
 * @param {string} productCategory - Category of the product itself (if any)
 * @param {string} shopCategory - Category of the shop it belongs to (fallback)
 * @param {number|null} gstRateOverride - A manually enforced GST rate (e.g. 0.12)
 * @param {number} itemPrice - The selling price of the item
 * @returns {number} The decimal GST rate (e.g. 0.05 for 5%)
 */
function getGstRateForProduct(productCategory, shopCategory, gstRateOverride, itemPrice) {
    // 1. Explicit override on the product always wins
    if (gstRateOverride != null) {
        return parseFloat(gstRateOverride);
    }
    
    // 2. Determine base category. Product category takes precedence over Shop category.
    const activeCategory = productCategory || shopCategory || 'Other';
    
    return gstRateForCategory(activeCategory, itemPrice);
}

// Attach to window for global access
window.getGstRateForProduct = getGstRateForProduct;

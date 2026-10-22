# 100x Forensic Edge-Case Audit & Remediation (Product Variant Selection & Cart Flow Fortress)

All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols for product variant selection, cart additions, and buy-now checkouts:

1. **Zero Default Pre-Selection of Smallest Variant**:
   In `ProductDetailSheet` (`lib/widgets/product_detail_sheet.dart`) and `ProductDetailsPage` (`lib/pages/customer/product_details_page.dart`), when a product has variants (`product.variants.isNotEmpty`), `_selectedVariant` MUST NOT blindly default to `product.variants.first` unless that specific item is already actively present in the cart. If the product is not in the cart, `_selectedVariant` MUST be initialized to `null`.

2. **Mandatory Conscious Variant Selection on Buy Now / Add to Cart**:
   Tapping **ADD TO CART** or **BUY NOW** when `product.variants.isNotEmpty && _selectedVariant == null` MUST NOT add or purchase any item. Instead, it MUST invoke `_promptVariantSelection()`:
   - Smoothly expand the sheet if needed via `DraggableScrollableController.animateTo(0.88)`
   - Scroll directly to the variant section container (`_variantKey`) using `Scrollable.ensureVisible(..., alignment: 0.18)`
   - Fire sensory tactile feedback (`SensoryHaptics.error()`)
   - Trigger an elastic pulse animation and glowing border around the variant options
   - Render a leak-proof floating warning banner ("Please Select an Option")

3. **No Disruptive Reverse-Scroll on Selection**:
   When a customer taps any variant chip, the viewport MUST NOT scroll back up to the top of the sheet (`0.0`). The screen must stay focused on the selected variant and the sticky bottom bar, allowing immediate follow-through taps on **BUY NOW** or **ADD TO CART**.

4. **Zero-Friction Flow for Standard Products**:
   For products without variants (`product.variants.isEmpty`), tapping **ADD TO CART** or **BUY NOW** directly proceeds without prompt or delay.

5. **Leak-Proof Overlay Entry Cleanup**:
   Any active warning banner registered in `OverlayEntry` must be dismissed immediately on chip selection and in `dispose()` to prevent floating orphaned UI elements.

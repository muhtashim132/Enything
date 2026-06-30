# Store Assets Guide

This directory is where you should store all the visual assets required to publish your app to the Google Play Store and Apple App Store.

## Android (Google Play Store)
Place your assets in `android/`

### 1. Feature Graphic (`android/feature_graphic/`)
- **Dimensions**: 1024w x 500h (px)
- **Format**: JPEG or 24-bit PNG (no alpha)
- **Purpose**: This is the large banner image shown at the top of your Play Store listing.

### 2. Screenshots (`android/screenshots/`)
- **Dimensions**: Min dimension 320px, Max dimension 3840px. (Common: 1080 x 1920)
- **Ratio**: Cannot be more than 2:1 or 1:2.
- **Quantity**: 2 to 8 screenshots.
- **Format**: JPEG or 24-bit PNG (no alpha)

## iOS (Apple App Store)
Place your assets in `ios/`

### 1. Screenshots (`ios/screenshots/`)
Apple requires specific sizes for different devices.
- **6.5" Display (iPhone Pro Max)**: 1284 x 2778 or 1242 x 2688
- **5.5" Display (iPhone 8 Plus)**: 1242 x 2208 (Required if supporting older devices)
- **Format**: PNG (no alpha) or JPEG.
- **Quantity**: Up to 10 screenshots per device size.

*Tip: You can use tools like AppMockUp or Studio to easily generate these store screenshots from standard app screenshots.*

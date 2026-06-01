import 'package:flutter/material.dart';
import '../pages/splash_page.dart';
import '../pages/auth/role_selection_page.dart';
import '../pages/auth/phone_input_page.dart';
import '../pages/auth/otp_verify_page.dart';
import '../pages/auth/complete_profile_page.dart';
import '../pages/auth/seller_kyc_upload_page.dart';
import '../pages/auth/seller_pending_verification_page.dart';
import '../pages/auth/delivery_kyc_upload_page.dart';
import '../pages/auth/delivery_pending_verification_page.dart';
import '../pages/auth/login_page.dart';
import '../pages/auth/accept_invite_page.dart';
import '../pages/customer/home_page.dart';
import '../pages/customer/restaurant_page.dart';
import '../pages/customer/restaurant_dashboard_page.dart';
import '../pages/customer/product_details_page.dart';
import '../pages/customer/cart_page.dart';
import '../pages/customer/checkout_page.dart';
import '../pages/customer/track_order_page.dart';
import '../pages/customer/order_history_page.dart';
import '../pages/customer/favorites_page.dart';
import '../pages/seller/dashboard_page.dart';
import '../pages/seller/add_product_page.dart';
import '../models/product_model.dart';
import '../pages/seller/manage_products_page.dart';
import '../pages/seller/seller_orders_page.dart';
import '../pages/seller/analytics_page.dart';
import '../pages/seller/ca_report_page.dart';
import '../pages/delivery/dashboard_page.dart';
import '../pages/delivery/earnings_page.dart';
import '../pages/seller/shop_management_page.dart';
import '../pages/settings/profile_settings_page.dart';
import '../pages/legal/terms_of_service_page.dart';
import '../pages/legal/privacy_policy_page.dart';
import '../pages/admin/admin_password_page.dart';
import '../pages/admin/admin_dashboard_page.dart';
import '../pages/settings/faq_support_page.dart';
import '../pages/legal/refund_policy_page.dart';
import '../pages/seller/seller_withdrawals_page.dart';
import '../pages/delivery/rider_withdrawals_page.dart';

class AppRoutes {
  static const String splash = '/';
  static const String roleSelect = '/auth/role';
  static const String phoneAuth = '/auth/phone';
  static const String otpVerify = '/auth/otp';
  static const String completeProfile = '/auth/complete-profile';
  static const String sellerKycUpload = '/auth/seller-kyc';
  static const String sellerPendingVerification = '/auth/seller-pending';
  static const String deliveryKycUpload = '/auth/delivery-kyc';
  static const String deliveryPendingVerification = '/auth/delivery-pending';
  static const String login = '/login';
  static const String acceptAdminInvite = '/auth/accept-admin-invite';
  static const String customerHome = '/customer/home';
  static const String restaurant = '/customer/restaurant';
  static const String restaurantDashboard = '/customer/restaurant-food';
  static const String productDetails = '/customer/product';
  static const String cart = '/customer/cart';
  static const String checkout = '/customer/checkout';
  static const String trackOrder = '/customer/track';
  static const String orderHistory = '/customer/orders';
  static const String favorites = '/customer/favorites';
  static const String sellerDashboard = '/seller/dashboard';
  static const String addProduct = '/seller/add-product';
  static const String manageProducts = '/seller/products';
  static const String sellerOrders = '/seller/orders';
  static const String analytics = '/seller/analytics';
  static const String caReport = '/seller/ca-report';
  static const String deliveryDashboard = '/delivery/dashboard';
  static const String earnings = '/delivery/earnings';
  static const String shopManagement = '/seller/shop-management';
  static const String settings = '/settings';
  static const String terms = '/legal/terms';
  static const String privacy = '/legal/privacy';
  static const String adminPassword      = '/admin/password';
  static const String adminDashboard     = '/admin/dashboard';
  static const String faqSupport         = '/settings/faq-support';
  static const String refundPolicy       = '/legal/refund-policy';
  static const String sellerWithdrawals  = '/seller/withdrawals';
  static const String riderWithdrawals   = '/delivery/withdrawals';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case splash:
        return _build(const SplashPage(), routeSettings);
      case roleSelect:
        return _build(const RoleSelectionPage(), routeSettings);
      case phoneAuth:
        return _build(const PhoneAuthPage(), routeSettings);
      case otpVerify:
        return _build(const OtpVerifyPage(), routeSettings);
      case completeProfile:
        return _build(const CompleteProfilePage(), routeSettings);
      case sellerKycUpload:
        return _build(const SellerKycUploadPage(), routeSettings);
      case sellerPendingVerification:
        return _build(const SellerPendingVerificationPage(), routeSettings);
      case deliveryKycUpload:
        return _build(const DeliveryKycUploadPage(), routeSettings);
      case deliveryPendingVerification:
        return _build(const DeliveryPendingVerificationPage(), routeSettings);
      case login:
        return _build(const LoginPage(), routeSettings);
      case acceptAdminInvite:
        return _build(const AcceptInvitePage(), routeSettings);
      case customerHome:
        return _build(const CustomerHomePage(), routeSettings);
      case restaurant:
        final a = routeSettings.arguments as Map<String, dynamic>?;
        return _build(
            RestaurantPage(shopId: a?['shopId'] ?? ''), routeSettings);
      case restaurantDashboard:
        final b = routeSettings.arguments as Map<String, dynamic>?;
        return _build(
            RestaurantDashboardPage(shopId: b?['shopId'] ?? ''), routeSettings);
      case productDetails:
        final a = routeSettings.arguments as Map<String, dynamic>?;
        return _build(ProductDetailsPage(productId: a?['productId'] ?? ''),
            routeSettings);
      case cart:
        return _build(const CartPage(), routeSettings);
      case checkout:
        return _build(const CheckoutPage(), routeSettings);
      case trackOrder:
        final a = routeSettings.arguments as Map<String, dynamic>?;
        return _build(
            TrackOrderPage(orderId: a?['orderId'] ?? ''), routeSettings);
      case orderHistory:
        return _build(const OrderHistoryPage(), routeSettings);
      case favorites:
        return _build(const FavoritesPage(), routeSettings);
      case sellerDashboard:
        return _build(const SellerDashboardPage(), routeSettings);
      case addProduct:
        final a = routeSettings.arguments as Map<String, dynamic>?;
        return _build(AddProductPage(existingProduct: a?['product'] as ProductModel?), routeSettings);
      case manageProducts:
        return _build(const ManageProductsPage(), routeSettings);
      case sellerOrders:
        return _build(const SellerOrdersPage(), routeSettings);
      case analytics:
        return _build(const AnalyticsPage(), routeSettings);
      case caReport:
        return _build(const CaReportPage(), routeSettings);
      case deliveryDashboard:
        return _build(const DeliveryDashboardPage(), routeSettings);
      case earnings:
        return _build(const EarningsPage(), routeSettings);
      case shopManagement:
        return _build(const ShopManagementPage(), routeSettings);
      case settings:
        return _build(const ProfileSettingsPage(), routeSettings);
      case terms:
        return _build(const TermsOfServicePage(), routeSettings);
      case privacy:
        return _build(const PrivacyPolicyPage(), routeSettings);
      case adminPassword:
        return _build(const AdminPasswordPage(), routeSettings);
      case adminDashboard:
        return _build(const AdminDashboardPage(), routeSettings);
      case faqSupport:
        return _build(const FaqSupportPage(), routeSettings);
      case refundPolicy:
        return _build(const RefundPolicyPage(), routeSettings);
      case sellerWithdrawals:
        return _build(const SellerWithdrawalsPage(), routeSettings);
      case riderWithdrawals:
        return _build(const RiderWithdrawalsPage(), routeSettings);
      default:
        return _build(const SplashPage(), routeSettings);
    }
  }

  static PageRouteBuilder _build(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}

import 'package:flutter/material.dart';

class PermissionModel {
  final String id;
  final String code;
  final String name;
  final String description;
  final String module;
  final DateTime createdAt;

  const PermissionModel({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.module,
    required this.createdAt,
  });

  factory PermissionModel.fromMap(Map<String, dynamic> map) {
    return PermissionModel(
      id: map['id'] as String? ?? '',
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      module: map['module'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'description': description,
        'module': module,
        'created_at': createdAt.toIso8601String(),
      };

  PermissionModel copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? module,
    DateTime? createdAt,
  }) =>
      PermissionModel(
        id: id ?? this.id,
        code: code ?? this.code,
        name: name ?? this.name,
        description: description ?? this.description,
        module: module ?? this.module,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PermissionModel && other.code == code);

  @override
  int get hashCode => code.hashCode;
}

// ── All permission codes as constants ──────────────────────────
class Permissions {
  Permissions._();

  // Dashboard
  static const String dashboardView = 'dashboard.view';

  // Orders
  static const String ordersView = 'orders.view';
  static const String ordersAssign = 'orders.assign';
  static const String ordersCancel = 'orders.cancel';
  static const String ordersRefund = 'orders.refund';
  static const String ordersOverrideStatus = 'orders.override_status';

  // Customers
  static const String customersView = 'customers.view';
  static const String customersEdit = 'customers.edit';
  static const String customersBlock = 'customers.block';

  // Sellers
  static const String sellersView = 'sellers.view';
  static const String sellersApprove = 'sellers.approve';
  static const String sellersReject = 'sellers.reject';
  static const String sellersSuspend = 'sellers.suspend';
  static const String sellersPayouts = 'sellers.payouts';

  // Riders
  static const String ridersView = 'riders.view';
  static const String ridersApprove = 'riders.approve';
  static const String ridersSuspend = 'riders.suspend';
  static const String ridersEarnings = 'riders.earnings';

  // Payments
  static const String paymentsView = 'payments.view';
  static const String paymentsRefund = 'payments.refund';
  static const String paymentsManualAdjustment = 'payments.manual_adjustment';

  // Withdrawals
  static const String withdrawalsView = 'withdrawals.view';
  static const String withdrawalsApprove = 'withdrawals.approve';
  static const String withdrawalsReject = 'withdrawals.reject';

  // Marketing
  static const String marketingView = 'marketing.view';
  static const String marketingSendPush = 'marketing.send_push';
  static const String marketingSendSms = 'marketing.send_sms';
  static const String marketingSendEmail = 'marketing.send_email';

  // Support
  static const String supportView = 'support.view';
  static const String supportReply = 'support.reply';
  static const String supportClose = 'support.close';

  // Finance
  static const String financeView = 'finance.view';
  static const String financeExport = 'finance.export';
  static const String financePayouts = 'finance.payouts';

  // Analytics
  static const String analyticsView = 'analytics.view';
  static const String analyticsExport = 'analytics.export';

  // Settings
  static const String settingsView = 'settings.view';
  static const String settingsEdit = 'settings.edit';

  // Roles
  static const String rolesView = 'roles.view';
  static const String rolesCreate = 'roles.create';
  static const String rolesEdit = 'roles.edit';
  static const String rolesDelete = 'roles.delete';
  static const String rolesAssign = 'roles.assign';

  // Audit
  static const String auditView = 'audit.view';

  // System
  static const String systemBackup = 'system.backup';
  static const String systemRestore = 'system.restore';
  static const String systemMaintenance = 'system.maintenance';

  /// All grouped by module for UI rendering
  static const Map<String, List<String>> grouped = {
    'Dashboard': [dashboardView],
    'Orders': [
      ordersView,
      ordersAssign,
      ordersCancel,
      ordersRefund,
      ordersOverrideStatus
    ],
    'Customers': [customersView, customersEdit, customersBlock],
    'Sellers': [
      sellersView,
      sellersApprove,
      sellersReject,
      sellersSuspend,
      sellersPayouts
    ],
    'Riders': [ridersView, ridersApprove, ridersSuspend, ridersEarnings],
    'Payments': [paymentsView, paymentsRefund, paymentsManualAdjustment],
    'Withdrawals': [withdrawalsView, withdrawalsApprove, withdrawalsReject],
    'Marketing': [
      marketingView,
      marketingSendPush,
      marketingSendSms,
      marketingSendEmail
    ],
    'Support': [supportView, supportReply, supportClose],
    'Finance': [financeView, financeExport, financePayouts],
    'Analytics': [analyticsView, analyticsExport],
    'Settings': [settingsView, settingsEdit],
    'Roles': [rolesView, rolesCreate, rolesEdit, rolesDelete, rolesAssign],
    'Audit': [auditView],
    'System': [systemBackup, systemRestore, systemMaintenance],
  };

  static IconData moduleIcon(String module) {
    switch (module.toLowerCase()) {
      case 'dashboard':
        return Icons.dashboard_rounded;
      case 'orders':
        return Icons.receipt_long_rounded;
      case 'customers':
        return Icons.people_rounded;
      case 'sellers':
        return Icons.store_rounded;
      case 'riders':
        return Icons.delivery_dining_rounded;
      case 'payments':
        return Icons.payment_rounded;
      case 'withdrawals':
        return Icons.account_balance_wallet_rounded;
      case 'marketing':
        return Icons.campaign_rounded;
      case 'support':
        return Icons.support_agent_rounded;
      case 'finance':
        return Icons.account_balance_rounded;
      case 'analytics':
        return Icons.bar_chart_rounded;
      case 'settings':
        return Icons.settings_rounded;
      case 'roles':
        return Icons.admin_panel_settings_rounded;
      case 'audit':
        return Icons.history_rounded;
      case 'system':
        return Icons.dns_rounded;
      default:
        return Icons.lock_rounded;
    }
  }
}

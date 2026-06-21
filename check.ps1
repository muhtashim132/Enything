$tables = 'admin_invitations', 'admin_sessions', 'admin_users', 'coupons', 'customer_favorites', 'customers', 'delivery_kyc_docs', 'delivery_partners', 'notifications', 'order_items', 'orders', 'permissions', 'platform_config', 'prescription_docs', 'products', 'profiles', 'ratings', 'reviews', 'role_permissions', 'roles', 'saved_addresses', 'seller_kyc_docs', 'shops', 'support_tickets', 'tax_config', 'vehicle_change_requests', 'withdrawals'
foreach ($t in $tables) {
    $res = Select-String -Path 'd:\Enything\supabase\migrations\*.sql' -Pattern "CREATE TABLE.*$t"
    if (-not $res) {
        Write-Output "Missing: $t"
    }
}

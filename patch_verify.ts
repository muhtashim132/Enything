    if (cart_group_id) {
      const { data: orders, error } = await supabaseAdmin
        .from('orders')
        .select('grand_total_collected, status, customer_id')
        .eq('cart_group_id', cart_group_id);

SELECT id, status, acceptance_deadline, payment_deadline, created_at 
FROM orders 
ORDER BY created_at DESC 
LIMIT 5;
